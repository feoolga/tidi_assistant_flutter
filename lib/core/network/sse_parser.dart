// lib/core/network/sse_parser.dart

import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;

/// Парсер Server-Sent Events (SSE) потока.
class SseParser {
  /// Парсит SSE-поток
  static Stream<Map<String, dynamic>> parse(http.StreamedResponse response) {
    if (response.statusCode != 200) {
      throw Exception('Ошибка сервера: ${response.statusCode}');
    }

    // 1. Преобразуем поток байтов в поток строк
    final stream = response.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter());

    // 2. Создаём контроллер, который будет выдавать события наружу
    final controller = StreamController<Map<String, dynamic>>();

    // 3. Переменные для сборки одного события
    String? currentEventType;
    final List<String> currentDataLines = [];

    // 4. Подписываемся на поток строк
    stream.listen(
      (line) {
        // --- Если строка пустая — значит, событие закончилось ---
        if (line.isEmpty) {
          // Если есть собранные данные — отправляем событие
          if (currentEventType != null && currentDataLines.isNotEmpty) {
            final dataString = currentDataLines.join('\n');
            final jsonData = jsonDecode(dataString) as Map<String, dynamic>;

            // Добавляем тип события в данные (для удобства)
            jsonData['_event_type'] = currentEventType;

            controller.add(jsonData);
          }

          // Сбрасываем буфер
          currentEventType = null;
          currentDataLines.clear();
          return;
        }

        // --- Строка с типом события ---
        if (line.startsWith('event:')) {
          currentEventType = line.substring(6).trim();
          return;
        }

        // --- Строка с данными ---
        if (line.startsWith('data:')) {
          final data = line.substring(5).trim();
          if (data.isNotEmpty) {
            currentDataLines.add(data);
          }
          return;
        }

        // --- Игнорируем другие строки (комментарии, пустые и т.д.) ---
      },
      onError: (error) {
        controller.addError('Ошибка в SSE-потоке: $error');
        controller.close();
      },
      onDone: () {
        // Закрываем контроллер, когда поток завершён
        controller.close();
      },
    );

    // 5. Возвращаем поток событий наружу
    return controller.stream;
  }
}
