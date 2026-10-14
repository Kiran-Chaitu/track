import 'package:flutter_test/flutter_test.dart';
import 'package:track/utils/qr_payload_parser.dart';

import '../test_helpers.dart';

void main() {
  group('plain format (default)', () {
    final parser = QrPayloadParser(validator: defaultValidator());

    test('accepts a bare registration number, normalised', () {
      final result = parser.parse(' 22a91a0501 \n');
      expect(result, isA<QrParseSuccess>());
      expect((result as QrParseSuccess).registrationNumber, '22A91A0501');
    });

    final rejected = {
      'empty': '',
      'whitespace': '   ',
      'null': null,
      'url': 'https://college.example/students/22A91A0501',
      'www': 'www.example.com',
      'json': '{"rollNumber":"22A91A0501"}',
      'array': '["22A91A0501"]',
      'multiple values (comma)': '22A91A0501,22A91A0502',
      'multiple values (newline)': '22A91A0501\n22A91A0502',
      'arbitrary text': 'Hello world',
      'invalid characters': '22A91-A0501',
      'too short': 'AB1',
    };
    rejected.forEach((name, payload) {
      test('rejects $name', () {
        expect(parser.parse(payload), isA<QrParseFailure>());
      });
    });

    test('explains why a link was rejected', () {
      final result = parser.parse('https://example.com') as QrParseFailure;
      expect(result.reason, contains('link'));
    });
  });

  group('json format (opt-in)', () {
    final parser = QrPayloadParser(
      validator: defaultValidator(),
      format: QrPayloadFormat.json,
      jsonKey: 'regNo',
    );

    test('extracts the configured key', () {
      final result = parser.parse('{"regNo": " 22a91a0501 ", "name": "x"}');
      expect((result as QrParseSuccess).registrationNumber, '22A91A0501');
    });

    test('rejects missing key, wrong type and plain text', () {
      for (final payload in [
        '{"rollNumber":"22A91A0501"}',
        '{"regNo": 123}',
        '22A91A0501',
      ]) {
        expect(parser.parse(payload), isA<QrParseFailure>(), reason: payload);
      }
    });
  });

  group('prefixed format (opt-in)', () {
    final parser = QrPayloadParser(
      validator: defaultValidator(),
      format: QrPayloadFormat.prefixed,
      prefix: 'REG:',
    );

    test('strips the prefix case-insensitively', () {
      final result = parser.parse('reg:22a91a0501');
      expect((result as QrParseSuccess).registrationNumber, '22A91A0501');
    });

    test('rejects payloads without the prefix', () {
      expect(parser.parse('22A91A0501'), isA<QrParseFailure>());
    });
  });

  test('QrPayloadFormat.parse falls back to plain', () {
    expect(QrPayloadFormat.parse('JSON'), QrPayloadFormat.json);
    expect(QrPayloadFormat.parse('nonsense'), QrPayloadFormat.plain);
  });
}
