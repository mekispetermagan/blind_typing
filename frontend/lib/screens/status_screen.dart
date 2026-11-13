import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../widgets/app_keyboard.dart';

class StatusScreen extends StatelessWidget {
  const StatusScreen({
    required this.message,
    required this.onClose,
    this.onRetry,
    this.onBack,
    super.key,
  });
  final String message;
  final VoidCallback onClose;
  final VoidCallback? onRetry;
  final VoidCallback? onBack;
  @override
  Widget build(BuildContext context) => AppKeyboard(
    onClose: onClose,
    shortcuts: {
      LogicalKeyboardKey.enter: ?onRetry,
      LogicalKeyboardKey.escape: ?onBack,
    },
    child: Scaffold(
      appBar: AppBar(
        title: const Text('Gépírás'),
        actions: [
          IconButton(
            onPressed: onClose,
            tooltip: 'Kilépés (F4)',
            icon: const Icon(Icons.close),
          ),
        ],
      ),
      body: Center(
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 24),
        ),
      ),
    ),
  );
}
