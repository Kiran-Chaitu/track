import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:track/models/registration_result.dart';
import 'package:track/models/scan_record.dart';
import 'package:track/models/status_message.dart';
import 'package:track/widgets/registration_input.dart';
import 'package:track/widgets/submission_status.dart';

Widget wrap(Widget child) => MaterialApp(
  home: Scaffold(
    body: Padding(padding: const EdgeInsets.all(16), child: child),
  ),
);

RegistrationResult resultFor(RegistrationStatus status, String number) =>
    RegistrationResult(
      status: status,
      registrationNumber: number,
      message: status == RegistrationStatus.invalidInput
          ? 'Enter a registration number.'
          : 'ok',
    );

String fieldText(WidgetTester tester) => tester
    .widget<TextField>(find.byKey(const Key('registrationInput')))
    .controller!
    .text;

void main() {
  testWidgets('typed text is converted to uppercase', (tester) async {
    await tester.pumpWidget(
      wrap(RegistrationInput(onSubmit: (_) async => null, submitting: false)),
    );
    await tester.enterText(
      find.byKey(const Key('registrationInput')),
      '22a91a0501',
    );
    expect(fieldText(tester), '22A91A0501');
    expect(find.text('Submit Registration Number'), findsOneWidget);
    expect(find.text('Enter registration number'), findsOneWidget);
  });

  testWidgets('empty submission shows the validation message', (tester) async {
    final submitted = <String>[];
    await tester.pumpWidget(
      wrap(
        RegistrationInput(
          onSubmit: (value) async {
            submitted.add(value);
            return resultFor(RegistrationStatus.invalidInput, '');
          },
          submitting: false,
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('submitButton')));
    await tester.pump();

    expect(submitted, ['']);
    expect(find.text('Enter a registration number.'), findsOneWidget);
  });

  testWidgets('confirmed result clears the field; failure keeps it', (
    tester,
  ) async {
    var status = RegistrationStatus.networkUnavailable;
    await tester.pumpWidget(
      wrap(
        RegistrationInput(
          onSubmit: (value) async => resultFor(status, value),
          submitting: false,
        ),
      ),
    );
    final field = find.byKey(const Key('registrationInput'));

    await tester.enterText(field, 'abc12345');
    await tester.tap(find.byKey(const Key('submitButton')));
    await tester.pump();
    expect(fieldText(tester), 'ABC12345', reason: 'kept for retry');

    status = RegistrationStatus.stored;
    await tester.tap(find.byKey(const Key('submitButton')));
    await tester.pump();
    expect(fieldText(tester), isEmpty);
  });

  testWidgets('clear button removes the input', (tester) async {
    await tester.pumpWidget(
      wrap(RegistrationInput(onSubmit: (_) async => null, submitting: false)),
    );
    await tester.enterText(find.byKey(const Key('registrationInput')), 'ab12');
    await tester.pump();
    await tester.tap(find.byTooltip('Clear'));
    await tester.pump();
    expect(fieldText(tester), isEmpty);
  });

  testWidgets('button and field are disabled while submitting', (tester) async {
    await tester.pumpWidget(
      wrap(RegistrationInput(onSubmit: (_) async => null, submitting: true)),
    );
    final button = tester.widget<ButtonStyleButton>(
      find.byKey(const Key('submitButton')),
    );
    expect(button.onPressed, isNull);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('registrationInput')))
          .enabled,
      isFalse,
    );
  });

  testWidgets('fits on a small phone without overflow', (tester) async {
    tester.view.physicalSize = const Size(320, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      wrap(
        ListView(
          children: [
            SubmissionStatus(
              status: StatusMessage.fromResult(
                resultFor(RegistrationStatus.backendUnavailable, '22A91A0501'),
                SubmissionSource.qr,
              ),
            ),
            RegistrationInput(onSubmit: (_) async => null, submitting: false),
          ],
        ),
      ),
    );
    expect(tester.takeException(), isNull);
  });
}
