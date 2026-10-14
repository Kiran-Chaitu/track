import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import '../models/registration_result.dart';
import '../utils/registration_validator.dart';

/// The single submission path used by both the QR scanner and manual entry.
class RegistrationApiService {
  RegistrationApiService({
    required this.config,
    required this.validator,
    http.Client? client,
  }) : _client = client ?? http.Client();

  final AppConfig config;
  final RegistrationValidator validator;
  final http.Client _client;

  /// Requests currently in flight, keyed by normalised number. A second call
  /// for the same number shares the first call's result instead of sending
  /// another request.
  final Map<String, Future<RegistrationResult>> _inFlight = {};

  /// Normalises, validates and submits [rawValue]. Never throws: every failure
  /// is reported as a [RegistrationResult].
  Future<RegistrationResult> submitRegistrationNumber(String rawValue) {
    final validation = validator.validate(rawValue);
    if (!validation.isValid) {
      return Future.value(
        RegistrationResult(
          status: RegistrationStatus.invalidInput,
          registrationNumber: validation.value,
          message: validation.message!,
        ),
      );
    }
    final number = validation.value;

    if (!config.isApiConfigured) {
      return Future.value(
        RegistrationResult(
          status: RegistrationStatus.notConfigured,
          registrationNumber: number,
          message:
              'The server address is not configured. Rebuild the app with '
              '--dart-define=API_BASE_URL=https://your-service.onrender.com',
        ),
      );
    }

    return _inFlight[number] ??= _sendAndRelease(number);
  }

  Future<RegistrationResult> _sendAndRelease(String number) async {
    try {
      return await _send(number);
    } finally {
      _inFlight.remove(number);
    }
  }

  Future<RegistrationResult> _send(String number) async {
    RegistrationResult failure(RegistrationStatus status, String message) =>
        RegistrationResult(
          status: status,
          registrationNumber: number,
          message: message,
        );

    try {
      final response = await _client
          .post(
            config.endpoint('roll-numbers'),
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
              if (config.ingestApiKey.isNotEmpty)
                'X-Api-Key': config.ingestApiKey,
            },
            body: jsonEncode({'rollNumber': number}),
          )
          .timeout(config.requestTimeout);
      return _interpret(response, number);
    } on TimeoutException {
      return failure(
        RegistrationStatus.timeout,
        'The server did not respond in time. It may still have saved the '
        'number; submit again to confirm.',
      );
    } on SocketException catch (e) {
      return _isOffline(e)
          ? failure(
              RegistrationStatus.networkUnavailable,
              'No network connection. Check Wi-Fi or mobile data.',
            )
          : failure(
              RegistrationStatus.backendUnavailable,
              'Could not connect to the server. It may be down or restarting.',
            );
    } on HandshakeException {
      return failure(
        RegistrationStatus.backendUnavailable,
        'A secure connection to the server could not be established.',
      );
    } on http.ClientException {
      return failure(
        RegistrationStatus.networkUnavailable,
        'The request could not be sent. Check your connection.',
      );
    } catch (_) {
      return failure(
        RegistrationStatus.unexpectedResponse,
        'Something went wrong while contacting the server.',
      );
    }
  }

  RegistrationResult _interpret(http.Response response, String number) {
    final body = _decodeObject(response);
    final serverMessage = body?['message'] is String
        ? body!['message'] as String
        : null;
    final serverNumber = body?['rollNumber'] is String
        ? body!['rollNumber'] as String
        : number;
    final code = response.statusCode;

    RegistrationResult result(RegistrationStatus status, String fallback) =>
        RegistrationResult(
          status: status,
          registrationNumber: serverNumber,
          message: serverMessage ?? fallback,
          httpStatus: code,
        );

    if (code == 200 || code == 201) {
      // Only report success when the response body confirms it.
      if (body == null ||
          body['success'] != true ||
          body['duplicate'] is! bool) {
        return result(
          RegistrationStatus.unexpectedResponse,
          'The server response could not be verified.',
        );
      }
      return body['duplicate'] == true
          ? result(
              RegistrationStatus.duplicate,
              'Registration number already exists',
            )
          : result(
              RegistrationStatus.stored,
              'Registration number stored successfully',
            );
    }

    return switch (code) {
      400 || 413 || 415 || 422 => result(
        RegistrationStatus.invalidInput,
        'The server rejected this registration number.',
      ),
      401 || 403 => result(
        RegistrationStatus.unauthorized,
        'This app is not authorised to submit registrations.',
      ),
      429 => result(
        RegistrationStatus.rateLimited,
        'Too many requests. Wait a moment and try again.',
      ),
      >= 500 => result(
        RegistrationStatus.backendUnavailable,
        'The server is temporarily unavailable. Try again shortly.',
      ),
      _ => result(
        RegistrationStatus.unexpectedResponse,
        'Unexpected server response (HTTP $code).',
      ),
    };
  }

  /// Lightweight reachability check used for the app-bar indicator.
  Future<BackendHealth> checkHealth() async {
    if (!config.isApiConfigured) return BackendHealth.notConfigured;
    try {
      final response = await _client
          .get(
            config.endpoint('health'),
            headers: {'Accept': 'application/json'},
          )
          .timeout(const Duration(seconds: 8));
      final body = _decodeObject(response);
      if (response.statusCode != 200 || body?['status'] != 'ok') {
        return BackendHealth.offline;
      }
      final storage = body!['storage'];
      final storageOk = storage is Map && storage['status'] == 'ok';
      return storageOk ? BackendHealth.online : BackendHealth.storageIssue;
    } catch (_) {
      return BackendHealth.offline;
    }
  }

  void close() => _client.close();

  static Map<String, dynamic>? _decodeObject(http.Response response) {
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  /// DNS failures and "network unreachable" usually mean the device itself is
  /// offline; refused/reset connections point at the server instead.
  static bool _isOffline(SocketException e) {
    final text = '${e.message} ${e.osError?.message ?? ''}'.toLowerCase();
    const offlineHints = [
      'failed host lookup',
      'no address associated',
      'network is unreachable',
      'no route to host',
      'nodename nor servname',
    ];
    return offlineHints.any(text.contains);
  }
}
