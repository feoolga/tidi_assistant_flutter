// lib/core/network/sse_parser.dart

import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;

/// Парсер Server-Sent Events (SSE) потока.
///
/// Превращает сырой HTTP-поток в поток структурированных событий.
class SseParser {
  /// Парсит SSE-поток из [StreamedResponse].
  ///
  /// Возвращает поток, где каждое событие — это Map с полями:
  /// - 'type': тип события (из строки event:)
  /// - 'data': распарсенный JSON из строки data:
  static Stream<Map<String, dynamic>> parse(http.StreamedResponse response) {
    // Проверяем статус ответа
    if (response.statusCode != 200) {
      throw Exception('Ошибка сервера: ${response.statusCode}');
    }

    // Преобразуем поток байтов в поток строк
    final stream = response.stream
        .transform(utf8.decoder) // bytes → String
        .transform(const LineSplitter()); // String → строки по \n

    return Stream.fromIterable([]); // ВРЕМЕННО: пока просто заглушка
  }
}
