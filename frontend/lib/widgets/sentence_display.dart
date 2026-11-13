import 'package:flutter/material.dart';

class SentenceDisplay extends StatelessWidget {
  const SentenceDisplay({
    required this.words,
    required this.completedWords,
    super.key,
  });

  final List<String> words;
  final int completedWords;

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        children: [
          for (var index = 0; index < words.length; index++)
            TextSpan(
              text: '${index == 0 ? '' : ' '}${words[index]}',
              style: TextStyle(
                color: index < completedWords
                    ? Colors.greenAccent.shade200
                    : Colors.grey.shade400,
              ),
            ),
        ],
      ),
      textAlign: TextAlign.center,
      style: const TextStyle(fontSize: 24, height: 1.6),
    );
  }
}
