import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/registration_result.dart';
import '../models/scan_record.dart';
import '../models/status_message.dart';
import '../services/registration_api_service.dart';
import '../utils/qr_payload_parser.dart';
import '../utils/registration_validator.dart';
import '../utils/scan_gate.dart';

/// Screen state for one scanning session. Both input methods end up in
/// [_submit], which calls the shared
/// [RegistrationApiService.submitRegistrationNumber].
class ScanSessionController extends ChangeNotifier {
  ScanSessionController({
    required RegistrationApiService api,
    required QrPayloadParser parser,
    required Duration scanCooldown,
    this.maxRecent = 30,
    this.onScanAccepted,
    DateTime Function()? clock,
  }) : _api = api,
       _parser = parser,
       _clock = clock ?? DateTime.now,
       _gate = ScanGate(cooldown: scanCooldown, clock: clock);

  final RegistrationApiService _api;
  final QrPayloadParser _parser;
  final DateTime Function() _clock;
  final ScanGate _gate;
  final int maxRecent;

  /// Called when a QR code is accepted for submission (e.g. for haptics).
  final VoidCallback? onScanAccepted;

  static const _multipleCodesKey = '\u0000multiple';

  StatusMessage _status = const StatusMessage.idle();
  final List<ScanRecord> _recent = [];
  bool _manualSubmitting = false;
  bool _scanSubmitting = false;
  BackendHealth _health = BackendHealth.checking;
  Timer? _healthTimer;
  bool _disposed = false;

  StatusMessage get status => _status;
  List<ScanRecord> get recent => List.unmodifiable(_recent);
  bool get manualSubmitting => _manualSubmitting;
  bool get scanSubmitting => _scanSubmitting;
  BackendHealth get health => _health;

  /// Handles one camera frame's QR payloads. Repeated detections of the same
  /// code are dropped by the [ScanGate].
  Future<void> handleQrDetected(List<String> payloads) async {
    final distinct = payloads.map((p) => p.trim()).toSet();
    if (distinct.isEmpty) return;

    if (distinct.length > 1) {
      if (_gate.tryAcquire(_multipleCodesKey)) {
        _setStatus(const StatusMessage.multipleQr());
        _gate.release();
      }
      return;
    }

    final payload = distinct.single;
    if (!_gate.tryAcquire(payload)) return;
    try {
      switch (_parser.parse(payload)) {
        case QrParseFailure(:final reason):
          _setStatus(StatusMessage.invalidQr(reason));
        case QrParseSuccess(:final registrationNumber):
          onScanAccepted?.call();
          _scanSubmitting = true;
          await _submit(registrationNumber, SubmissionSource.qr);
      }
    } finally {
      _scanSubmitting = false;
      _gate.release();
      _notify();
    }
  }

  /// Submits manually typed text. Returns null if a manual submission is
  /// already running.
  Future<RegistrationResult?> submitManual(String rawValue) async {
    if (_manualSubmitting) return null;
    _manualSubmitting = true;
    _notify();
    try {
      return await _submit(rawValue, SubmissionSource.manual);
    } finally {
      _manualSubmitting = false;
      _notify();
    }
  }

  Future<RegistrationResult> _submit(
    String rawValue,
    SubmissionSource source,
  ) async {
    _setStatus(
      StatusMessage.submitting(RegistrationValidator.normalize(rawValue)),
    );

    final result = await _api.submitRegistrationNumber(rawValue);
    if (_disposed) return result;

    _status = StatusMessage.fromResult(result, source);
    if (result.status != RegistrationStatus.invalidInput &&
        result.status != RegistrationStatus.notConfigured) {
      _recent.insert(
        0,
        ScanRecord(
          registrationNumber: result.registrationNumber,
          source: source,
          status: result.status,
          timestamp: _clock(),
        ),
      );
      if (_recent.length > maxRecent) _recent.removeLast();
    }

    if (result.status.isConnectivityProblem) {
      _health = BackendHealth.offline;
      unawaited(refreshHealth());
    } else if (result.isConfirmed) {
      _health = BackendHealth.online;
    }
    _notify();
    return result;
  }

  void reportCameraPermissionDenied() {
    _setStatus(const StatusMessage.cameraPermissionDenied());
  }

  void clearRecent() {
    _recent.clear();
    _notify();
  }

  /// Starts periodic backend health checks.
  void startHealthChecks(Duration interval) {
    _healthTimer?.cancel();
    unawaited(refreshHealth());
    _healthTimer = Timer.periodic(interval, (_) => refreshHealth());
  }

  Future<void> refreshHealth() async {
    final health = await _api.checkHealth();
    if (_disposed) return;
    _health = health;
    _notify();
  }

  void _setStatus(StatusMessage status) {
    _status = status;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _healthTimer?.cancel();
    super.dispose();
  }
}
