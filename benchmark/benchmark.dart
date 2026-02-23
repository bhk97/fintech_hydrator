import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:fintech_hydrator/fintech_hydrator.dart';

void main() async {
  print('--- FintechHydrator Performance Benchmarks ---');

  const int itemCount = 10000;
  print('Generating $itemCount items JSON payload...');

  final List<Map<String, dynamic>> items = List.generate(
    itemCount,
    (index) => {
      'id': index,
      'amount': index * 1.5,
      'description':
          'Transaction #$index - Fintech Hydrator Refactor Benchmark',
      'category': 'Finance',
      'is_pending': false,
      'timestamp': DateTime.now().toIso8601String(),
    },
  );
  final String rawJson = jsonEncode(items);
  final double sizeInMb = rawJson.length / (1024 * 1024);
  print('Payload size: ${sizeInMb.toStringAsFixed(2)} MB');

  // Benchmark [1]: Standard jsonDecode
  print('\n[1] Standard jsonDecode (Main Isolate Blocking)');
  final initialMemory = ProcessInfo.currentRss;
  final sw1 = Stopwatch()..start();

  final heart1 = Timer.periodic(const Duration(milliseconds: 16), (timer) {
    // This will likely be blocked and not run
  });

  final List<dynamic> decoded = jsonDecode(rawJson);
  decoded.map((e) => Transaction.fromJson(e)).toList();

  sw1.stop();
  heart1.cancel();
  final peakMemory1 = ProcessInfo.currentRss;

  print('Total Time: ${sw1.elapsedMilliseconds} ms');
  print(
    'Peak Memory: ${((peakMemory1 - initialMemory) / (1024 * 1024)).toStringAsFixed(2)} MB',
  );

  // Benchmark [2]: FintechHydrator
  print('\n[2] FintechHydrator (Background Isolate + Accumulative Stream)');
  final initialMemory2 = ProcessInfo.currentRss;
  final sw2 = Stopwatch()..start();

  int maxJitter = 0;
  DateTime lastHeartbeat = DateTime.now();
  final heart2 = Timer.periodic(const Duration(milliseconds: 16), (timer) {
    final now = DateTime.now();
    final diff = now.difference(lastHeartbeat).inMilliseconds;
    if (diff > maxJitter) maxJitter = diff;
    lastHeartbeat = now;
  });

  int? timeToFirst10;
  final completer = Completer<void>();

  final hydrator = FintechHydrator<Transaction>(
    bytes: utf8.encode(rawJson),
    mapper: Transaction.fromJson,
    chunkSize: 20,
    maxFrameWorkMs: 4,
  );

  hydrator.onData.listen(
    (data) {
      if (timeToFirst10 == null && data.length >= 10) {
        timeToFirst10 = sw2.elapsedMilliseconds;
      }
    },
    onDone: () {
      sw2.stop();
      heart2.cancel();
      completer.complete();
    },
  );

  await completer.future;
  final peakMemory2 = ProcessInfo.currentRss;

  print('Total Time: ${sw2.elapsedMilliseconds} ms');
  print('Time to First 10 items: ${timeToFirst10} ms');
  print('Max Main Isolate Block (Jitter): ${maxJitter} ms');
  print(
    'Peak Memory: ${((peakMemory2 - initialMemory2) / (1024 * 1024)).toStringAsFixed(2)} MB',
  );

  FintechHydrator.dispose();
}

class Transaction {
  final int id;
  final double amount;
  final String description;
  final String category;
  final bool isPending;
  final String timestamp;

  Transaction({
    required this.id,
    required this.amount,
    required this.description,
    required this.category,
    required this.isPending,
    required this.timestamp,
  });

  static Transaction fromJson(Map<String, dynamic> json) {
    return Transaction(
      id: json['id'],
      amount: (json['amount'] as num).toDouble(),
      description: json['description'],
      category: json['category'],
      isPending: json['is_pending'] ?? false,
      timestamp: json['timestamp'] ?? '',
    );
  }
}
