import 'package:flutter/material.dart';

/// Every glyph has a permanent slot, including letters not yet revealed.
class CurrentWord extends StatelessWidget {
  const CurrentWord({
    required this.word,
    required this.acceptedLetters,
    super.key,
  });

  final String word;
  final int acceptedLetters;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Semantics(
        label: word.substring(0, acceptedLetters),
        child: ExcludeSemantics(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var index = 0; index < word.length; index++)
                Container(
                  key: ValueKey('letter-slot-$index'),
                  width: 60,
                  height: 114,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    border: index == acceptedLetters
                        ? Border(
                            bottom: BorderSide(color: colors.primary, width: 3),
                          )
                        : null,
                  ),
                  child: Text(
                    index < acceptedLetters ? word[index] : ' ',
                    key: ValueKey('letter-$index'),
                    style: TextStyle(fontSize: 72, color: colors.onSurface),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
