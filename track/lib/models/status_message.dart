import 'registration_result.dart';
import 'scan_record.dart';

enum StatusKind { idle, working, success, duplicate, warning, error }

/// What the status panel shows.
class StatusMessage {
  const StatusMessage({
    required this.kind,
    required this.title,
    required this.detail,
  });

  const StatusMessage.idle()
    : kind = StatusKind.idle,
      title = 'Ready to scan',
      detail = 'Scan a QR code or type a registration number below.';

  factory StatusMessage.submitting(String number) => StatusMessage(
    kind: StatusKind.working,
    title: 'Submitting $number…',
    detail: 'Waiting for the server to confirm.',
  );

  const StatusMessage.invalidQr(String reason)
    : kind = StatusKind.warning,
      title = 'Unsupported QR code',
      detail = reason;

  const StatusMessage.multipleQr()
    : kind = StatusKind.warning,
      title = 'Multiple QR codes in view',
      detail = 'Show one QR code at a time.';

  const StatusMessage.cameraPermissionDenied()
    : kind = StatusKind.warning,
      title = 'Camera access denied',
      detail =
          'Allow camera access in system settings to scan, or type the '
          'registration number below.';

  factory StatusMessage.fromResult(
    RegistrationResult result,
    SubmissionSource source,
  ) {
    final number = result.registrationNumber;
    final via = source == SubmissionSource.qr ? 'Scanned' : 'Entered';
    return switch (result.status) {
      RegistrationStatus.stored => StatusMessage(
        kind: StatusKind.success,
        title: 'Registration stored',
        detail: '$via $number was saved on the server.',
      ),
      RegistrationStatus.duplicate => StatusMessage(
        kind: StatusKind.duplicate,
        title: 'Already registered',
        detail: '$number is already stored. No new record was created.',
      ),
      RegistrationStatus.invalidInput => StatusMessage(
        kind: StatusKind.warning,
        title: 'Invalid registration number',
        detail: result.message,
      ),
      RegistrationStatus.networkUnavailable => StatusMessage(
        kind: StatusKind.error,
        title: 'No network connection',
        detail: '$number was NOT submitted. ${result.message}',
      ),
      RegistrationStatus.backendUnavailable => StatusMessage(
        kind: StatusKind.error,
        title: 'Server unavailable',
        detail: '$number was NOT confirmed. ${result.message}',
      ),
      RegistrationStatus.timeout => StatusMessage(
        kind: StatusKind.error,
        title: 'Request timed out',
        detail: '$number: ${result.message}',
      ),
      RegistrationStatus.unauthorized => StatusMessage(
        kind: StatusKind.error,
        title: 'Not authorised',
        detail: result.message,
      ),
      RegistrationStatus.rateLimited => StatusMessage(
        kind: StatusKind.warning,
        title: 'Too many requests',
        detail: result.message,
      ),
      RegistrationStatus.unexpectedResponse => StatusMessage(
        kind: StatusKind.error,
        title: 'Unexpected server response',
        detail: '$number was NOT confirmed. ${result.message}',
      ),
      RegistrationStatus.notConfigured => StatusMessage(
        kind: StatusKind.error,
        title: 'Server not configured',
        detail: result.message,
      ),
    };
  }

  final StatusKind kind;
  final String title;
  final String detail;
}
