import 'package:flutter/material.dart';

import '../models/registration_result.dart';
import '../utils/upper_case_text_formatter.dart';

/// Manual entry field and submit button. Input is upper-cased as it is typed;
/// the shared service normalises and validates again before sending.
class RegistrationInput extends StatefulWidget {
  const RegistrationInput({
    super.key,
    required this.onSubmit,
    required this.submitting,
    this.maxLength = 64,
  });

  /// Returns the server-confirmed result, or null if the submission was
  /// ignored (already submitting).
  final Future<RegistrationResult?> Function(String value) onSubmit;
  final bool submitting;
  final int maxLength;

  @override
  State<RegistrationInput> createState() => _RegistrationInputState();
}

class _RegistrationInputState extends State<RegistrationInput> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  String? _errorText;

  Future<void> _submit() async {
    if (widget.submitting) return;
    final result = await widget.onSubmit(_controller.text);
    if (!mounted || result == null) return;

    setState(() {
      if (result.isConfirmed) {
        _controller.clear();
        _errorText = null;
      } else if (result.status == RegistrationStatus.invalidInput) {
        _errorText = result.message;
        _focusNode.requestFocus();
      } else {
        _errorText = null; // Keep the text so the user can retry.
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          key: const Key('registrationInput'),
          controller: _controller,
          focusNode: _focusNode,
          enabled: !widget.submitting,
          textCapitalization: TextCapitalization.characters,
          inputFormatters: const [UpperCaseTextFormatter()],
          autocorrect: false,
          enableSuggestions: false,
          maxLength: widget.maxLength,
          textInputAction: TextInputAction.send,
          onSubmitted: (_) => _submit(),
          onChanged: (_) {
            if (_errorText != null) setState(() => _errorText = null);
          },
          style: const TextStyle(
            letterSpacing: 1.2,
            fontWeight: FontWeight.w600,
          ),
          decoration: InputDecoration(
            labelText: 'Registration number',
            hintText: 'Enter registration number',
            prefixIcon: const Icon(Icons.badge_outlined),
            border: const OutlineInputBorder(),
            counterText: '',
            errorText: _errorText,
            suffixIcon: ValueListenableBuilder(
              valueListenable: _controller,
              builder: (context, value, _) => value.text.isEmpty
                  ? const SizedBox.shrink()
                  : IconButton(
                      tooltip: 'Clear',
                      icon: const Icon(Icons.clear),
                      onPressed: widget.submitting
                          ? null
                          : () => setState(() {
                              _controller.clear();
                              _errorText = null;
                            }),
                    ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 52,
          child: FilledButton.icon(
            key: const Key('submitButton'),
            onPressed: widget.submitting ? null : _submit,
            icon: widget.submitting
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  )
                : const Icon(Icons.send),
            label: const Text('Submit Registration Number'),
          ),
        ),
      ],
    );
  }
}
