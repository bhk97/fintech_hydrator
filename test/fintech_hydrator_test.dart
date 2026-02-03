import 'package:flutter_test/flutter_test.dart';
import 'package:fintech_hydrator/fintech_hydrator.dart';

void main() {
  test('FintechHydrator small payload test', () async {
    const json = '[{"id": 1, "name": "Test"}]';
    final hydrator = FintechHydrator<Map<String, dynamic>>(
      payload: json,
      mapper: (json) => json,
    );

    final events = await hydrator.onData.toList();
    expect(events.length, 1);
    expect(events[0][0]['id'], 1);
  });
}
