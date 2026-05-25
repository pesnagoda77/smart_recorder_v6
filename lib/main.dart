import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'audio_service.dart';
import 'transcription_service.dart';
import 'home_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  await AudioService().init();
  await TranscriptionService().initModel();
  runApp(const SmartRecorderApp());
}

class SmartRecorderApp extends StatelessWidget {
  const SmartRecorderApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Smart Recorder',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0F0F1E),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF6366F1),
          secondary: Color(0xFF8B5CF6),
          surface: Color(0xFF1E1E2E),
        ),
      ),
      home: const HomePage(),
    );
  }
}
