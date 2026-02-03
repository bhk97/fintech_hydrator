import 'dart:async';
import 'dart:isolate';
import 'package:flutter/services.dart';
import 'models.dart';
import 'worker.dart';

/// Manages the lifecycle of the long-lived background isolate.
class IsolateSupervisor {
  static final IsolateSupervisor _instance = IsolateSupervisor._internal();
  factory IsolateSupervisor() => _instance;
  IsolateSupervisor._internal();

  Isolate? _isolate;
  SendPort? _sendPort;
  final _readyCompleter = Completer<void>();
  Timer? _heartbeatTimer;
  DateTime _lastHeartbeat = DateTime.now();
  bool _isRestarting = false;

  Future<void> ensureReady() async {
    if (_isolate != null && _sendPort != null && !_isRestarting) return;
    if (_readyCompleter.isCompleted && !_isRestarting) return;

    await _start();
    return _readyCompleter.future;
  }

  Future<void> _start() async {
    final receivePort = ReceivePort();
    final token = RootIsolateToken.instance;

    _isolate = await Isolate.spawn(HydrationWorker.entryPoint, [
      receivePort.sendPort,
      token,
    ], debugName: 'FintechHydratorWorker');

    final completer = Completer<SendPort>();
    receivePort.listen((message) {
      if (message is SendPort) {
        completer.complete(message);
      } else if (message is HydrationResponse && message.isHeartbeat) {
        _lastHeartbeat = DateTime.now();
      }
    });

    _sendPort = await completer.future;
    if (!_readyCompleter.isCompleted) {
      _readyCompleter.complete();
    }
    _isRestarting = false;
    _startHeartbeatMonitor();
  }

  void _startHeartbeatMonitor() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
      if (DateTime.now().difference(_lastHeartbeat).inSeconds > 5) {
        print('FintechHydrator: Isolate heartbeat lost. Restarting...');
        restart();
      }
    });
  }

  Future<void> restart() async {
    if (_isRestarting) return;
    _isRestarting = true;
    dispose();
    await _start();
  }

  void send(HydrationRequest request) {
    _sendPort?.send(request);
  }

  void dispose() {
    _heartbeatTimer?.cancel();
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _sendPort = null;
  }
}
