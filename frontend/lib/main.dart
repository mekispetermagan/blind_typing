import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'controllers/app_controller.dart';
import 'models/area.dart';
import 'screens/area_selection_screen.dart';
import 'screens/pin_change_screen.dart';
import 'api/auth_session.dart';
import 'api/http_content_repository.dart';
import 'api/audio_cache.dart';
import 'api/attempt_sync.dart';
import 'services/audio_service.dart';
import 'services/practice_records.dart';
import 'services/soloud_audio_service.dart';
import 'services/speech_coordinator.dart';
import 'widgets/pin_field.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const DemoApp());
}

ThemeData _authTheme() => ThemeData(
  colorScheme: ColorScheme.fromSeed(
    seedColor: Colors.teal,
    brightness: Brightness.dark,
  ),
  fontFamily: 'DejaVuSansMono',
);

class DemoApp extends StatefulWidget {
  const DemoApp({super.key});
  @override
  State<DemoApp> createState() => _DemoAppState();
}

class _DemoAppState extends State<DemoApp> {
  final auth = AuthSession();
  final audio = SoloudAudioService(cache: AudioCache());

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  bool _onKey(KeyEvent event) {
    if (event is KeyDownEvent || event is KeyRepeatEvent) auth.interaction();
    return false;
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    auth.dispose();
    unawaited(audio.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: (_) => auth.interaction(),
    onPointerSignal: (_) => auth.interaction(),
    child: ListenableBuilder(
      listenable: auth,
      builder: (context, _) {
        if (auth.token == null) return _LoginScreen(auth: auth, audio: audio);
        if (auth.pinTemporary) {
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: _authTheme(),
            home: PinChangeScreen(
              pinLength: auth.pinLength,
              setupRequired: true,
              audio: audio,
              onSave: auth.savePin,
              onCancel: () => unawaited(auth.logout()),
            ),
          );
        }
        return _AuthenticatedView(
          key: ValueKey(auth.userId),
          auth: auth,
          audio: audio,
        );
      },
    ),
  );
}

