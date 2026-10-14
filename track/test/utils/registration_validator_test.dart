import 'package:flutter_test/flutter_test.dart';
import 'package:track/utils/registration_validator.dart';

import '../test_helpers.dart';

void main() {
  final validator = defaultValidator();

  test('normalises whitespace and case', () {
    final result = validator.validate('  22a91a0501\t');
    expect(result.isValid, isTrue);
    expect(result.value, '22A91A0501');
  });

  test('rejects empty and whitespace-only input', () {
    for (final input in ['', '   ', '\n']) {
      final result = validator.validate(input);
      expect(result.isValid, isFalse);
      expect(result.error, RegistrationValidationError.empty);
    }
  });

  test('rejects values that do not match the pattern', () {
    for (final input in ['22A-91', 'ABC', 'A' * 21, '22A9 1A05', 'ÄBCDE']) {
      expect(validator.validate(input).isValid, isFalse, reason: input);
    }
  });

  test('enforces the hard length limit before the pattern', () {
    final v = RegistrationValidator(pattern: '[A-Z]+', maxLength: 5);
    expect(v.validate('ABCDEF').error, RegistrationValidationError.tooLong);
  });

  test('pattern is configurable and always anchored', () {
    final v = RegistrationValidator(pattern: r'[0-9]{4}/[A-Z]{2}/[0-9]{3}');
    expect(v.validate('2022/cs/001').value, '2022/CS/001');
    expect(v.validate('2022/cs/001').isValid, isTrue);
    expect(v.validate('X2022/CS/001').isValid, isFalse);
    expect(v.validate('2022/CS/0012').isValid, isFalse);
  });
}
