// test/domain/models/rag_config_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:tidi_assistant_flutter/domain/models/rag_config.dart';

void main() {
  group('RagConfig', () {
    // ============================================================
    // КОНСТРУКТОР И ДЕФОЛТЫ
    // ============================================================

    group('конструктор и дефолты', () {
      test('дефолтный конструктор даёт ожидаемые значения', () {
        const config = RagConfig();

        expect(config.prompt, isNull);
        expect(config.temperature, 0.3);
        expect(config.topK, 5);
        expect(config.scoreThreshold, 0.4);
      });

      test('можно переопределить только temperature', () {
        const config = RagConfig(temperature: 0.9);

        expect(config.prompt, isNull);
        expect(config.temperature, 0.9);
        expect(config.topK, 5); // дефолт
        expect(config.scoreThreshold, 0.4); // дефолт
      });

      test('можно переопределить все поля', () {
        const config = RagConfig(
          prompt: 'Отвечай кратко',
          temperature: 0.1,
          topK: 10,
          scoreThreshold: 0.8,
        );

        expect(config.prompt, 'Отвечай кратко');
        expect(config.temperature, 0.1);
        expect(config.topK, 10);
        expect(config.scoreThreshold, 0.8);
      });
    });

    // ============================================================
    // ASSERTS — ГРАНИЦЫ ДИАПАЗОНОВ
    // ============================================================

    group('assert-проверки (в дебаге)', () {
      test('temperature < 0.0 → AssertionError', () {
        expect(
          () => RagConfig(temperature: -0.1),
          throwsA(isA<AssertionError>()),
        );
      });

      test('temperature > 1.0 → AssertionError', () {
        expect(
          () => RagConfig(temperature: 1.1),
          throwsA(isA<AssertionError>()),
        );
      });

      test('temperature на границе 0.0 → ок', () {
        expect(() => RagConfig(temperature: 0.0), returnsNormally);
      });

      test('temperature на границе 1.0 → ок', () {
        expect(() => RagConfig(temperature: 1.0), returnsNormally);
      });

      test('topK < 1 → AssertionError', () {
        expect(() => RagConfig(topK: 0), throwsA(isA<AssertionError>()));
      });

      test('topK > 10 → AssertionError', () {
        expect(() => RagConfig(topK: 11), throwsA(isA<AssertionError>()));
      });

      test('topK на границе 1 → ок', () {
        expect(() => RagConfig(topK: 1), returnsNormally);
      });

      test('topK на границе 10 → ок', () {
        expect(() => RagConfig(topK: 10), returnsNormally);
      });

      test('scoreThreshold < 0.0 → AssertionError', () {
        expect(
          () => RagConfig(scoreThreshold: -0.01),
          throwsA(isA<AssertionError>()),
        );
      });

      test('scoreThreshold > 1.0 → AssertionError', () {
        expect(
          () => RagConfig(scoreThreshold: 1.01),
          throwsA(isA<AssertionError>()),
        );
      });
    });

    // ============================================================
    // copyWith
    // ============================================================

    group('copyWith', () {
      test('без параметров возвращает эквивалент', () {
        const original = RagConfig(
          prompt: 'Тест',
          temperature: 0.5,
          topK: 7,
          scoreThreshold: 0.6,
        );

        final copy = original.copyWith();

        expect(copy.prompt, original.prompt);
        expect(copy.temperature, original.temperature);
        expect(copy.topK, original.topK);
        expect(copy.scoreThreshold, original.scoreThreshold);
      });

      test('меняет только temperature', () {
        const original = RagConfig(prompt: 'A', temperature: 0.3, topK: 5);

        final copy = original.copyWith(temperature: 0.9);

        expect(copy.temperature, 0.9);
        expect(copy.prompt, 'A'); // не тронуто
        expect(copy.topK, 5); // не тронуто
      });

      test('меняет только prompt', () {
        const original = RagConfig(prompt: 'A', topK: 5);

        final copy = original.copyWith(prompt: 'B');

        expect(copy.prompt, 'B');
        expect(copy.topK, 5);
      });

      // ---- Ключевой кейс: маркер copyWithUnset ----

      test('copyWith(prompt: null) СБРАСЫВАЕТ prompt', () {
        // Вот для этого и нужен маркер.
        // Обычный nullable-параметр не отличил бы
        // "не передали" от "передали null".
        const original = RagConfig(prompt: 'Было значение');

        final copy = original.copyWith(prompt: null);

        expect(copy.prompt, isNull);
      });

      test('copyWith() БЕЗ prompt сохраняет старый prompt', () {
        const original = RagConfig(prompt: 'Было значение');

        final copy = original.copyWith();

        expect(copy.prompt, 'Было значение');
      });

      test('можно установить новый prompt', () {
        const original = RagConfig(prompt: null);

        final copy = original.copyWith(prompt: 'Новое значение');

        expect(copy.prompt, 'Новое значение');
      });
    });
  });
}
