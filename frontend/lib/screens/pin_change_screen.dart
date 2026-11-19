import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/pin_update_result.dart';
import '../services/soloud_audio_service.dart';
import '../widgets/pin_field.dart';

class PinChangeScreen extends StatefulWidget {
  const PinChangeScreen({
    required this.pinLength,
    required this.setupRequired,
    required this.audio,
    required this.onSave,
    required this.onCancel,
    this.onSaved,
    super.key,
  });

  final int pinLength;
  final bool setupRequired;
  final SoloudAudioService audio;
  final Future<PinUpdateResult> Function(String?, String, String) onSave;
  final VoidCallback onCancel;
  final VoidCallback? onSaved;

  @override
  State<PinChangeScreen> createState() => _PinChangeScreenState();
}

class _PinChangeScreenState extends State<PinChangeScreen> {
  final _current = TextEditingController();
  final _newPin = TextEditingController();
  final _confirmation = TextEditingController();
  final _newFocus = FocusNode();
  final _confirmationFocus = FocusNode();
  bool _audioReady = false;
  bool _saving = false;
  String? _error;

  String get _introduction => widget.setupRequired ? 'setup' : 'change';
  String get _cancelCue => widget.setupRequired ? 'logout' : 'cancel';

  @override
  void initState() {
    super.initState();
    unawaited(_initializeSpeech());
  }

  Future<void> _initializeSpeech() async {
    try {
      await widget.audio.initializePinForm();
      if (!mounted) return;
      _audioReady = true;
      await _speak(_introduction);
    } catch (_) {
      // The labeled fields remain usable with a screen reader.
    }
  }

  Future<void> _speak(String cue) async {
    if (!_audioReady) return;
    try {
      await widget.audio.speak('assets/audio/login_pin_$cue.wav');
    } catch (_) {
      // Audio failure should not prevent a PIN change.
    }
  }

  Future<void> _submit() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final result = await widget.onSave(
      widget.setupRequired ? null : _current.text,
      _newPin.text,
      _confirmation.text,
    );
    if (!mounted) return;
    if (result == PinUpdateResult.saved) {
      widget.onSaved?.call();
      return;
    }
    setState(() {
      _saving = false;
      _error = switch (result) {
        PinUpdateResult.invalidNewPin =>
          'A PIN-kód pontosan ${widget.pinLength} számjegyből álljon.',
        PinUpdateResult.mismatch => 'A két új PIN-kód nem egyezik.',
        PinUpdateResult.incorrectCurrentPin => 'A jelenlegi PIN-kód hibás.',
        _ => 'A PIN-kód mentése nem sikerült. Próbáld újra.',
      };
    });
    unawaited(_speak('error'));
  }

  Widget _withCue(String cue, Widget child) => Focus(
    canRequestFocus: false,
    onFocusChange: (focused) {
      if (focused) unawaited(_speak(cue));
    },
    child: child,
  );

  Widget _field(
    String label,
    String cue,
    TextEditingController controller, {
    FocusNode? focus,
    FocusNode? next,
    bool autofocus = false,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: _withCue(
      cue,
      PinField(
        label: label,
        length: widget.pinLength,
        controller: controller,
        focusNode: focus,
        autofocus: autofocus,
        readOnly: _saving,
        textInputAction: next == null
            ? TextInputAction.done
            : TextInputAction.next,
        onSubmit: next == null ? _submit : next.requestFocus,
      ),
    ),
  );

  @override
  void dispose() {
    _current.dispose();
    _newPin.dispose();
    _confirmation.dispose();
    _newFocus.dispose();
    _confirmationFocus.dispose();
    if (widget.setupRequired) widget.audio.stopSpeech();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => CallbackShortcuts(
    bindings: {
      const SingleActivator(LogicalKeyboardKey.f1): () =>
          unawaited(_speak(_error == null ? _introduction : 'error')),
      if (!_saving)
        const SingleActivator(LogicalKeyboardKey.escape): widget.onCancel,
    },
    child: Scaffold(
      appBar: AppBar(
        title: Text(
          widget.setupRequired ? 'Adj meg új PIN-kódot' : 'PIN-kód módosítása',
        ),
      ),
      body: Center(
        child: SingleChildScrollView(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: PinField.formMaxWidth),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'A PIN-kód ${widget.pinLength} számjegyből áll.',
                    style: const TextStyle(fontSize: 28),
                  ),
                  if (widget.setupRequired)
                    const Text(
                      'A jelenlegi PIN-kódot is megadhatod.',
                      style: TextStyle(fontSize: 28),
                    ),
                  const SizedBox(height: 16),
                  if (!widget.setupRequired)
                    _field(
                      'Jelenlegi PIN-kód',
                      'current',
                      _current,
                      next: _newFocus,
                      autofocus: true,
                    ),
                  _field(
                    'Új PIN-kód',
                    'new',
                    _newPin,
                    focus: _newFocus,
                    next: _confirmationFocus,
                    autofocus: widget.setupRequired,
                  ),
                  _field(
                    'Új PIN-kód megerősítése',
                    'repeat',
                    _confirmation,
                    focus: _confirmationFocus,
                  ),
                  if (_error case final error?)
                    Semantics(
                      liveRegion: true,
                      child: Text(error, style: const TextStyle(fontSize: 28)),
                    ),
                  const SizedBox(height: 16),
                  _withCue(
                    'save',
                    FilledButton(
                      onPressed: _saving ? null : _submit,
                      child: const Text('PIN-kód mentése'),
                    ),
                  ),
                  _withCue(
                    _cancelCue,
                    TextButton(
                      onPressed: _saving ? null : widget.onCancel,
                      child: Text(
                        widget.setupRequired ? 'Kijelentkezés' : 'Mégse',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