class _LoginScreen extends StatefulWidget {
  const _LoginScreen({required this.auth, required this.audio});
  final AuthSession auth;
  final SoloudAudioService audio;
  @override
  State<_LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<_LoginScreen> {
  final identifier = TextEditingController();
  final pin = TextEditingController();
  final identifierFocus = FocusNode();
  final pinFocus = FocusNode();
  final submitFocus = FocusNode();
  bool ready = false;
  bool loading = false;
  bool failed = false;

  @override
  void initState() {
    super.initState();
    identifierFocus.addListener(_focusChanged);
    pinFocus.addListener(_focusChanged);
    submitFocus.addListener(_focusChanged);
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    try {
      await widget.audio.initializeLogin();
      if (!mounted) return;
      ready = true;
      await widget.audio.speak(
        widget.auth.expired
            ? 'assets/audio/login_expired.wav'
            : 'assets/audio/login_welcome.wav',
      );
    } catch (_) {
      // The text fields remain usable if audio hardware is unavailable.
    }
  }

  void _focusChanged() {
    if (!ready) return;
    if (identifierFocus.hasFocus) {
      unawaited(widget.audio.speak('assets/audio/login_identifier.wav'));
    } else if (pinFocus.hasFocus) {
      unawaited(widget.audio.speak('assets/audio/login_pin.wav'));
    } else if (submitFocus.hasFocus) {
      unawaited(widget.audio.speak('assets/audio/login_submit.wav'));
    }
  }

  Future<void> _submit() async {
    if (loading) return;
    if (identifier.text.trim().isEmpty ||
        !RegExp(r'^(?:[0-9]{4}|[0-9]{6})$').hasMatch(pin.text)) {
      setState(() => failed = true);
      if (ready)
        unawaited(widget.audio.speak('assets/audio/login_failure.wav'));
      return;
    }
    setState(() {
      loading = true;
      failed = false;
    });
    final submittedPin = pin.text;
    pin.clear();
    final success = await widget.auth.login(
      identifier.text.trim(),
      submittedPin,
    );
    if (!mounted) return;
    setState(() {
      loading = false;
      failed = !success;
    });
    if (!success && ready)
      unawaited(widget.audio.speak('assets/audio/login_failure.wav'));
  }

  @override
  void dispose() {
    identifierFocus.removeListener(_focusChanged);
    pinFocus.removeListener(_focusChanged);
    submitFocus.removeListener(_focusChanged);
    identifierFocus.dispose();
    pinFocus.dispose();
    submitFocus.dispose();
    identifier.dispose();
    pin.dispose();
    widget.audio.stopSpeech();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: _authTheme(),
    home: Scaffold(
      body: Center(
        child: SingleChildScrollView(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: PinField.formMaxWidth),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Bejelentkezés',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 24),
                  TextField(
                    controller: identifier,
                    focusNode: identifierFocus,
                    autofocus: true,
                    autofillHints: const [AutofillHints.username],
                    style: const TextStyle(fontSize: 32),
                    decoration: const InputDecoration(
                      label: Text('E-mail cím vagy telefonszám'),
                      labelStyle: TextStyle(fontSize: 32),
                      floatingLabelStyle: TextStyle(fontSize: 32),
                    ),
                    textInputAction: TextInputAction.next,
                    onSubmitted: (_) => pinFocus.requestFocus(),
                  ),
                  const SizedBox(height: 16),
                  PinField(
                    controller: pin,
                    focusNode: pinFocus,
                    label: 'PIN-kód',
                    hint: '4 vagy 6 számjegy',
                    length: 6,
                    readOnly: loading,
                    onSubmit: _submit,
                  ),
                  if (failed)
                    const Padding(
                      padding: EdgeInsets.only(top: 16),
                      child: Text(
                        'A bejelentkezés nem sikerült. Ellenőrizd az adataidat és a kapcsolatot.',
                        style: TextStyle(fontSize: 28),
                      ),
                    ),
                  const SizedBox(height: 24),
                  FilledButton(
                    focusNode: submitFocus,
                    onPressed: loading ? null : _submit,
                    child: const Text('Bejelentkezés'),
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

class _AuthenticatedView extends StatefulWidget {
  const _AuthenticatedView({
    super.key,
    required this.auth,
    required this.audio,
  });
  final AuthSession auth;
  final SoloudAudioService audio;
  @override
  State<_AuthenticatedView> createState() => _AuthenticatedViewState();
}

class _AuthenticatedViewState extends State<_AuthenticatedView> {
  late AppArea? selectedArea;

  @override
  void initState() {
    super.initState();
    selectedArea = initialAreaForRole(widget.auth.role!);
  }

  late final SharedPreferencesAsync preferences = SharedPreferencesAsync();
  late final AttemptSync sync = AttemptSync(
    preferences,
    storageKey: 'pending_attempt_snapshots_${widget.auth.userId}',
    sessionToken: widget.auth.token,
  );
  late final Future<void> initialized = _initialize();

  Future<void> _initialize() async {
    if (widget.auth.identifier == 'mekis.peter@gmail.com') {
      for (final key in ['practice_records', 'pending_attempt_snapshots']) {
        final scoped = '${key}_${widget.auth.userId}';
        final legacy = await preferences.getString(key);
        if (legacy != null && await preferences.getString(scoped) == null) {
          await preferences.setString(scoped, legacy);
          await preferences.remove(key);
        }
      }
    }
    await sync.initialize();
  }

  @override
  void dispose() {
    sync.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<void>(
    future: initialized,
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) {
        return const MaterialApp(
          home: Scaffold(body: Center(child: CircularProgressIndicator())),
        );
      }
      if (snapshot.hasError) {
        return const MaterialApp(
          home: Scaffold(
            body: Center(child: Text('A helyi adatok nem tölthetők be.')),
          ),
        );
      }
      if (selectedArea == null) {
        return AreaSelectionScreen(
          role: widget.auth.role!,
          audio: widget.audio,
          onSelect: (area) => setState(() => selectedArea = area),
          onClose: () => SystemNavigator.pop(),
        );
      }
      final recordsKey = 'practice_records_${widget.auth.userId}';
      return _TypingSession(
        key: ValueKey(selectedArea),
        area: selectedArea!,
        onAreaSelector: () => setState(() => selectedArea = null),
        audio: widget.audio,
        sync: sync,
        preferences: preferences,
        recordsKey: recordsKey,
        onLogout: () => unawaited(widget.auth.logout()),
        pinScreen: (onBack) => PinChangeScreen(
          pinLength: widget.auth.pinLength,
          setupRequired: false,
          audio: widget.audio,
          onSave: widget.auth.savePin,
          onCancel: onBack,
          onSaved: onBack,
        ),
      );
    },
  );
}

class _TypingSession extends StatefulWidget {
  const _TypingSession({
    super.key,
    required this.area,
    required this.onAreaSelector,
    required this.audio,
    required this.sync,
    required this.preferences,
    required this.recordsKey,
    required this.onLogout,
    required this.pinScreen,
  });
  final AppArea area;
  final VoidCallback onAreaSelector;
  final SoloudAudioService audio;
  final AttemptSync sync;
  final SharedPreferencesAsync preferences;
  final String recordsKey;
  final VoidCallback onLogout;
  final Widget Function(VoidCallback onBack) pinScreen;
  @override
  State<_TypingSession> createState() => _TypingSessionState();
}

class _TypingSessionState extends State<_TypingSession> {
  late final controller = AppController(
    content: HttpContentRepository(
      area: widget.area.name,
      includePinChange: true,
    ),
    menuWelcome: widget.area == AppArea.student
        ? AudioCues.menuWelcome
        : 'assets/audio/menu_area_welcome.wav',
    onAttempt: widget.sync.save,
    homeworkEvents: widget.sync.homeworkEvents,
    onLogout: widget.onLogout,
    onAreaSelector: widget.onAreaSelector,
    speech: SpeechCoordinator(_BorrowedAudio(widget.audio)),
    records: PracticeRecords(
      read: () => widget.preferences.getString(widget.recordsKey),
      write: (value) => widget.preferences.setString(widget.recordsKey, value),
    ),
  );
  @override
  Widget build(BuildContext context) => TypingApp(
    controller: controller,
    onClose: () => SystemNavigator.pop(),
    pinScreen: widget.pinScreen,
    showMode: widget.area == AppArea.student,
  );
}

class _BorrowedAudio implements AudioService {
  _BorrowedAudio(this.audio);
  final SoloudAudioService audio;
  @override
  Future<void> initialize(Iterable<String> assets) => audio.initialize(assets);
  @override
  Future<void> setActivityAssets(Iterable<String> assets) =>
      audio.setActivityAssets(assets);
  @override
  Future<void> speak(String asset) => audio.speak(asset);
  @override
  void stopSpeech() => audio.stopSpeech();
  @override
  Future<void> celebrate({required bool sentence}) =>
      audio.celebrate(sentence: sentence);
  @override
  void feedback({required bool correct}) => audio.feedback(correct: correct);
  @override
  Future<void> dispose() async {
    audio.stopSpeech();
  }
}
