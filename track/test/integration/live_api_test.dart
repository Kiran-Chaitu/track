// End-to-end check of the real service against a running backend.
// Skipped unless LIVE_API_BASE_URL is provided, e.g.:
//
//   flutter test test/integration/live_api_test.dart \
//     --dart-define=LIVE_API_BASE_URL=http://127.0.0.1:3000
//
// It submits a random registration number, so point it at a development
// backend, not production.
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:track/config/app_config.dart';
import 'package:track/models/registration_result.dart';
import 'package:track/services/registration_api_service.dart';
import 'package:track/utils/registration_validator.dart';

import '../test_helpers.dart';

const liveUrl = String.fromEnvironment('LIVE_API_BASE_URL');

void main() {
  final skip = liveUrl.isEmpty ? 'LIVE_API_BASE_URL not set' : false;

  test('health, store, duplicate and invalid against a live backend', () async {
    final service = RegistrationApiService(
      config: const AppConfig(apiBaseUrl: liveUrl),
      validator: defaultValidator(),
    );
    addTearDown(service.close);

    expect(await service.checkHealth(), BackendHealth.online);

    final number = 'IT${Random().nextInt(1 << 30).toRadixString(36)}';
    final lower = number.toLowerCase();

    final first = await service.submitRegistrationNumber(' $lower ');
    expect(first.status, RegistrationStatus.stored, reason: '$first');
    expect(first.registrationNumber, number.toUpperCase());
    expect(first.httpStatus, 201);

    final again = await service.submitRegistrationNumber(number);
    expect(again.status, RegistrationStatus.duplicate, reason: '$again');
    expect(again.httpStatus, 200);

    // Bypass client validation to prove the server enforces it too.
    final permissive = RegistrationApiService(
      config: const AppConfig(apiBaseUrl: liveUrl),
      validator: RegistrationValidator(pattern: '.*'),
    );
    addTearDown(permissive.close);
    final bad = await permissive.submitRegistrationNumber('BAD-VALUE!');
    expect(bad.status, RegistrationStatus.invalidInput, reason: '$bad');
    expect(bad.httpStatus, 400);
  }, skip: skip);

  test('unreachable backend is reported as unavailable', () async {
    final service = RegistrationApiService(
      config: const AppConfig(
        apiBaseUrl: 'http://127.0.0.1:9',
        requestTimeout: Duration(seconds: 3),
      ),
      validator: defaultValidator(),
    );
    addTearDown(service.close);
    final result = await service.submitRegistrationNumber('22A91A0501');
    expect(result.status.isConnectivityProblem, isTrue, reason: '$result');
    expect(result.isConfirmed, isFalse);
  }, skip: skip);
}
