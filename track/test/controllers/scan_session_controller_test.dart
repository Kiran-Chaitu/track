import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:track/controllers/scan_session_controller.dart';
import 'package:track/models/registration_result.dart';
import 'package:track/models/scan_record.dart';
import 'package:track/models/status_message.dart';
import 'package:track/utils/qr_payload_parser.dart';

import '../test_helpers.dart';

void main() {
  late FakeBackend backend;
  late DateTime now;
  late ScanSessionController session;
  late int accepted;

  void advance(int ms) => now = now.add(Duration(milliseconds: ms));

  setUp(() {
    backend = FakeBackend();
    now = DateTime(2026);
    accepted = 0;
    session = ScanSessionController(
      api: backend.service(),
      parser: QrPayloadParser(validator: defaultValidator()),
      scanCooldown: const Duration(seconds: 2),
      clock: () => now,
      onScanAccepted: () => accepted++,
    );
  });

  tearDown(() => session.dispose());

  test('a valid QR code is submitted automatically', () async {
    await session.handleQrDetected(['22a91a0501']);

    expect(backend.submissionCount, 1);
    expect(backend.stored, {'22A91A0501'});
    expect(session.status.kind, StatusKind.success);
    expect(session.recent.single.source, SubmissionSource.qr);
    expect(session.recent.single.status, RegistrationStatus.stored);
    expect(accepted, 1);
  });

  test('the same QR code remaining visible is submitted only once', () async {
    await session.handleQrDetected(['22A91A0501']);
    for (var i = 0; i < 20; i++) {
      advance(250);
      await session.handleQrDetected(['22A91A0501']);
    }
    expect(backend.submissionCount, 1);
    expect(session.recent, hasLength(1));
  });

  test('frames arriving while a request is in flight are ignored', () async {
    backend.gate = Completer<void>();
    final first = session.handleQrDetected(['22A91A0501']);
    expect(session.scanSubmitting, isTrue);

    // Same and different codes seen during the request.
    await session.handleQrDetected(['22A91A0501']);
    await session.handleQrDetected(['22A91A0502']);

    backend.gate!.complete();
    await first;
    expect(backend.submissionCount, 1);
    expect(session.scanSubmitting, isFalse);
  });

  test('a different QR code is processed normally', () async {
    await session.handleQrDetected(['22A91A0501']);
    advance(100);
    await session.handleQrDetected(['22A91A0502']);
    expect(backend.stored, {'22A91A0501', '22A91A0502'});
  });

  test(
    're-showing the same code after the cooldown reports a duplicate',
    () async {
      await session.handleQrDetected(['22A91A0501']);
      advance(2500);
      await session.handleQrDetected(['22A91A0501']);

      expect(backend.submissionCount, 2);
      expect(backend.stored, hasLength(1));
      expect(session.status.kind, StatusKind.duplicate);
      expect(session.recent.first.status, RegistrationStatus.duplicate);
    },
  );

  test('invalid QR content is rejected without a request', () async {
    await session.handleQrDetected(['https://example.com/student/1']);
    expect(backend.requests, isEmpty);
    expect(session.status.title, 'Unsupported QR code');
    expect(session.recent, isEmpty);
    expect(accepted, 0);
  });

  test('several QR codes in one frame are not submitted', () async {
    await session.handleQrDetected(['22A91A0501', '22A91A0502']);
    expect(backend.requests, isEmpty);
    expect(session.status.title, 'Multiple QR codes in view');
  });

  test('manual entry uses the same service and normalises case', () async {
    final result = await session.submitManual('  22a91a0501 ');
    expect(result!.status, RegistrationStatus.stored);
    expect(backend.stored, {'22A91A0501'});
    expect(session.recent.single.source, SubmissionSource.manual);

    // The scanner then sees the same number: the server reports a duplicate.
    await session.handleQrDetected(['22A91A0501']);
    expect(session.status.kind, StatusKind.duplicate);
    expect(backend.stored, hasLength(1));
  });

  test('manual submission is blocked while one is in progress', () async {
    backend.gate = Completer<void>();
    final first = session.submitManual('22A91A0501');
    expect(session.manualSubmitting, isTrue);
    expect(await session.submitManual('22A91A0502'), isNull);

    backend.gate!.complete();
    await first;
    expect(session.manualSubmitting, isFalse);
    expect(backend.submissionCount, 1);
  });

  test('empty manual input shows a validation message, not success', () async {
    final result = await session.submitManual('   ');
    expect(result!.status, RegistrationStatus.invalidInput);
    expect(session.status.kind, StatusKind.warning);
    expect(backend.requests, isEmpty);
    expect(session.recent, isEmpty);
  });

  test('network failures are recorded as failed, never as success', () async {
    session.dispose();
    session = ScanSessionController(
      api: serviceThatFails(),
      parser: QrPayloadParser(validator: defaultValidator()),
      scanCooldown: const Duration(seconds: 2),
    );
    await session.handleQrDetected(['22A91A0501']);
    expect(session.status.kind, StatusKind.error);
    expect(session.status.title, 'No network connection');
    expect(session.recent.single.status, RegistrationStatus.networkUnavailable);
  });

  test('clearRecent only clears the local history', () async {
    await session.submitManual('22A91A0501');
    session.clearRecent();
    expect(session.recent, isEmpty);
    expect(backend.stored, {'22A91A0501'});
  });
}
