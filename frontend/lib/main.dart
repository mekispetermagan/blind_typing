import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'controllers/app_controller.dart';
import 'api/http_content_repository.dart';
import 'api/audio_cache.dart';
import 'api/attempt_sync.dart';
import 'services/practice_records.dart';
import 'services/soloud_audio_service.dart';
import 'services/speech_coordinator.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final preferences = SharedPreferencesAsync();
  final attemptSync = AttemptSync(preferences);
  await attemptSync.initialize();
  const recordsKey = 'practice_records';
  runApp(
    TypingApp(
      controller: AppController(
        content: HttpContentRepository(),
        onAttempt: attemptSync.save,
        speech: SpeechCoordinator(SoloudAudioService(cache: AudioCache())),
        records: PracticeRecords(
          read: () => preferences.getString(recordsKey),
          write: (value) => preferences.setString(recordsKey, value),
        ),
      ),
      onClose: () => SystemNavigator.pop(),
    ),
  );
}
