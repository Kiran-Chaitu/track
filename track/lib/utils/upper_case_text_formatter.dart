import 'package:flutter/services.dart';

/// Converts typed or pasted text to uppercase as the user types.
class UpperCaseTextFormatter extends TextInputFormatter {
  const UpperCaseTextFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final upper = newValue.text.toUpperCase();
    if (upper == newValue.text) return newValue;

    // Some characters change length when upper-cased (e.g. "ß" -> "SS"); the
    // old selection would then be invalid, so move the caret to the end.
    if (upper.length != newValue.text.length) {
      return TextEditingValue(
        text: upper,
        selection: TextSelection.collapsed(offset: upper.length),
      );
    }
    return newValue.copyWith(text: upper);
  }
}
