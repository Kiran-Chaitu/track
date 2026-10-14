/// Why a registration number was rejected.
enum RegistrationValidationError { empty, tooLong, invalidFormat }

class RegistrationValidation {
  const RegistrationValidation._(this.value, this.error, this.message);

  const RegistrationValidation.valid(String value) : this._(value, null, null);

  const RegistrationValidation.invalid(
    String value,
    RegistrationValidationError error,
    String message,
  ) : this._(value, error, message);

  /// The normalised (trimmed, upper-cased) value.
  final String value;
  final RegistrationValidationError? error;
  final String? message;

  bool get isValid => error == null;
}

/// Client-side normalisation and validation. The backend applies the same
/// rules and remains the source of truth.
class RegistrationValidator {
  RegistrationValidator({required String pattern, this.maxLength = 64})
    // Always match the whole value, even if the pattern has no anchors.
    : _pattern = RegExp('^(?:$pattern)\$', unicode: true);

  final RegExp _pattern;
  final int maxLength;

  /// Trims whitespace and upper-cases. Dart's toUpperCase is locale-independent.
  static String normalize(String raw) => raw.trim().toUpperCase();

  RegistrationValidation validate(String raw) {
    final value = normalize(raw);
    if (value.isEmpty) {
      return RegistrationValidation.invalid(
        value,
        RegistrationValidationError.empty,
        'Enter a registration number.',
      );
    }
    if (value.length > maxLength) {
      return RegistrationValidation.invalid(
        value,
        RegistrationValidationError.tooLong,
        'Registration number must be at most $maxLength characters.',
      );
    }
    if (!_pattern.hasMatch(value)) {
      return RegistrationValidation.invalid(
        value,
        RegistrationValidationError.invalidFormat,
        '"$value" is not a valid registration number.',
      );
    }
    return RegistrationValidation.valid(value);
  }
}
