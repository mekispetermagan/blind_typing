import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Every glyph has a permanent slot, including letters not yet revealed.
class CurrentWord extends StatelessWidget {
  const CurrentWord({
    required this.word,
    required this.acceptedLetters,
    this.enteredCharacters,
    super.key,
  });

  final String word;
  final int acceptedLetters;
  final List<String>? enteredCharacters;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final entered = enteredCharacters;
    final cursor = entered?.length ?? acceptedLetters;
    final slots = math.max(word.length, entered == null ? cursor : cursor + 1);
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Semantics(
        label: entered?.join() ?? word.substring(0, acceptedLetters),
        child: ExcludeSemantics(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var index = 0; index < slots; index++)
                Container(
                  key: ValueKey('letter-slot-$index'),
                  width: 60,
                  height: 114,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    border: index == cursor
                        ? Border(
                            bottom: BorderSide(color: colors.primary, width: 3),
                          )
                        : null,
                  ),
                  child: Text(
                    entered != null
                        ? (index < entered.length ? entered[index] : ' ')
                        : (index < acceptedLetters ? word[index] : ' '),
                    key: ValueKey('letter-$index'),
                    style: TextStyle(
                      fontSize: 72,
                      color:
                          entered != null &&
                              index >= acceptedLetters &&
                              index < entered.length
                          ? colors.error
                          : colors.onSurface,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
