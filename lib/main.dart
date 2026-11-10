import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app.dart';
import 'controllers/app_controller.dart';
import 'services/content_repository.dart';
import 'services/soloud_audio_service.dart';
import 'services/speech_coordinator.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    TypingApp(
      controller: AppController(
        content: AssetContentRepository(),
        speech: SpeechCoordinator(SoloudAudioService()),
      ),
      onClose: () => SystemNavigator.pop(),
    ),
  );
}
