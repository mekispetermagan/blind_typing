import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pinput/pinput.dart';

class PinField extends StatelessWidget {
  const PinField({
    required this.label,
    required this.length,
    required this.controller,
    required this.onSubmit,
    this.hint,
    this.focusNode,
    this.autofocus = false,
    this.readOnly = false,
    this.textInputAction = TextInputAction.done,
    super.key,
  });

  final String label;
  final String? hint;
  final int length;
  final TextEditingController controller;
  final FocusNode? focusNode;
  final bool autofocus;
  final bool readOnly;
  final TextInputAction textInputAction;
  final VoidCallback onSubmit;

  static const _slotSize = 96.0;
  static const _gap = 8.0;
  static const formMaxWidth = 6 * _slotSize + 5 * _gap + 48;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ExcludeSemantics(
          child: Text(label, style: const TextStyle(fontSize: 28)),
        ),
        const SizedBox(height: 8),
        Semantics(
          label: label,
          hint: hint,
          child: CallbackShortcuts(
            bindings: readOnly
                ? const {}
                : {
                    const SingleActivator(
                      LogicalKeyboardKey.enter,
                      includeRepeats: false,
                    ): onSubmit,
                    const SingleActivator(
                      LogicalKeyboardKey.numpadEnter,
                      includeRepeats: false,
                    ): onSubmit,
                  },
            child: LayoutBuilder(
              builder: (context, constraints) {
                final width =
                    ((constraints.maxWidth - _gap * (length - 1)) / length)
                        .clamp(0.0, _slotSize);
                final height = width.clamp(48.0, _slotSize);
                final borderRadius = BorderRadius.circular(8);
                final pinTheme = PinTheme(
                  width: width,
                  height: height,
                  textStyle: theme.textTheme.titleLarge?.copyWith(
                    color: colors.onSurface,
                    fontSize: height * 44 / _slotSize,
                  ),
                  decoration: BoxDecoration(
                    border: Border.all(color: colors.outline),
                    borderRadius: borderRadius,
                  ),
                );
                return Pinput(
                  length: length,
                  controller: controller,
                  focusNode: focusNode,
                  autofocus: autofocus,
                  readOnly: readOnly,
                  obscureText: true,
                  obscuringWidget: ExcludeSemantics(
                    child: Text('•', style: pinTheme.textStyle),
                  ),
                  showCursor: false,
                  enableSuggestions: false,
                  autofillHints: null,
                  closeKeyboardWhenCompleted: false,
                  keyboardType: TextInputType.number,
                  textInputAction: textInputAction,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  onSubmitted: readOnly ? null : (_) => onSubmit(),
                  mainAxisAlignment: MainAxisAlignment.start,
                  separatorBuilder: (_) => const SizedBox(width: _gap),
                  defaultPinTheme: pinTheme,
                  focusedPinTheme: pinTheme.copyWith(
                    decoration: BoxDecoration(
                      border: Border.all(color: colors.primary, width: 2),
                      borderRadius: borderRadius,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        if (hint case final text?) ...[
          const SizedBox(height: 8),
          ExcludeSemantics(
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(fontSize: 24),
            ),
          ),
        ],
      ],
    );
  }
}
