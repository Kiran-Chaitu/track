import 'dart:convert';

import 'registration_validator.dart';

/// Supported QR payload layouts. Only [plain] is enabled by default; other
/// formats must be explicitly configured (QR_FORMAT build define).
enum QrPayloadFormat {
  /// The whole payload is the registration number, e.g. `22A91A0501`.
  plain,

  /// A JSON object with the number under a configured key,
  /// e.g. `{"rollNumber": "22A91A0501"}`.
  json,

  /// A fixed prefix followed by the number, e.g. `REG:22A91A0501`.
  prefixed;

  static QrPayloadFormat parse(String value) {
    return QrPayloadFormat.values.firstWhere(
      (f) => f.name == value.trim().toLowerCase(),
      orElse: () => QrPayloadFormat.plain,
    );
  }
}

sealed class QrParseResult {
  const QrParseResult();
}

class QrParseSuccess extends QrParseResult {
  const QrParseSuccess(this.registrationNumber);

  /// Normalised (trimmed, upper-cased) and validated.
  final String registrationNumber;
}

class QrParseFailure extends QrParseResult {
  const QrParseFailure(this.reason);

  /// User-facing explanation.
  final String reason;
}

/// Extracts a registration number from a QR payload. Keeping this separate
/// from the scanning UI means the QR format can change without touching it.
///
/// Arbitrary text, links, JSON and multi-value payloads are rejected unless
/// the configured [format] explicitly recognises them.
class QrPayloadParser {
  const QrPayloadParser({
    required this.validator,
    this.format = QrPayloadFormat.plain,
    this.jsonKey = 'rollNumber',
    this.prefix = '',
  });

  final RegistrationValidator validator;
  final QrPayloadFormat format;
  final String jsonKey;
  final String prefix;

  static final _urlLike = RegExp(
    r'^[a-z][a-z0-9+.-]*:|^www\.',
    caseSensitive: false,
  );
  static final _multiValue = RegExp(r'[\s,;|]');

  QrParseResult parse(String? rawPayload) {
    final payload = rawPayload?.trim() ?? '';
    if (payload.isEmpty) {
      return const QrParseFailure('The QR code does not contain any text.');
    }

    final String candidate;
    switch (format) {
      case QrPayloadFormat.plain:
        candidate = payload;
      case QrPayloadFormat.json:
        final extracted = _extractJson(payload);
        if (extracted == null) {
          return QrParseFailure(
            'Expected a JSON QR code with a "$jsonKey" field.',
          );
        }
        candidate = extracted.trim();
      case QrPayloadFormat.prefixed:
        if (prefix.isEmpty ||
            !payload.toUpperCase().startsWith(prefix.toUpperCase())) {
          return QrParseFailure('Expected a QR code starting with "$prefix".');
        }
        candidate = payload.substring(prefix.length).trim();
    }

    if (format == QrPayloadFormat.plain) {
      if (_urlLike.hasMatch(candidate) &&
          candidate.contains(RegExp(r'[:/.]'))) {
        return const QrParseFailure(
          'This QR code contains a link, not a registration number.',
        );
      }
      if (candidate.startsWith('{') || candidate.startsWith('[')) {
        return const QrParseFailure(
          'This QR code contains structured data, not a registration number.',
        );
      }
    }
    if (_multiValue.hasMatch(candidate)) {
      return const QrParseFailure(
        'This QR code contains multiple values. Scan a code with a single '
        'registration number.',
      );
    }

    final validation = validator.validate(candidate);
    if (!validation.isValid) {
      return const QrParseFailure(
        'The QR code does not contain a valid registration number.',
      );
    }
    return QrParseSuccess(validation.value);
  }

  String? _extractJson(String payload) {
    try {
      final decoded = jsonDecode(payload);
      if (decoded is Map<String, dynamic>) {
        final value = decoded[jsonKey];
        if (value is String) return value;
      }
    } on FormatException {
      // Not JSON.
    }
    return null;
  }
}
