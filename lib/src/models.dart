import 'dart:isolate';
import 'package:flutter/services.dart';

class HydrationRequest<T> {
  final TransferableTypedData? payload;
  final String? rawJson;
  final T Function(Map<String, dynamic>) decoder;
  final int chunkSize;
  final int? maxFrameWorkMs;
  final SendPort replyPort;
  final RootIsolateToken? token;

  HydrationRequest({
    this.payload,
    this.rawJson,
    required this.decoder,
    required this.chunkSize,
    this.maxFrameWorkMs,
    required this.replyPort,
    this.token,
  });
}

class HydrationResponse<T> {
  final List<T>? items;
  final HydrationError? error;
  final bool isComplete;
  final bool isHeartbeat;
  final int? totalItems;

  HydrationResponse({
    this.items,
    this.error,
    this.isComplete = false,
    this.isHeartbeat = false,
    this.totalItems,
  });

  factory HydrationResponse.chunk(List<T> items, {int? totalItems}) =>
      HydrationResponse(items: items, totalItems: totalItems);
  factory HydrationResponse.error(HydrationError error) =>
      HydrationResponse(error: error);
  factory HydrationResponse.complete() => HydrationResponse(isComplete: true);
  factory HydrationResponse.heartbeat() => HydrationResponse(isHeartbeat: true);
}

class HydrationProgress {
  final int loadedItems;
  final int totalItems;

  double get percentage =>
      totalItems == 0 ? 1.0 : (loadedItems / totalItems).clamp(0.0, 1.0);

  const HydrationProgress({
    required this.loadedItems,
    required this.totalItems,
  });

  @override
  String toString() =>
      'HydrationProgress($loadedItems/$totalItems, ${(percentage * 100).toStringAsFixed(1)}%)';
}

class HydrationError {
  final String message;
  final Object? originalError;
  final StackTrace? stackTrace;

  HydrationError(this.message, [this.originalError, this.stackTrace]);

  @override
  String toString() => 'HydrationError: $message ${originalError ?? ''}';
}
