// test/core/utils/message_id_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:tidi_assistant_flutter/core/utils/message_id.dart';

void main() {
  // ============================================================
  // КОНСТАНТЫ ДЛЯ ТЕСТОВ
  // ============================================================

  // Один и тот же UUID, чтобы проверять, что префиксы не влияют
  // на идентичность.
  const uuid = '412a99f2-4cdc-445d-a28a-0dfb1faf4135';
  const uuidUpperCase = '412A99F2-4CDC-445D-A28A-0DFB1FAF4135';

  // ============================================================
  // parse — РАСПОЗНАВАНИЕ ПРЕФИКСОВ
  // ============================================================

  group('parse', () {
    test('распознаёт resp_', () {
      final id = MessageId.parse('resp_$uuid');

      expect(id.uuid, uuid);
      expect(id.prefixOrNull, 'resp');
      expect(id.isResponse, isTrue);
      expect(id.isMessage, isFalse);
      expect(id.isBare, isFalse);
    });

    test('распознаёт msg_', () {
      final id = MessageId.parse('msg_$uuid');

      expect(id.uuid, uuid);
      expect(id.prefixOrNull, 'msg');
      expect(id.isMessage, isTrue);
      expect(id.isResponse, isFalse);
    });

    test('распознаёт голый UUID', () {
      final id = MessageId.parse(uuid);

      expect(id.uuid, uuid);
      expect(id.prefixOrNull, isNull);
      expect(id.isBare, isTrue);
    });

    test('нормализует UPPERCASE в lowercase', () {
      final id = MessageId.parse('resp_$uuidUpperCase');

      expect(id.uuid, uuid);
      expect(id.isResponse, isTrue);
    });

    test('нормализует UPPERCASE в голом UUID', () {
      final id = MessageId.parse(uuidUpperCase);

      expect(id.uuid, uuid);
      expect(id.isBare, isTrue);
    });
  });

  // ============================================================
  // ВАЛИДАЦИЯ — ПАДАЕМ НА МУСОРЕ
  // ============================================================

  group('валидация', () {
    test('пустая строка → ArgumentError', () {
      expect(() => MessageId.parse(''), throwsA(isA<ArgumentError>()));
    });

    test('невалидный UUID → ArgumentError', () {
      expect(
        () => MessageId.parse('resp_not-a-uuid'),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('UUID без дефисов → ArgumentError', () {
      expect(
        () => MessageId.parse('resp_412a99f24cdc445da28a0dfb1faf4135'),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('UUID с не-hex символами → ArgumentError', () {
      expect(
        () => MessageId.parse('resp_zzzzzzzz-zzzz-zzzz-zzzz-zzzzzzzzzzzz'),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('UUID не той длины → ArgumentError', () {
      expect(
        () => MessageId.parse('resp_412a99f2-4cdc-445d-a28a'),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('chatcmpl- не поддерживается → UUID невалидный → ArgumentError', () {
      // Мы работаем только с Responses API. Если придёт chatcmpl-,
      // префикс не распознается, и UUID-валидация упадёт.
      expect(
        () => MessageId.parse('chatcmpl-$uuid'),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  // ============================================================
  // ФАБРИКИ — ЯВНОЕ СОЗДАНИЕ
  // ============================================================

  group('fromResponse', () {
    test('создаёт с префиксом resp', () {
      final id = MessageId.fromResponse(uuid);

      expect(id.uuid, uuid);
      expect(id.isResponse, isTrue);
      expect(id.raw, 'resp_$uuid');
    });
  });

  group('fromMessage', () {
    test('создаёт с префиксом msg', () {
      final id = MessageId.fromMessage(uuid);

      expect(id.uuid, uuid);
      expect(id.isMessage, isTrue);
      expect(id.raw, 'msg_$uuid');
    });
  });

  group('fromUuid', () {
    test('создаёт без префикса', () {
      final id = MessageId.fromUuid(uuid);

      expect(id.uuid, uuid);
      expect(id.isBare, isTrue);
      expect(id.raw, uuid);
    });
  });

  // ============================================================
  // РАВЕНСТВО — ПО UUID, НЕ ПО ПРЕФИКСУ
  // ============================================================

  group('равенство', () {
    test('resp_ и msg_ с одним UUID — равны', () {
      final a = MessageId.parse('resp_$uuid');
      final b = MessageId.parse('msg_$uuid');

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('голый UUID и resp_ с тем же UUID — равны', () {
      final a = MessageId.parse(uuid);
      final b = MessageId.parse('resp_$uuid');

      expect(a, equals(b));
    });

    test('разные UUID — не равны', () {
      final a = MessageId.parse('resp_$uuid');
      final b = MessageId.parse('resp_00000000-0000-0000-0000-000000000000');

      expect(a, isNot(equals(b)));
    });

    test('один и тот же объект — равен сам себе', () {
      final a = MessageId.parse('resp_$uuid');

      expect(a, equals(a));
    });

    test('сравнение со строкой → false', () {
      final a = MessageId.parse('resp_$uuid');

      // Явно используем матчер equals — чтобы анализатор
      // не ругался на сравнение несвязанных типов.
      expect(a, isNot(equals('resp_$uuid')));
    });
  });

  // ============================================================
  // ПРЕОБРАЗОВАНИЯ
  // ============================================================

  group('asResponse', () {
    test('msg_ → resp_', () {
      final msgId = MessageId.parse('msg_$uuid');
      final respId = msgId.asResponse();

      expect(respId.uuid, uuid);
      expect(respId.isResponse, isTrue);
      expect(respId.raw, 'resp_$uuid');
      // После преобразования объект равен исходному по UUID.
      expect(respId, equals(msgId));
    });

    test('голый UUID → resp_', () {
      final bare = MessageId.fromUuid(uuid);
      final resp = bare.asResponse();

      expect(resp.isResponse, isTrue);
      expect(resp.raw, 'resp_$uuid');
    });
  });

  group('asMessage', () {
    test('resp_ → msg_', () {
      final resp = MessageId.parse('resp_$uuid');
      final msg = resp.asMessage();

      expect(msg.isMessage, isTrue);
      expect(msg.raw, 'msg_$uuid');
    });
  });

  group('asBare', () {
    test('resp_ → голый UUID', () {
      final resp = MessageId.parse('resp_$uuid');
      final bare = resp.asBare();

      expect(bare.isBare, isTrue);
      expect(bare.raw, uuid);
    });
  });

  // ============================================================
  // toString
  // ============================================================

  group('toString', () {
    test('возвращает raw', () {
      final id = MessageId.parse('resp_$uuid');

      expect(id.toString(), 'resp_$uuid');
    });

    test('для голого UUID возвращает uuid', () {
      final id = MessageId.fromUuid(uuid);

      expect(id.toString(), uuid);
    });
  });
}
