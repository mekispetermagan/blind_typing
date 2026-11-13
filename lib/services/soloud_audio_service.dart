import 'dart:async';

import 'package:flutter_soloud/flutter_soloud.dart';

import 'audio_service.dart';

class SoloudAudioService implements AudioService {
  final SoLoud _engine = SoLoud.instance;
  final Map<String, AudioSource> _sources = {};
  final Map<String, StreamSubscription<StreamSoundEvent>> _subscriptions = {};
  final Set<String> _shared = {};
  Set<String> _activity = {};
  Future<void> _pending = Future.value();
  SoundHandle? _speechHandle;
  Completer<void>? _speechFinished;
  int _speechGeneration = 0;
  bool _disposed = false;

  Future<void> _serialize(Future<void> Function() action) {
    final result = _pending.then((_) => action());
    _pending = result.catchError((Object _) {});
    return result;
  }

  @override
  Future<void> initialize(Iterable<String> speechAssets) {
    final assets = {
      ...speechAssets,
      AudioCues.good,
      AudioCues.bad,
      AudioCues.wordComplete,
      AudioCues.sentenceComplete,
    };
    return _serialize(() async {
      if (_disposed) return;
      _shared.addAll(assets);
      await _load(assets);
    });
  }

  @override
  Future<void> setActivityAssets(Iterable<String> speechAssets) {
    final assets = speechAssets.toSet();
    return _serialize(() async {
      if (_disposed) return;
      final removed = _activity.difference(assets).difference(_shared);
      for (final asset in removed) {
        final subscription = _subscriptions.remove(asset);
        await subscription?.cancel();
        final source = _sources.remove(asset);
        if (source != null && _engine.isInitialized) {
          await _engine.disposeSource(source);
        }
      }
      _activity = assets;
      if (assets.isNotEmpty) await _load(assets);
    });
  }

  Future<void> _load(Set<String> assets) async {
    if (_disposed) return;
    if (!_engine.isInitialized) {
      await _engine.init(sampleRate: 48000, bufferSize: 256);
    }
    if (_disposed) return;
    for (final asset in assets) {
      if (_disposed) return;
      if (_sources.containsKey(asset)) continue;
      final source = await _engine.loadAsset(asset, mode: LoadMode.memory);
      // Keep track of a source even if disposal began during the await.
      _sources[asset] = source;
      if (_disposed) return;
      _subscriptions[asset] = source.soundEvents.listen((event) {
        if (event.handle == _speechHandle) _finishSpeech();
      });
    }
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
  Future<void> dispose() {
    _disposed = true;
    stopSpeech();
    return _serialize(() async {
      for (final subscription in _subscriptions.values) {
        await subscription.cancel();
      }
      _subscriptions.clear();
      _sources.clear();
      if (_engine.isInitialized) await _engine.deinitAsync();
    });
  }
}
