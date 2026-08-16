// lib/theme/app_theme.dart
import 'package:flutter/material.dart';

class AppTheme {
  // Цвета из CSS
  static const Color primary = Color(0xFF0ABAB5);      // Тиффани
  static const Color primaryDark = Color(0xFF158683);   // Темный тиффани
  static const Color primaryLight = Color(0xFFF2FBFA);  // Светлый фон
  static const Color surface = Color(0xFFFFFFFF);       // Белый
  static const Color textPrimary = Color(0xFF1A1A1A);   // Почти черный
  static const Color textSecondary = Color(0xFF6B6B6B); // Серый
  
  // Светлая тема
  static ThemeData lightTheme = ThemeData(
    // Базовые цвета
    brightness: Brightness.light,
    primaryColor: primary,
    colorScheme: const ColorScheme.light(
      primary: primary,
      secondary: primaryDark,
      surface: surface,
      onPrimary: Colors.white,
      onSecondary: Colors.white,
      onSurface: textPrimary,
    ),
    
    // Стиль AppBar
    appBarTheme: const AppBarTheme(
      backgroundColor: surface,
      foregroundColor: textPrimary,
      elevation: 0, // убираем тень
      centerTitle: false,
    ),
    
    // Стиль текста
    textTheme: const TextTheme(
      bodyLarge: TextStyle(
        fontSize: 16,
        color: textPrimary,
      ),
      bodyMedium: TextStyle(
        fontSize: 14,
        color: textPrimary,
      ),
      titleLarge: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.bold,
        color: textPrimary,
      ),
    ),
    
    // Общие настройки
    scaffoldBackgroundColor: surface,
    useMaterial3: true,
    visualDensity: VisualDensity.adaptivePlatformDensity,
      // Это адаптирует плотность под платформу
  );
}