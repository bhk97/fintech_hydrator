import 'dart:isolate';
import 'package:flutter/services.dart';

/// Represents a request to hydrate a JSON payload.
class HydrationRequest<T> {
  final TransferableTypedData? payload;
  final String? rawJson;
  final T Function(Map<String, dynamic>) decoder;
  final int chunkSize;
  final SendPort replyPort;
  final RootIsolateToken? token;

  HydrationRequest({
    this.payload,
    this.rawJson,
    required this.decoder,
    required this.chunkSize,
    required this.replyPort,
    this.token,
  });
}

/// Represents a chunk of hydrated data or an error.
class HydrationResponse<T> {
  final List<T>? items;
  final HydrationError? error;
  final bool isComplete;
  final bool isHeartbeat;

  HydrationResponse({
    this.items,
    this.error,
    this.isComplete = false,
    this.isHeartbeat = false,
  });

  factory HydrationResponse.chunk(List<T> items) =>
      HydrationResponse(items: items);
  factory HydrationResponse.error(HydrationError error) =>
      HydrationResponse(error: error);
  factory HydrationResponse.complete() => HydrationResponse(isComplete: true);
  factory HydrationResponse.heartbeat() => HydrationResponse(isHeartbeat: true);
}

/// Custom error for hydration failures.
class HydrationError {
  final String message;
  final Object? originalError;
  final StackTrace? stackTrace;

  HydrationError(this.message, [this.originalError, this.stackTrace]);

  @override
  String toString() => 'HydrationError: $message ${originalError ?? ''}';
}
