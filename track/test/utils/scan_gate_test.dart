import 'package:flutter_test/flutter_test.dart';
import 'package:track/utils/scan_gate.dart';

void main() {
  late DateTime now;
  late ScanGate gate;

  void advance(int ms) => now = now.add(Duration(milliseconds: ms));

  setUp(() {
    now = DateTime(2026);
    gate = ScanGate(
      cooldown: const Duration(milliseconds: 2000),
      clock: () => now,
    );
  });

  test('blocks everything while a code is being processed', () {
    expect(gate.tryAcquire('A'), isTrue);
    expect(gate.tryAcquire('A'), isFalse);
    expect(gate.tryAcquire('B'), isFalse);
  });

  test('same code that stays in view is never resubmitted', () {
    expect(gate.tryAcquire('A'), isTrue);
    gate.release();
    // The scanner keeps reporting A every 250 ms for 10 seconds.
    for (var i = 0; i < 40; i++) {
      advance(250);
      expect(gate.tryAcquire('A'), isFalse);
    }
  });

  test('same code is accepted again after leaving view for the cooldown', () {
    expect(gate.tryAcquire('A'), isTrue);
    gate.release();
    advance(2001);
    expect(gate.tryAcquire('A'), isTrue);
  });

  test('cooldown restarts when the request finishes', () {
    expect(gate.tryAcquire('A'), isTrue);
    advance(5000); // slow request
    gate.release();
    advance(500);
    expect(gate.tryAcquire('A'), isFalse);
  });

  test('a different code is processed immediately after release', () {
    expect(gate.tryAcquire('A'), isTrue);
    gate.release();
    expect(gate.tryAcquire('B'), isTrue);
  });

  test('reset allows the last code again', () {
    expect(gate.tryAcquire('A'), isTrue);
    gate
      ..release()
      ..reset();
    expect(gate.tryAcquire('A'), isTrue);
  });
}
