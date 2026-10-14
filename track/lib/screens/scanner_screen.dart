import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config/app_config.dart';
import '../controllers/scan_session_controller.dart';
import '../services/registration_api_service.dart';
import '../utils/qr_payload_parser.dart';
import '../utils/registration_validator.dart';
import '../widgets/connection_indicator.dart';
import '../widgets/qr_scanner_view.dart';
import '../widgets/recent_scans_list.dart';
import '../widgets/registration_input.dart';
import '../widgets/submission_status.dart';

class ScannerScreen extends StatefulWidget {
  const ScannerScreen({super.key, required this.config});

  final AppConfig config;

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  late final RegistrationApiService _api;
  late final ScanSessionController _session;

  @override
  void initState() {
    super.initState();
    final config = widget.config;
    final validator = RegistrationValidator(
      pattern: config.registrationPattern,
      maxLength: config.registrationMaxLength,
    );
    _api = RegistrationApiService(config: config, validator: validator);
    _session = ScanSessionController(
      api: _api,
      parser: QrPayloadParser(
        validator: validator,
        format: config.qrFormat,
        jsonKey: config.qrJsonKey,
        prefix: config.qrPrefix,
      ),
      scanCooldown: config.scanCooldown,
      onScanAccepted: HapticFeedback.mediumImpact,
    )..startHealthChecks(config.healthCheckInterval);
  }

  @override
  void dispose() {
    _session.dispose();
    _api.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Registration Scanner'),
        actions: [
          ListenableBuilder(
            listenable: _session,
            builder: (context, _) => ConnectionIndicator(
              health: _session.health,
              onRefresh: _session.refreshHealth,
            ),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Size the scanner from the screen, not the remaining space, so it
            // does not shrink (and relayout the camera) when the keyboard opens.
            final screen = MediaQuery.sizeOf(context);
            final wide =
                constraints.maxWidth >= 640 &&
                constraints.maxWidth > constraints.maxHeight;

            final scanner = ListenableBuilder(
              listenable: _session,
              builder: (context, _) => QrScannerView(
                onDetect: _session.handleQrDetected,
                onPermissionDenied: _session.reportCameraPermissionDenied,
                autoZoom: widget.config.autoZoom,
                busy: _session.scanSubmitting,
              ),
            );
            final controls = _Controls(
              session: _session,
              config: widget.config,
            );

            if (wide) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: scanner,
                    ),
                  ),
                  SizedBox(
                    width: (constraints.maxWidth * 0.45).clamp(300.0, 460.0),
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(0, 12, 12, 24),
                      children: [controls],
                    ),
                  ),
                ],
              );
            }

            final scannerHeight = (screen.height * 0.42)
                .clamp(200.0, 460.0)
                .clamp(0.0, constraints.maxWidth * 1.1);
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              children: [
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 560),
                    child: SizedBox(height: scannerHeight, child: scanner),
                  ),
                ),
                const SizedBox(height: 16),
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 560),
                    child: controls,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Controls extends StatelessWidget {
  const _Controls({required this.session, required this.config});

  final ScanSessionController session;
  final AppConfig config;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: session,
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SubmissionStatus(status: session.status),
          const SizedBox(height: 16),
          RegistrationInput(
            onSubmit: session.submitManual,
            submitting: session.manualSubmitting,
            maxLength: config.registrationMaxLength,
          ),
          const SizedBox(height: 24),
          RecentScansList(
            records: session.recent,
            onClear: session.clearRecent,
          ),
        ],
      ),
    );
  }
}
