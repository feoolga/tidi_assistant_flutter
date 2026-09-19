// lib/core/network/sse_parser.dart

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../logger/app_logger.dart';

/// Парсер Server-Sent Events (SSE) потока.
///
/// **Ответственность:** превратить сырой [http.StreamedResponse]
/// в поток JSON-объектов.
///
/// **Что НЕ делает:**
/// - не проверяет статус — это делает [AppHttpClient.postStream]
///   (до возврата `StreamedResponse`), потому что только клиент может
///   прочитать тело ошибки (это JSON, а не SSE-поток);
/// - не интерпретирует события (`response.completed`, `event: error`) —
///   это задача use-case, у которого есть доменный контекст;
/// - не логирует ошибки транспорта — только пропускает невалидные строки.
///
/// **Формат SSE:**
/// ```
/// event: response.output_text.delta
/// data: {"type":"response.output_text.delta","delta":"В"}
///
/// event: response.completed
/// data: {"type":"response.completed","response":{...}}
/// ```
///
/// **Как читаем:**
/// - пустая строка — конец события: склеиваем накопленные `data:`-строки
///   и эмитим как JSON;
/// - `event: X` — тип события (нужен для контекста, кладём в `_event_type`);
/// - `data: Y` — данные (может быть несколько строк — склеиваем через `\n`);
/// - всё остальное (комментарии `: ...`, неизвестные поля) — игнорируем.
class SseParser {
  /// Приватный конструктор — класс используется только статически.
  const SseParser._();

  /// Парсит SSE-поток.
  ///
  /// Возвращает [Stream] JSON-объектов. Каждый объект — одно SSE-событие,
  /// плюс поле `_event_type` с типом события (`event: X`), если был.
  ///
  /// **Невалидные JSON-строки** (например, сервисные сообщения) **пропускаются** с предупреждением в лог —
  /// парсер не падает из-за служебных событий.
  ///
  /// **Важно:** вызывающий код **должен** гарантировать, что
  /// `response.statusCode == 200`. Если передать `StreamedResponse` с `404`
  /// или `500`, парсер попытается прочитать тело как SSE — что даст мусор.
  /// Это ответственность [AppHttpClient.postStream].
  static Stream<Map<String, dynamic>> parse(http.StreamedResponse response) {
    // 1. Преобразуем поток байтов в поток строк.
    final stream = response.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter());

    // 2. Контроллер — выдаёт события наружу.
    final controller = StreamController<Map<String, dynamic>>();

    // 3. Буфер одного события (живёт между строками).
    String? currentEventType;
    final List<String> currentDataLines = [];

    // 4. Подписка на поток строк.
    final subscription = stream.listen(
      (line) {
        // --- Пустая строка = конец события ---
        if (line.isEmpty) {
          _flushEvent(
            controller: controller,
            eventType: currentEventType,
            dataLines: currentDataLines,
          );
          // Сбрасываем буфер.
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

        // --- Остальные строки (комментарии `: ...`, поля `id:`, `retry:`)
        //     игнорируем. SSE-спек допускает их, но нам они не нужны. ---
      },
      onError: (Object error, StackTrace stackTrace) {
        AppLogger.error('Ошибка в SSE-потоке', error, stackTrace);
        controller.addError(error, stackTrace);
        controller.close();
      },
      onDone: () {
        controller.close();
      },
    );

    // 5. Если клиент отписался — отписываемся от источника.
    //    Без этого source продолжит присылать данные в никуда (утечка).
    controller.onCancel = () {
      subscription.cancel();
    };

    return controller.stream;
  }

  // ============================================================
  // ВСПОМОГАТЕЛЬНЫЕ МЕТОДЫ
  // ============================================================

  /// Собирает накопленные `data:`-строки в JSON и эмитит событие.
  ///
  /// **Что делаем:**
  /// - если данных нет — ничего не эмитим;
  /// - если данные не парсятся как JSON-объект — **пропускаем**
  ///   (с предупреждением в лог), не падаем.
  ///
  // SSE-протокол допускает служебные события, которые могут быть
  // не JSON (например, собственные события бэкенда в будущем).
  // Парсер не должен рушить весь стрим из-за одного неизвестного события.
  static void _flushEvent({
    required StreamController<Map<String, dynamic>> controller,
    required String? eventType,
    required List<String> dataLines,
  }) {
    if (dataLines.isEmpty) return;

    final dataString = dataLines.join('\n');

    try {
      final decoded = jsonDecode(dataString);

      if (decoded is! Map<String, dynamic>) {
        AppLogger.warning(
          'SSE: пропущено событие, не JSON-объект '
          '(type=${decoded.runtimeType}): '
          '${_preview(dataString)}',
        );
        return;
      }

      // Добавляем тип события в данные — удобно для use-case.
      // Префикс `_` — соглашение, что это служебное поле, не из JSON.
      if (eventType != null) {
        decoded['_event_type'] = eventType;
      }

      controller.add(decoded);
    } catch (e) {
      // Не JSON — пропускаем с предупреждением.
      AppLogger.warning(
        'SSE: пропущено событие, невалидный JSON: '
        '${_preview(dataString)} ($e)',
      );
    }
  }

  /// Обрезает строку для лога — чтобы не залить логи гигантскими телами.
  static String _preview(String s, {int maxLength = 100}) {
    if (s.length <= maxLength) return s;
    return '${s.substring(0, maxLength)}...';
  }
}
