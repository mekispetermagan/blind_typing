import 'dart:async';

import 'package:flutter_soloud/flutter_soloud.dart';

import 'audio_service.dart';

class SoloudAudioService implements AudioService {
  final SoLoud _engine = SoLoud.instance;
  final Map<String, AudioSource> _sources = {};
  final List<StreamSubscription<StreamSoundEvent>> _subscriptions = [];
  SoundHandle? _speechHandle;
  Completer<void>? _speechFinished;
  int _speechGeneration = 0;
  bool _disposed = false;

  @override
  Future<void> initialize(Iterable<String> speechAssets) async {
    if (_disposed) return;
    if (!_engine.isInitialized) {
      // 256 frames at 48 kHz: 5.3 ms mixing quantum, not end-to-end latency.
      await _engine.init(sampleRate: 48000, bufferSize: 256);
    }
    if (_disposed) {
      await _engine.deinitAsync();
      return;
    }
    for (final asset in {
      ...speechAssets,
      AudioCues.good,
      AudioCues.bad,
      AudioCues.wordComplete,
      AudioCues.sentenceComplete,
    }) {
      if (_disposed) return;
      if (_sources.containsKey(asset)) continue;
      final source = await _engine.loadAsset(asset, mode: LoadMode.memory);
      if (_disposed) return;
      _sources[asset] = source;
      _subscriptions.add(
        source.soundEvents.listen((event) {
          if (event.handle == _speechHandle) _finishSpeech();
        }),
      );
    }
    // Keep the device warm even when the learner pauses between keystrokes.
    if (!_disposed) {
      _engine.setAudioDeviceIdleTimeout(null);
      await _engine.startAudioDevice();
    }
  }

  @override
  Future<void> celebrate({required bool sentence}) async {
    final finished = speak(AudioCues.wordComplete);
    final generation = _speechGeneration;
    await finished;
    if (sentence && !_disposed && generation == _speechGeneration) {
      await speak(AudioCues.sentenceComplete);
    }
  }

  @override
  Future<void> speak(String asset) {
    stopSpeech();
    if (_disposed) return Future.value();
    final source = _sources[asset];
    if (source == null) throw StateError('Audio not loaded: $asset');
    final handle = _engine.play(source);
    if (!_engine.getIsValidVoiceHandle(handle)) {
      throw StateError('Unable to play: $asset');
    }
    _speechHandle = handle;
    _speechFinished = Completer<void>();
    return _speechFinished!.future;
  }

  @override
  void stopSpeech() {
    ++_speechGeneration;
    final handle = _speechHandle;
    _finishSpeech();
    if (handle != null && _engine.isInitialized) {
      // Native stop is immediate; the Future waits for cleanup notification.
      unawaited(_engine.stop(handle));
    }
  }

  void _finishSpeech() {
    _speechHandle = null;
    final finished = _speechFinished;
    _speechFinished = null;
    if (finished != null && !finished.isCompleted) finished.complete();
  }

  @override
  void feedback({required bool correct}) {
    if (_disposed) return;
    final source = _sources[correct ? AudioCues.good : AudioCues.bad];
    if (source == null) throw StateError('Feedback audio not loaded');
    _engine.play(source, volume: 0.65);
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    stopSpeech();
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    _subscriptions.clear();
    _sources.clear();
    if (_engine.isInitialized) await _engine.deinitAsync();
  }
}
