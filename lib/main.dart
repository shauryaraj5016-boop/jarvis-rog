import 'package:flutter/material.dart';
import 'assistant/assistant_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const JarvisRogApp());
}

class JarvisRogApp extends StatelessWidget {
  const JarvisRogApp({super.key});

  static const Color red = Color(0xFFFF3344);

  @override
  Widget build(BuildContext context) {
    const background = Color(0xFF08080B);
    return MaterialApp(
      title: 'JARVIS ROG Edition',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: background,
        colorScheme: const ColorScheme.dark(
          primary: red,
          secondary: Color(0xFFFF5662),
          surface: Color(0xFF111215),
          error: Color(0xFFFF6874),
        ),
        snackBarTheme: const SnackBarThemeData(
          backgroundColor: Color(0xFF1B1C20),
          contentTextStyle: TextStyle(color: Colors.white),
          behavior: SnackBarBehavior.floating,
        ),
        useMaterial3: true,
      ),
      home: const AssistantScreen(),
    );
  }
}
