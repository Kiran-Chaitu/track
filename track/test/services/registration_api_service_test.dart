import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:track/config/app_config.dart';
import 'package:track/models/registration_result.dart';
import 'package:track/services/registration_api_service.dart';

import '../test_helpers.dart';

RegistrationApiService serviceWith(
  Future<http.Response> Function(http.Request) handler, {
  AppConfig config = testConfig,
}) => RegistrationApiService(
  config: config,
  validator: defaultValidator(),
  client: MockClient(handler),
);

void main() {
  test('sends a normalised POST to /api/roll-numbers', () async {
    final backend = FakeBackend();
    final result = await backend.service().submitRegistrationNumber(
      '  22a91a0501 ',
    );

    expect(result.status, RegistrationStatus.stored);
    final request = backend.requests.single;
    expect(request.method, 'POST');
    expect(request.url.toString(), 'https://api.example.test/api/roll-numbers');
    expect(request.headers['Content-Type'], startsWith('application/json'));
    expect(jsonDecode(request.body), {'rollNumber': '22A91A0501'});
    expect(request.headers.containsKey('X-Api-Key'), isFalse);
  });

  test('201 is reported as stored', () async {
    final result = await serviceWith(
      (_) async => jsonResponse(201, {
        'success': true,
        'message': 'Registration number stored successfully',
        'rollNumber': '22A91A0501',
        'duplicate': false,
      }),
    ).submitRegistrationNumber('22A91A0501');

    expect(result.status, RegistrationStatus.stored);
    expect(result.isConfirmed, isTrue);
    expect(result.registrationNumber, '22A91A0501');
  });

  test('200 with duplicate=true is reported as duplicate', () async {
    final result = await serviceWith(
      (_) async => jsonResponse(200, {
        'success': true,
        'message': 'Registration number already exists',
        'rollNumber': '22A91A0501',
        'duplicate': true,
      }),
    ).submitRegistrationNumber('22A91A0501');

    expect(result.status, RegistrationStatus.duplicate);
    expect(result.message, 'Registration number already exists');
  });

  test('2xx without a confirming body is NOT treated as success', () async {
    for (final response in [
      http.Response('<html>OK</html>', 200),
      jsonResponse(201, {'success': true}),
      jsonResponse(200, {'success': false, 'duplicate': false}),
    ]) {
      final result = await serviceWith(
        (_) async => response,
      ).submitRegistrationNumber('22A91A0501');
      expect(result.status, RegistrationStatus.unexpectedResponse);
      expect(result.isConfirmed, isFalse);
    }
  });

  test('invalid input is rejected locally without a request', () async {
    final backend = FakeBackend();
    final service = backend.service();
    for (final input in ['', '   ', '22A-91', 'https://x.y']) {
      final result = await service.submitRegistrationNumber(input);
      expect(result.status, RegistrationStatus.invalidInput, reason: input);
    }
    expect(backend.requests, isEmpty);
  });

  test(
    'server-side 400 is reported as invalid input with its message',
    () async {
      final result = await serviceWith(
        (_) async => jsonResponse(400, {
          'success': false,
          'code': 'ROLL_NUMBER_INVALID',
          'message': 'Registration number format is invalid',
        }),
      ).submitRegistrationNumber('22A91A0501');

      expect(result.status, RegistrationStatus.invalidInput);
      expect(result.message, 'Registration number format is invalid');
    },
  );

  test('maps HTTP error codes', () async {
    final cases = {
      401: RegistrationStatus.unauthorized,
      429: RegistrationStatus.rateLimited,
      500: RegistrationStatus.backendUnavailable,
      503: RegistrationStatus.backendUnavailable,
      404: RegistrationStatus.unexpectedResponse,
    };
    for (final MapEntry(key: code, value: expected) in cases.entries) {
      final result = await serviceWith(
        (_) async => http.Response('', code),
      ).submitRegistrationNumber('22A91A0501');
      expect(result.status, expected, reason: 'HTTP $code');
    }
  });

  test('DNS failure is reported as network unavailable', () async {
    final result = await serviceWith(
      (_) async =>
          throw const SocketException("Failed host lookup: 'api.example.test'"),
    ).submitRegistrationNumber('22A91A0501');
    expect(result.status, RegistrationStatus.networkUnavailable);
  });

  test('refused connection is reported as backend unavailable', () async {
    final result = await serviceWith(
      (_) async => throw const SocketException(
        'Connection refused',
        osError: OSError('Connection refused', 111),
      ),
    ).submitRegistrationNumber('22A91A0501');
    expect(result.status, RegistrationStatus.backendUnavailable);
  });

  test('generic client errors are reported as network problems', () async {
    final result = await serviceWith(
      (_) async => throw http.ClientException('Connection closed'),
    ).submitRegistrationNumber('22A91A0501');
    expect(result.status, RegistrationStatus.networkUnavailable);
  });

  test('slow responses time out', () async {
    final never = Completer<http.Response>();
    final result = await serviceWith(
      (_) => never.future,
    ).submitRegistrationNumber('22A91A0501');
    expect(result.status, RegistrationStatus.timeout);
  });

  test('concurrent submissions of the same number share one request', () async {
    final backend = FakeBackend()..gate = Completer<void>();
    final service = backend.service();

    final first = service.submitRegistrationNumber('22A91A0501');
    final second = service.submitRegistrationNumber(' 22a91a0501 ');
    backend.gate!.complete();
    final results = await Future.wait([first, second]);

    expect(backend.submissionCount, 1);
    expect(
      results.map((r) => r.status),
      everyElement(RegistrationStatus.stored),
    );
  });

  test('the in-flight lock is released after completion and failure', () async {
    var calls = 0;
    final service = serviceWith((_) async {
      calls++;
      if (calls == 1) throw http.ClientException('boom');
      return jsonResponse(201, {
        'success': true,
        'rollNumber': '22A91A0501',
        'duplicate': false,
      });
    });

    expect(
      (await service.submitRegistrationNumber('22A91A0501')).status,
      RegistrationStatus.networkUnavailable,
    );
    expect(
      (await service.submitRegistrationNumber('22A91A0501')).status,
      RegistrationStatus.stored,
    );
    expect(calls, 2);
  });

  test('sends the ingestion key when configured', () async {
    final backend = FakeBackend();
    await backend
        .service(
          config: const AppConfig(
            apiBaseUrl: 'https://api.example.test/',
            ingestApiKey: 'k1',
          ),
        )
        .submitRegistrationNumber('22A91A0501');
    expect(backend.requests.single.headers['X-Api-Key'], 'k1');
  });

  test('reports not configured when API_BASE_URL is missing', () async {
    final result = await serviceWith(
      (_) async => fail('must not send'),
      config: const AppConfig(apiBaseUrl: ''),
    ).submitRegistrationNumber('22A91A0501');
    expect(result.status, RegistrationStatus.notConfigured);
  });

  group('health check', () {
    test('online / storage issue / offline', () async {
      expect(await FakeBackend().service().checkHealth(), BackendHealth.online);

      final storageIssue = await serviceWith(
        (_) async => jsonResponse(200, {
          'status': 'ok',
          'storage': {'status': 'error', 'code': 'STORAGE_CORRUPT'},
        }),
      ).checkHealth();
      expect(storageIssue, BackendHealth.storageIssue);

      final offline = await serviceWith(
        (_) async => throw const SocketException('Failed host lookup'),
      ).checkHealth();
      expect(offline, BackendHealth.offline);
    });
  });

  group('AppConfig', () {
    test('builds endpoints and keeps base paths', () {
      expect(
        const AppConfig(
          apiBaseUrl: 'https://x.onrender.com/',
        ).endpoint('roll-numbers').toString(),
        'https://x.onrender.com/api/roll-numbers',
      );
      expect(
        const AppConfig(
          apiBaseUrl: 'http://10.0.2.2:3000/proxy',
        ).endpoint('health').toString(),
        'http://10.0.2.2:3000/proxy/api/health',
      );
    });

    test('rejects missing or non-http URLs', () {
      for (final url in ['', 'localhost:3000', 'ftp://x', 'not a url']) {
        expect(
          AppConfig(apiBaseUrl: url).isApiConfigured,
          isFalse,
          reason: url,
        );
      }
    });
  });
}
