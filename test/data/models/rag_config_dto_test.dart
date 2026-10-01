// test/data/models/rag_config_dto_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:tidi_assistant_flutter/data/models/rag_config_dto.dart';

void main() {
  group('RagConfigDto.fromJson', () {
    // ============================================================
    // HAPPY PATH
    // ============================================================

    test('парсит полный config', () {
      final json = <String, dynamic>{
        'prompt': 'Отвечай кратко',
        'temperature': 0.5,
        'top_k': 7,
        'score_threshold': 0.6,
      };

      final dto = RagConfigDto.fromJson(json);

      expect(dto.prompt, 'Отвечай кратко');
      expect(dto.temperature, 0.5);
      expect(dto.topK, 7);
      expect(dto.scoreThreshold, 0.6);
    });

    test('парсит config с prompt = null', () {
      final json = <String, dynamic>{
        'prompt': null,
        'temperature': 0.3,
        'top_k': 5,
        'score_threshold': 0.4,
      };

      final dto = RagConfigDto.fromJson(json);

      expect(dto.prompt, isNull);
    });

    // ============================================================
    // ОПЦИОНАЛЬНЫЕ ПОЛЯ
    // ============================================================

    test('пустой config — все null', () {
      final json = <String, dynamic>{};

      final dto = RagConfigDto.fromJson(json);

      expect(dto.prompt, isNull);
      expect(dto.temperature, isNull);
      expect(dto.topK, isNull);
      expect(dto.scoreThreshold, isNull);
    });

    // ============================================================
    // ПАРСИНГ INT → DOUBLE
    // ============================================================

    test('temperature как int → double', () {
      // JSON не различает 1 и 1.0. Dart при парсинге может дать int.
      final json = <String, dynamic>{
        'temperature': 1, // int, не double
      };

      final dto = RagConfigDto.fromJson(json);

      expect(dto.temperature, 1.0);
      expect(dto.temperature, isA<double>());
    });

    test('score_threshold как int → double', () {
      final json = <String, dynamic>{'score_threshold': 0};

      final dto = RagConfigDto.fromJson(json);

      expect(dto.scoreThreshold, 0.0);
      expect(dto.scoreThreshold, isA<double>());
    });

    // ============================================================
    // НЕВАЛИДНЫЕ ЗНАЧЕНИЯ
    // ============================================================

    test('temperature как строка → null (не парсим)', () {
      final json = <String, dynamic>{
        'temperature': '0.5', // строка, не число
      };

      final dto = RagConfigDto.fromJson(json);

      expect(dto.temperature, isNull);
    });

    test('top_k как строка → null (TypeError обёрнут в null?)', () {
      // Хм, тут as int? выбросит TypeError, если пришла строка.
      // Это ОК — контракт нарушен.
      // Но давай проверим, что реально происходит.
      final json = <String, dynamic>{'top_k': 'abc'};

      expect(() => RagConfigDto.fromJson(json), throwsA(isA<TypeError>()));
    });
  });
}
