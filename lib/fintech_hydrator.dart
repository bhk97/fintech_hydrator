import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';
import 'src/models.dart';
import 'src/supervisor.dart';

export 'src/models.dart' show HydrationError, HydrationProgress;

class FintechHydrator<T> {
  static const int _defaultChunkSize = 20;
  static const int _gatekeeperThresholdBytes = 50 * 1024; // 50KB

  final StreamController<List<T>> _controller = StreamController<List<T>>();
  final StreamController<HydrationProgress> _progressController =
      StreamController<HydrationProgress>();
  final List<T> _accumulated = [];

  StreamSubscription? _subscription;
  ReceivePort? _receivePort;
  bool _isCancelled = false;

  Stream<List<T>> get onData => _controller.stream;

  Stream<HydrationProgress> get onProgress => _progressController.stream;

  FintechHydrator({
    String? payload,
    Uint8List? bytes,
    required T Function(Map<String, dynamic>) mapper,
    int chunkSize = _defaultChunkSize,
    int? maxFrameWorkMs,
  }) {
    final Uint8List finalBytes = bytes ?? utf8.encode(payload ?? '');

    if (finalBytes.length < _gatekeeperThresholdBytes) {
      _parseOnMainThread(utf8.decode(finalBytes), mapper, chunkSize);
    } else {
      _parseOnWorkerIsolate(finalBytes, mapper, chunkSize, maxFrameWorkMs);
    }
  }

  void cancel() {
    if (_isCancelled) return;
    _isCancelled = true;
    _subscription?.cancel();
    _receivePort?.close();
    if (!_controller.isClosed) _controller.close();
    if (!_progressController.isClosed) _progressController.close();
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
        _progressController.close();
        return;
      }

      final List<dynamic> list = decoded;
      final int totalItems = list.length;

      for (int i = 0; i < list.length; i += chunkSize) {
        if (_isCancelled) return;

        final end = (i + chunkSize < list.length) ? i + chunkSize : list.length;
        final chunk = list.sublist(i, end);

        final mapped = chunk
            .map((e) => mapper(e as Map<String, dynamic>))
            .toList();
        _accumulated.addAll(mapped);

        // Unmodifiable view instead of deep copy — O(1) vs O(n)
        _controller.add(List<T>.unmodifiable(_accumulated));
        _progressController.add(
          HydrationProgress(
            loadedItems: _accumulated.length,
            totalItems: totalItems,
          ),
        );
      }
      _controller.close();
      _progressController.close();
    } catch (e, stack) {
      _controller.addError(
        HydrationError('Main thread parse failed', e, stack),
      );
      _controller.close();
      _progressController.close();
    }
  }

  Future<void> _parseOnWorkerIsolate(
    Uint8List bytes,
    T Function(Map<String, dynamic>) mapper,
    int chunkSize,
    int? maxFrameWorkMs,
  ) async {
    final supervisor = IsolateSupervisor();
    await supervisor.ensureReady();

    _receivePort = ReceivePort();

    final transferable = TransferableTypedData.fromList([bytes]);

    final request = HydrationRequest<T>(
      payload: transferable,
      decoder: mapper,
      chunkSize: chunkSize,
      maxFrameWorkMs: maxFrameWorkMs,
      replyPort: _receivePort!.sendPort,
    );

    _subscription = _receivePort!.listen((message) {
      if (_isCancelled) return;

      if (message is HydrationResponse) {
        if (message.error != null) {
          _controller.addError(message.error!);
          _cleanup();
        } else if (message.isComplete) {
          _cleanup();
        } else if (message.items != null) {
          _accumulated.addAll(List<T>.from(message.items!));
          _controller.add(List<T>.unmodifiable(_accumulated));

          if (message.totalItems != null) {
            _progressController.add(
              HydrationProgress(
                loadedItems: _accumulated.length,
                totalItems: message.totalItems!,
              ),
            );
          }
        }
      }
    });

    supervisor.send(request);
  }

  void _cleanup() {
    _subscription?.cancel();
    _receivePort?.close();
    if (!_controller.isClosed) _controller.close();
    if (!_progressController.isClosed) _progressController.close();
  }

  static void dispose() {
    IsolateSupervisor().dispose();
  }
}
