import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';
import 'src/models.dart';
import 'src/supervisor.dart';

export 'src/models.dart' show HydrationError;

/// High-performance JSON hydrator for fintech payloads.
class FintechHydrator<T> {
  static const int _defaultChunkSize = 20;
  static const int _gatekeeperThresholdBytes = 50 * 1024; // 50KB

  final StreamController<List<T>> _controller = StreamController<List<T>>();
  final List<T> _accumulated = [];

  /// The stream of accumulated data.
  Stream<List<T>> get onData => _controller.stream;

  /// Creates a new hydrator and starts the process.
  FintechHydrator({
    required String payload,
    required T Function(Map<String, dynamic>) mapper,
    int chunkSize = _defaultChunkSize,
  }) {
    if (payload.length < _gatekeeperThresholdBytes) {
      _parseOnMainThread(payload, mapper, chunkSize);
    } else {
      _parseOnWorkerIsolate(payload, mapper, chunkSize);
    }
  }

  void _parseOnMainThread(
    String rawJson,
    T Function(Map<String, dynamic>) mapper,
    int chunkSize,
  ) {
    try {
      final decoded = jsonDecode(rawJson);
      if (decoded is! List) {
        _controller.addError(HydrationError('JSON root must be a List'));
        _controller.close();
        return;
      }

      final List<dynamic> list = decoded;
      for (int i = 0; i < list.length; i += chunkSize) {
        final end = (i + chunkSize < list.length) ? i + chunkSize : list.length;
        final chunk = list.sublist(i, end);

        final mapped = chunk
            .map((e) => mapper(e as Map<String, dynamic>))
            .toList();
        _accumulated.addAll(mapped);
        _controller.add(List<T>.from(_accumulated));
      }
      _controller.close();
    } catch (e, stack) {
      _controller.addError(
        HydrationError('Main thread parse failed', e, stack),
      );
      _controller.close();
    }
  }

  Future<void> _parseOnWorkerIsolate(
    String rawJson,
    T Function(Map<String, dynamic>) mapper,
    int chunkSize,
  ) async {
    final supervisor = IsolateSupervisor();
    await supervisor.ensureReady();

    final receivePort = ReceivePort();

    // Use TransferableTypedData to avoid copying large strings
    final bytes = utf8.encode(rawJson);
    final transferable = TransferableTypedData.fromList([
      Uint8List.fromList(bytes),
    ]);

    final request = HydrationRequest<T>(
      payload: transferable,
      decoder: mapper,
      chunkSize: chunkSize,
      replyPort: receivePort.sendPort,
    );

    StreamSubscription? subscription;
    subscription = receivePort.listen((message) {
      if (message is HydrationResponse) {
        if (message.error != null) {
          _controller.addError(message.error!);
          subscription?.cancel();
          receivePort.close();
          _controller.close();
        } else if (message.isComplete) {
          subscription?.cancel();
          receivePort.close();
          _controller.close();
        } else if (message.items != null) {
          _accumulated.addAll(List<T>.from(message.items!));
          _controller.add(List<T>.from(_accumulated));
        }
      }
    });

    supervisor.send(request);
  }

  /// Global cleanup for the isolate supervisor.
  static void dispose() {
    IsolateSupervisor().dispose();
  }
}
