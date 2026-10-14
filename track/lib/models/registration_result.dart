/// Outcome of a submission, as confirmed (or not) by the server.
enum RegistrationStatus {
  /// HTTP 201: the server stored a new registration number.
  stored,

  /// HTTP 200 with `duplicate: true`: already stored; nothing was added.
  duplicate,

  /// Rejected by local validation or by the server (HTTP 400/413).
  invalidInput,

  /// The device could not reach the network (no connectivity / DNS failure).
  networkUnavailable,

  /// The server was unreachable or reported an error (5xx, refused).
  backendUnavailable,

  /// No response within the configured timeout. The server MAY have stored it.
  timeout,

  /// HTTP 401/403.
  unauthorized,

  /// HTTP 429.
  rateLimited,

  /// The server answered, but not in the expected format.
  unexpectedResponse,

  /// API_BASE_URL was not provided at build time.
  notConfigured;

  /// True only when the server confirmed the number is stored.
  bool get isConfirmed => this == stored || this == duplicate;

  /// True when the failure is connectivity-related.
  bool get isConnectivityProblem =>
      this == networkUnavailable ||
      this == backendUnavailable ||
      this == timeout;
}

class RegistrationResult {
  const RegistrationResult({
    required this.status,
    required this.registrationNumber,
    required this.message,
    this.httpStatus,
  });

  final RegistrationStatus status;

  /// The normalised number (as returned by the server when available).
  final String registrationNumber;
  final String message;
  final int? httpStatus;

  bool get isConfirmed => status.isConfirmed;

  @override
  String toString() =>
      'RegistrationResult($status, $registrationNumber, $httpStatus, $message)';
}

/// Reachability of the backend, shown in the app bar.
enum BackendHealth { checking, online, storageIssue, offline, notConfigured }
