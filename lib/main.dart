import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'audio_service.dart';
import 'transcription_service.dart';
import 'home_page.dart';
import 'splash_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  await AudioService().init();
  await TranscriptionService().initModel();
  runApp(const DictaProApp());
}

class DictaProApp extends StatelessWidget {
  const DictaProApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ДиктаПро',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0F0F1E),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF6366F1),
          secondary: Color(0xFF8B5CF6),
          surface: Color(0xFF1E1E2E),
        ),
      ),
      home: const SplashWrapper(),
    );
  }
}

class SplashWrapper extends StatefulWidget {
  const SplashWrapper({super.key});

  @override
  State<SplashWrapper> createState() => _SplashWrapperState();
}

class _SplashWrapperState extends State<SplashWrapper> {
  bool _showSplash = true;

  @override
  Widget build(BuildContext context) {
    if (_showSplash) {
      return SplashScreen(
        onComplete: () {
          setState(() {
            _showSplash = false;
          });
        },
      );
    }
    return const HomePage();
  }
}
