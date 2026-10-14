import 'registration_result.dart';

enum SubmissionSource { qr, manual }

/// One entry in the in-memory, current-session history. This is NOT the
/// backend's dataset.
class ScanRecord {
  const ScanRecord({
    required this.registrationNumber,
    required this.source,
    required this.status,
    required this.timestamp,
  });

  final String registrationNumber;
  final SubmissionSource source;
  final RegistrationStatus status;
  final DateTime timestamp;
}
