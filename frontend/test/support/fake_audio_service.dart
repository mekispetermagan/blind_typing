import 'dart:async';

import 'package:blind_typing/services/audio_service.dart';

class FakeAudioService implements AudioService {
  final List<String> spoken = [];
  final List<bool> feedbackResults = [];
  final List<bool> celebrations = [];
  final List<String> interrupted = [];
  final List<String> loaded = [];
  Set<String> activityAssets = {};
  bool holdSpeech = false;
  bool failSpeech = false;
  bool disposed = false;
  Completer<void>? _pending;

  @override
  Future<void> initialize(Iterable<String> speechAssets) async {
    loaded.addAll(speechAssets);
  }

  @override
  Future<void> setActivityAssets(Iterable<String> assets) async {
    activityAssets = assets.toSet();
    loaded.addAll(assets);
  }

  @override
  Future<void> celebrate({required bool sentence}) {
    stopSpeech();
    celebrations.add(sentence);
    if (!holdSpeech) return Future.value();
    _pending = Completer<void>();
    return _pending!.future;
  }

  @override
  Future<void> speak(String asset) {
    stopSpeech();
    if (failSpeech) throw StateError('Test playback failure');
    spoken.add(asset);
    if (!holdSpeech) return Future.value();
    _pending = Completer<void>();
    return _pending!.future;
  }

  void finishSpeech() {
    _pending?.complete();
    _pending = null;
  }

  @override
  void stopSpeech() {
    if (_pending != null) {
      interrupted.add(spoken.last);
      finishSpeech();
    }
  }

  @override
  void feedback({required bool correct}) => feedbackResults.add(correct);

  @override
  Future<void> dispose() async {
    stopSpeech();
    disposed = true;
  }
}
