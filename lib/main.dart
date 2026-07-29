import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'screens/splash_screen.dart';
import 'theme/app_theme.dart';
import 'temp/state_test.dart';

void main() async {
  // Загружаем .env файл перед запуском приложения
  await dotenv.load(fileName: ".env");

  runApp(const ProviderScope(child: MyApp()));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AI Assistant',
      theme: AppTheme.lightTheme,
      // theme: ThemeData.dark(),
      home: const TestScreen(),
      // home: const SplashScreen(),
      // home: const ChatScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}
