import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'models.dart';

/// The worker that runs in the background isolate.
class HydrationWorker {
  static void entryPoint(List<dynamic> args) {
    final SendPort mainSendPort = args[0];
    final RootIsolateToken? token = args[1];

    if (token != null) {
      BackgroundIsolateBinaryMessenger.ensureInitialized(token);
    }

    final workerReceivePort = ReceivePort();
    mainSendPort.send(workerReceivePort.sendPort);

    // Heartbeat mechanism
    Timer.periodic(const Duration(seconds: 1), (timer) {
      mainSendPort.send(HydrationResponse.heartbeat());
    });

    workerReceivePort.listen((message) async {
      if (message is HydrationRequest) {
        await _handleRequest(message);
      }
    });
  }

  static Future<void> _handleRequest(HydrationRequest request) async {
    try {
      String jsonString;
      if (request.payload != null) {
        final Uint8List bytes = request.payload!.materialize().asUint8List();
        jsonString = utf8.decode(bytes);
      } else {
        jsonString = request.rawJson ?? '';
      }

      final dynamic decoded = jsonDecode(jsonString);

      if (decoded is! List) {
        request.replyPort.send(
          HydrationResponse.error(
            HydrationError('JSON root must be a List for streaming hydration.'),
          ),
        );
        return;
      }

      final List<dynamic> list = decoded;
      final int totalItems = list.length;
      final int chunkSize = request.chunkSize;

      for (int i = 0; i < totalItems; i += chunkSize) {
        final end = (i + chunkSize < totalItems) ? i + chunkSize : totalItems;
        final chunk = list.sublist(i, end);

        try {
          // Map items in the worker isolate.
          final mappedChunk = chunk
              .map((item) => request.decoder(item as Map<String, dynamic>))
              .toList();

          request.replyPort.send(HydrationResponse.chunk(mappedChunk));
        } catch (e, stack) {
          request.replyPort.send(
            HydrationResponse.error(
              HydrationError('Mapping error in chunk $i-$end', e, stack),
            ),
          );
          return;
        }
      }

      request.replyPort.send(HydrationResponse.complete());
    } catch (e, stack) {
      request.replyPort.send(
        HydrationResponse.error(
          HydrationError('Failed to decode JSON', e, stack),
        ),
      );
    }
  }
}
