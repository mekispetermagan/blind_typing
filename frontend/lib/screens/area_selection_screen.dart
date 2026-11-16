import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/area.dart';
import '../models/menu.dart';
import '../services/audio_service.dart';
import '../services/speech_coordinator.dart';
import '../widgets/app_keyboard.dart';
import '../widgets/menu_list.dart';
import 'status_screen.dart';

class AreaSelectionScreen extends StatefulWidget {
  const AreaSelectionScreen({
    required this.role,
    required this.audio,
    required this.onSelect,
    required this.onClose,
    super.key,
  });
  final UserRole role;
  final AudioService audio;
  final ValueChanged<AppArea> onSelect;
  final VoidCallback onClose;

  @override
  State<AreaSelectionScreen> createState() => _AreaSelectionScreenState();
}

class _AreaSelectionScreenState extends State<AreaSelectionScreen> {
  late final areas = areasForRole(widget.role);
  late final speech = SpeechCoordinator(widget.audio);
  late final items = [
    for (final area in areas)
      MenuNode(
        id: 'area_${area.name}',
        title: switch (area) {
          AppArea.admin => 'Adminisztrátor',
          AppArea.trainer => 'Oktató',
          AppArea.student => 'Tanuló',
        },
        command: MenuCommand.areaSelector,
      ),
  ];
  int selected = 0;
  bool loading = true;
  bool failed = false;

  @override
  void initState() {
    super.initState();
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    setState(() {
      loading = true;
      failed = false;
    });
    try {
      await widget.audio.initialize([
        'assets/audio/menu_area_selection.wav',
        ...items.map((item) => item.audioAsset),
      ]);
      if (!mounted) return;
      setState(() => loading = false);
      final token = speech.begin();
      unawaited(
        speech.sequence(token, [
          'assets/audio/menu_area_selection.wav',
          items[selected].audioAsset,
        ]),
      );
    } catch (_) {
      if (mounted)
        setState(() {
          loading = false;
          failed = true;
        });
    }
  }

  void _repeat() {
    final token = speech.begin();
    unawaited(speech.say(token, items[selected].audioAsset));
  }

  void _move(int delta) {
    setState(() => selected = (selected + delta).clamp(0, items.length - 1));
    _repeat();
  }

  void _activate(int index) {
    speech.begin();
    widget.onSelect(areas[index]);
  }

  @override
  void dispose() {
    speech.begin();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Gépírás',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: Colors.teal,
        brightness: Brightness.dark,
      ),
      fontFamily: 'DejaVuSansMono',
    ),
    home: loading
        ? StatusScreen(message: 'Betöltés…', onClose: widget.onClose)
        : failed
        ? StatusScreen(
            message: 'A területválasztó nem tölthető be. Enter: újrapróbálás.',
            onClose: widget.onClose,
            onRetry: _initialize,
          )
        : AppKeyboard(
            onClose: widget.onClose,
            shortcuts: {
              LogicalKeyboardKey.arrowUp: () => _move(-1),
              LogicalKeyboardKey.arrowDown: () => _move(1),
              LogicalKeyboardKey.enter: () => _activate(selected),
              LogicalKeyboardKey.numpadEnter: () => _activate(selected),
              LogicalKeyboardKey.arrowRight: () => _activate(selected),
              LogicalKeyboardKey.f1: _repeat,
            },
            child: Scaffold(
              appBar: AppBar(title: const Text('Területválasztó')),
              body: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Válassz területet!',
                      style: TextStyle(fontSize: 24),
                    ),
                    const SizedBox(height: 32),
                    Expanded(
                      child: MenuList(
                        items: items,
                        selectedIndex: selected,
                        onActivate: _activate,
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      '↑ ↓: választás   Enter / →: megnyitás\nF1: ismétlés   Ctrl+W / F4: kilépés',
                    ),
                  ],
                ),
              ),
            ),
          ),
  );
}
