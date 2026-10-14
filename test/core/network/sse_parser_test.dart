// test/core/network/sse_parser_test.dart

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:tidi_assistant_flutter/core/network/sse_parser.dart';

/// Тесты для [SseParser].
///
/// **Что проверяем.** Парсер превращает **сырой SSE-поток** в **поток
/// JSON-объектов**. Тесты покрывают:
/// - базовые сценарии (одно событие, несколько событий, multi-line data);
/// - heartbeat (`: ping` → `{'_event_type': '_heartbeat'}`);
/// - игнорирование служебных полей (`id:`, `retry:`);
/// - устойчивость к **невалидному JSON** (пропускаем, не падаем);
/// - корректное завершение **пустого** стрима.
///
/// **Что НЕ проверяем.** Сетевые ошибки, статус-коды, доменные события
/// (`response.completed`) — это **не** ответственность парсера.
///
/// **Про строки в SSE.** `LineSplitter` в парсере срезает `\n` **и** `\r\n`,
/// так что тесты с `\n` эквивалентны реальному трафику.
void main() {
  // ============================================================
  // ХЕЛПЕРЫ
  // ============================================================

  /// Создаёт `StreamedResponse` с телом из **строки**.
  ///
  /// `utf8.encode` превращает строку в байты (SSE — это **байты**
  /// на уровне сети). `Stream.value` эмитит **все** байты **сразу**,
  /// потом закрывается — то же самое, что видит клиент от сервера,
  /// когда ответ приходит **одним** TCP-пакетом.
  http.StreamedResponse makeSseResponse(String body) {
    return http.StreamedResponse(Stream.value(utf8.encode(body)), 200);
  }

  // ============================================================
  // 1. БАЗОВЫЕ СЦЕНАРИИ
  // ============================================================

  group('базовые сценарии', () {
    test('одно событие — один JSON-объект с _event_type', () async {
      const sse = '''
event: response.output_text.delta
data: {"delta":"Привет"}

''';

      final events = await SseParser.parse(makeSseResponse(sse)).toList();

      expect(events.length, 1);
      expect(events[0]['_event_type'], 'response.output_text.delta');
      expect(events[0]['delta'], 'Привет');
    });

    test('несколько событий — в правильном порядке', () async {
      const sse = '''
event: response.created
data: {"id":"resp_1"}

event: response.output_text.delta
data: {"delta":"А"}

event: response.output_text.delta
data: {"delta":"Б"}

''';

      final events = await SseParser.parse(makeSseResponse(sse)).toList();

      expect(events.length, 3);
      expect(events[0]['_event_type'], 'response.created');
      expect(events[1]['_event_type'], 'response.output_text.delta');
      expect(events[2]['_event_type'], 'response.output_text.delta');
      expect(events[1]['delta'], 'А');
      expect(events[2]['delta'], 'Б');
    });

    test('пустой стрим — пустой список событий', () async {
      final events = await SseParser.parse(makeSseResponse('')).toList();

      expect(events, isEmpty);
    });

    test('событие без event: — эмитится без _event_type', () async {
      const sse = '''
data: {"hello":"world"}

''';

      final events = await SseParser.parse(makeSseResponse(sse)).toList();

      expect(events.length, 1);
      expect(events[0]['_event_type'], isNull);
      expect(events[0]['hello'], 'world');
    });
  });

  // ============================================================
  // 2. HEARTBEAT
  // ============================================================

  group('heartbeat', () {
    test(': ping эмитит _heartbeat-маркер', () async {
      const sse = ''': ping

''';

      final events = await SseParser.parse(makeSseResponse(sse)).toList();

      expect(events.length, 1);
      expect(events[0]['_event_type'], '_heartbeat');
    });

    test('пустой комментарий `: ` тоже эмитит _heartbeat', () async {
      const sse = ''': 

''';

      final events = await SseParser.parse(makeSseResponse(sse)).toList();

      expect(events.length, 1);
      expect(events[0]['_event_type'], '_heartbeat');
    });

    test('комментарий с текстом эмитит _heartbeat', () async {
      // В SSE любая строка, начинающаяся с `:`, — комментарий,
      // независимо от содержимого после двоеточия.
      const sse = ''': server alive at 10:15

''';

      final events = await SseParser.parse(makeSseResponse(sse)).toList();

      expect(events.length, 1);
      expect(events[0]['_event_type'], '_heartbeat');
    });

    test('несколько : ping подряд — несколько _heartbeat', () async {
      const sse = '''
: ping

: ping

: ping

''';

      final events = await SseParser.parse(makeSseResponse(sse)).toList();

      expect(events.length, 3);
      expect(events.every((e) => e['_event_type'] == '_heartbeat'), isTrue);
    });

    test('heartbeat между содержательными событиями', () async {
      // Сценарий `agentic_rag`: сервер думает, шлёт heartbeat,
      // потом отвечает дельтой.
      const sse = '''
event: response.created
data: {"id":"resp_1"}

: ping

: ping

event: response.output_text.delta
data: {"delta":"Ответ"}

''';

      final events = await SseParser.parse(makeSseResponse(sse)).toList();

      expect(events.length, 4);
      expect(events[0]['_event_type'], 'response.created');
      expect(events[1]['_event_type'], '_heartbeat');
      expect(events[2]['_event_type'], '_heartbeat');
      expect(events[3]['_event_type'], 'response.output_text.delta');
    });
  });

  // ============================================================
  // 3. СЛУЖЕБНЫЕ ПОЛЯ (id:, retry:)
  // ============================================================

  group('служебные поля', () {
    test('id: не эмитит события', () async {
      // `id:` — служебное поле SSE, но НЕ комментарий (не начинается с `:`).
      // Парсер должен его игнорировать, а не путать с heartbeat.
      const sse = '''
id: 42

''';

      final events = await SseParser.parse(makeSseResponse(sse)).toList();

      expect(events, isEmpty);
    });

    test('retry: не эмитит события', () async {
      const sse = '''
retry: 3000

''';

      final events = await SseParser.parse(makeSseResponse(sse)).toList();

      expect(events, isEmpty);
    });

    test('id: вместе с event: и data: — id игнорируется', () async {
      const sse = '''
id: 42
event: response.output_text.delta
data: {"delta":"X"}

''';

      final events = await SseParser.parse(makeSseResponse(sse)).toList();

      expect(events.length, 1);
      expect(events[0]['_event_type'], 'response.output_text.delta');
      expect(events[0]['delta'], 'X');
      // Поля `id` в событии нет.
      expect(events[0].containsKey('id'), isFalse);
    });
  });

  // ============================================================
  // 4. MULTI-LINE data:
  // ============================================================

  group('multi-line data', () {
    test('несколько data: подряд склеиваются через \\n', () async {
      // По SSE-спеке несколько строк `data:` внутри одного события
      // склеиваются через `\n`.
      const sse = '''
event: multi
data: {"a":
data: 1}

''';

      final events = await SseParser.parse(makeSseResponse(sse)).toList();

      expect(events.length, 1);
      expect(events[0]['_event_type'], 'multi');
      // Склеили: `{"a":\n1}` → jsonDecode → {"a": 1}
      expect(events[0]['a'], 1);
    });
  });

  // ============================================================
  // 5. НЕВАЛИДНЫЙ JSON
  // ============================================================

  group('невалидный JSON', () {
    test('битый JSON в data: — событие пропускается, стрим жив', () async {
      const sse = '''
event: broken
data: это не JSON

event: good
data: {"ok":true}

''';

      final events = await SseParser.parse(makeSseResponse(sse)).toList();

      // Первое событие пропущено (невалидный JSON), второе — прошло.
      expect(events.length, 1);
      expect(events[0]['_event_type'], 'good');
      expect(events[0]['ok'], true);
    });

    test('JSON-массив в data: — пропускается (не объект)', () async {
      const sse = '''
event: array
data: [1,2,3]

event: object
data: {"x":1}

''';

      final events = await SseParser.parse(makeSseResponse(sse)).toList();

      // Массив — не JSON-объект, парсер его не пропускает.
      expect(events.length, 1);
      expect(events[0]['_event_type'], 'object');
    });

    test('data: без значения — не эмитит событие', () async {
      // `data:` с пустым содержимым — по SSE-спеке **не** считается
      // данными, событие не набирается.
      const sse = '''
event: empty
data:

''';

      final events = await SseParser.parse(makeSseResponse(sse)).toList();

      expect(events, isEmpty);
    });
  });

  // ============================================================
  // 6. КОМБИНИРОВАННЫЙ РЕАЛЬНЫЙ СЦЕНАРИЙ
  // ============================================================

  group('комбинированный сценарий', () {
    test('полная последовательность от agentic_rag', () async {
      // Реальная последовательность от `agentic_rag`:
      // created → in_progress → heartbeat × N → delta → completed.
      const sse = '''
event: response.created
data: {"id":"resp_1","status":"in_progress","model":"rag/abc"}

event: response.in_progress
data: {"id":"resp_1","status":"in_progress"}

: ping

: ping

event: response.output_text.delta
data: {"id":"resp_1","delta":"Объяснимый"}

event: response.output_text.delta
data: {"id":"resp_1","delta":" ИИ"}

event: response.completed
data: {"id":"resp_1","status":"completed","usage":{"total_tokens":100}}

''';

      final events = await SseParser.parse(makeSseResponse(sse)).toList();

      // Итого 7 событий:
      //   1. response.created
      //   2. response.in_progress
      //   3. _heartbeat (первый : ping)
      //   4. _heartbeat (второй : ping)
      //   5. response.output_text.delta
      //   6. response.output_text.delta
      //   7. response.completed
      //
      // Пустые строки **после** `: ping` не эмитят ничего — буфер
      // пуст, `_flushEvent` делает `return` при `dataLines.isEmpty`.
      expect(events.length, 7);
      expect(events[0]['_event_type'], 'response.created');
      expect(events[1]['_event_type'], 'response.in_progress');
      expect(events[2]['_event_type'], '_heartbeat');
      expect(events[3]['_event_type'], '_heartbeat');
      expect(events[4]['_event_type'], 'response.output_text.delta');
      expect(events[5]['_event_type'], 'response.output_text.delta');
      expect(events[6]['_event_type'], 'response.completed');
      // Проверим содержимое последнего.
      expect(events[6]['status'], 'completed');
      expect(events[6]['usage']['total_tokens'], 100);
      // И проверим, что дельты склеились бы в "Объяснимый ИИ",
      // если бы их обрабатывали последовательно (это уже работа
      // use-case, но полезно увидеть контракт).
      final deltas = events
          .where((e) => e['_event_type'] == 'response.output_text.delta')
          .map((e) => e['delta'] as String)
          .join();
      expect(deltas, 'Объяснимый ИИ');
    });
  });
}
