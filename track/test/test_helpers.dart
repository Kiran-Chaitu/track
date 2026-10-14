import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:track/config/app_config.dart';
import 'package:track/services/registration_api_service.dart';
import 'package:track/utils/registration_validator.dart';

const testConfig = AppConfig(
  apiBaseUrl: 'https://api.example.test',
  requestTimeout: Duration(milliseconds: 200),
);

RegistrationValidator defaultValidator() =>
    RegistrationValidator(pattern: AppConfig.defaultRegistrationPattern);

http.Response jsonResponse(int status, Map<String, Object?> body) =>
    http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json'},
    );

/// A fake backend that mimics the real API (201 new / 200 duplicate) and
/// records every request it receives.
class FakeBackend {
  final stored = <String>{};
  final requests = <http.Request>[];

  /// When set, requests wait for this before being answered.
  Completer<void>? gate;

  late final MockClient client = MockClient((request) async {
    requests.add(request);
    await gate?.future;
    if (request.url.path.endsWith('/api/health')) {
      return jsonResponse(200, {
        'status': 'ok',
        'storage': {'status': 'ok'},
      });
    }
    final number = (jsonDecode(request.body) as Map)['rollNumber'] as String;
    final added = stored.add(number);
    return jsonResponse(added ? 201 : 200, {
      'success': true,
      'message': added
          ? 'Registration number stored successfully'
          : 'Registration number already exists',
      'rollNumber': number,
      'duplicate': !added,
    });
  });

  int get submissionCount =>
      requests.where((r) => r.url.path.endsWith('/roll-numbers')).length;

  RegistrationApiService service({AppConfig config = testConfig}) =>
      RegistrationApiService(
        config: config,
        validator: defaultValidator(),
        client: client,
      );
}

/// A service whose every request fails as if the device were offline.
RegistrationApiService serviceThatFails() => RegistrationApiService(
  config: testConfig,
  validator: defaultValidator(),
  client: MockClient(
    (_) async => throw const SocketException("Failed host lookup: 'x'"),
  ),
);
