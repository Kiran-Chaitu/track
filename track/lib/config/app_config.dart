import '../utils/qr_payload_parser.dart';

/// Build-time configuration, supplied with `--dart-define` or
/// `--dart-define-from-file=env/dev.json`. See README for all keys.
class AppConfig {
  const AppConfig({
    required this.apiBaseUrl,
    this.ingestApiKey = '',
    this.registrationPattern = defaultRegistrationPattern,
    this.registrationMaxLength = 64,
    this.requestTimeout = const Duration(seconds: 10),
    this.scanCooldown = const Duration(milliseconds: 2500),
    this.qrFormat = QrPayloadFormat.plain,
    this.qrJsonKey = 'rollNumber',
    this.qrPrefix = '',
    this.autoZoom = false,
    this.healthCheckInterval = const Duration(seconds: 30),
  });

  /// Default accepted format after trimming and upper-casing.
  /// Must match the backend's ROLL_NUMBER_PATTERN.
  static const String defaultRegistrationPattern = r'^[A-Z0-9]{4,20}$';

  factory AppConfig.fromEnvironment() {
    const pattern = String.fromEnvironment('REG_PATTERN');
    return AppConfig(
      apiBaseUrl: const String.fromEnvironment('API_BASE_URL'),
      ingestApiKey: const String.fromEnvironment('INGEST_API_KEY'),
      registrationPattern: pattern.isEmpty
          ? defaultRegistrationPattern
          : pattern,
      registrationMaxLength: const int.fromEnvironment(
        'REG_MAX_LENGTH',
        defaultValue: 64,
      ),
      requestTimeout: const Duration(
        seconds: int.fromEnvironment(
          'REQUEST_TIMEOUT_SECONDS',
          defaultValue: 10,
        ),
      ),
      scanCooldown: const Duration(
        milliseconds: int.fromEnvironment(
          'SCAN_COOLDOWN_MS',
          defaultValue: 2500,
        ),
      ),
      qrFormat: QrPayloadFormat.parse(
        const String.fromEnvironment('QR_FORMAT', defaultValue: 'plain'),
      ),
      qrJsonKey: const String.fromEnvironment(
        'QR_JSON_KEY',
        defaultValue: 'rollNumber',
      ),
      qrPrefix: const String.fromEnvironment('QR_PREFIX'),
      autoZoom: const bool.fromEnvironment('SCANNER_AUTO_ZOOM'),
    );
  }

  final String apiBaseUrl;
  final String ingestApiKey;
  final String registrationPattern;
  final int registrationMaxLength;
  final Duration requestTimeout;
  final Duration scanCooldown;
  final QrPayloadFormat qrFormat;
  final String qrJsonKey;
  final String qrPrefix;

  /// Android-only ML Kit zoom suggestions (bounded by the library).
  final bool autoZoom;
  final Duration healthCheckInterval;

  /// The validated API base URI, or null if [apiBaseUrl] is missing/invalid.
  Uri? get apiBaseUri {
    final trimmed = apiBaseUrl.trim();
    if (trimmed.isEmpty) return null;
    final uri = Uri.tryParse(trimmed);
    if (uri == null ||
        !(uri.scheme == 'http' || uri.scheme == 'https') ||
        uri.host.isEmpty) {
      return null;
    }
    final path = uri.path.endsWith('/')
        ? uri.path.substring(0, uri.path.length - 1)
        : uri.path;
    return uri.replace(path: path);
  }

  bool get isApiConfigured => apiBaseUri != null;

  /// Builds `<base>/api/<path>`, keeping any base path (e.g. behind a proxy).
  Uri endpoint(String path) {
    final base = apiBaseUri;
    if (base == null) {
      throw StateError('API_BASE_URL is not configured');
    }
    return base.replace(path: '${base.path}/api/$path');
  }
}
