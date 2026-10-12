// test/core/utils/stream_with_inactivity_timeout_test.dart

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:tidi_assistant_flutter/core/errors/network_exceptions.dart';
import 'package:tidi_assistant_flutter/core/utils/stream_with_inactivity_timeout.dart';

/// Тесты для [InactivityTimeoutTransformer] / [StreamInactivityTimeoutExtension].
///
/// **Про тайминги.** Трансформер работает с реальными `Timer`'ами, и
/// тесты тоже используют **реальные** `Future.delayed` — но с **очень
/// маленькими** интервалами (десятки миллисекунд). Это даёт:
/// - **точность**: настоящий `Timer` реально срабатывает;
/// - **скорость**: тест занимает доли секунды, а не секунды;
/// - **простоту**: не нужен `fake_async`, который в комбинации с
///   `Stream.listen` работает хрупко.
///
/// **Про `onDone` после `onError`.** В `StreamController` после
/// `addError` идёт микротаска, и `close()` может произойти **не
/// мгновенно**. Поэтому после ожидаемой ошибки делаем небольшую
/// паузу перед проверкой флага `done`.
void main() {
  // ============================================================
  // 1. СОБЫТИЯ ПРОХОДЯТ СКВОЗЬ
  // ============================================================

  group('события проходят сквозь', () {
    test('события передаются без изменений', () async {
      final controller = StreamController<int>();
      final stream = controller.stream.withInactivityTimeout(
        const Duration(milliseconds: 100),
      );

      final events = <int>[];
      Object? caughtError;
      bool done = false;

      stream.listen(
        events.add,
        onError: (Object e) => caughtError = e,
        onDone: () => done = true,
      );

      controller.add(1);
      await Future.delayed(const Duration(milliseconds: 10));
      controller.add(2);
      await Future.delayed(const Duration(milliseconds: 10));
      controller.add(3);

      await controller.close();
      await Future.delayed(const Duration(milliseconds: 20));

      expect(events, [1, 2, 3]);
      expect(caughtError, isNull);
      expect(done, isTrue);
    });

    test('пустой стрим закрывается без ошибки', () async {
      final controller = StreamController<int>();
      final stream = controller.stream.withInactivityTimeout(
        const Duration(milliseconds: 100),
      );

      final events = <int>[];
      Object? caughtError;
      bool done = false;

      stream.listen(
        events.add,
        onError: (Object e) => caughtError = e,
        onDone: () => done = true,
      );

      await controller.close();
      await Future.delayed(const Duration(milliseconds: 20));

      expect(events, isEmpty);
      expect(caughtError, isNull);
      expect(done, isTrue);
    });
  });

  // ============================================================
  // 2. ТАЙМЕР СБРАСЫВАЕТСЯ НА СОБЫТИЯХ
  // ============================================================

  group('таймер сбрасывается на событиях', () {
    test('события с паузами меньше timeout — стрим не закрывается', () async {
      // timeout = 100 мс, паузы между событиями = 50 мс.
      // Если бы таймер НЕ сбрасывался — стрим закрылся бы через 100 мс.
      final controller = StreamController<int>();
      final stream = controller.stream.withInactivityTimeout(
        const Duration(milliseconds: 100),
      );

      final events = <int>[];
      Object? caughtError;
      bool done = false;

      stream.listen(
        events.add,
        onError: (Object e) => caughtError = e,
        onDone: () => done = true,
      );

      // 5 событий с паузами 50 мс. Суммарно 250 мс > timeout (100 мс).
      // Но таймер сбрасывается на каждом событии — стрим должен жить.
      for (var i = 0; i < 5; i++) {
        controller.add(i);
        await Future.delayed(const Duration(milliseconds: 50));
      }

      // Даже после последнего события ждём 50 мс (меньше timeout) —
      // стрим ещё жив.
      expect(events, [0, 1, 2, 3, 4]);
      expect(caughtError, isNull);
      expect(done, isFalse);

      // Дожидаемся закрытия вручную.
      await controller.close();
      await Future.delayed(const Duration(milliseconds: 20));
      expect(done, isTrue);
    });
  });

  // ============================================================
  // 3. ТАЙМЕР СРАБАТЫВАЕТ ПРИ МОЛЧАНИИ
  // ============================================================

  group('таймер срабатывает при молчании', () {
    test('после паузы > timeout приходит NetworkException.timeout', () async {
      // timeout = 50 мс, пауза = 150 мс.
      final controller = StreamController<int>();
      final stream = controller.stream.withInactivityTimeout(
        const Duration(milliseconds: 50),
      );

      final events = <int>[];
      Object? caughtError;
      bool done = false;

      stream.listen(
        events.add,
        onError: (Object e) => caughtError = e,
        onDone: () => done = true,
      );

      controller.add(1);
      await Future.delayed(const Duration(milliseconds: 150));

      expect(events, [1]);
      expect(caughtError, isA<NetworkException>());
      expect((caughtError! as NetworkException).code, 'NETWORK_TIMEOUT');
      expect(done, isTrue);
    });

    test('если первое событие не приходит — тоже срабатывает', () async {
      // Стрим открыли, ничего не эмитим — ждём срабатывания.
      final controller = StreamController<int>();
      final stream = controller.stream.withInactivityTimeout(
        const Duration(milliseconds: 50),
      );

      final events = <int>[];
      Object? caughtError;
      bool done = false;

      stream.listen(
        events.add,
        onError: (Object e) => caughtError = e,
        onDone: () => done = true,
      );

      // Ничего не эмитим — ждём срабатывания watchdog.
      await Future.delayed(const Duration(milliseconds: 150));

      expect(events, isEmpty);
      expect(caughtError, isA<NetworkException>());
      expect(done, isTrue);
    });
  });

  // ============================================================
  // 4. ОШИБКА ИСТОЧНИКА
  // ============================================================

  group('ошибка источника', () {
    test('пробрасывается с той же ошибкой', () async {
      final controller = StreamController<int>();
      final stream = controller.stream.withInactivityTimeout(
        const Duration(milliseconds: 100),
      );

      final events = <int>[];
      Object? caughtError;
      bool done = false;

      stream.listen(
        events.add,
        onError: (Object e) => caughtError = e,
        onDone: () => done = true,
      );

      controller.add(1);
      await Future.delayed(const Duration(milliseconds: 10));
      controller.addError(StateError('source failed'));
      await Future.delayed(const Duration(milliseconds: 20));

      expect(events, [1]);
      expect(caughtError, isA<StateError>());
      expect(done, isTrue);
    });
  });

  // ============================================================
  // 5. ОТМЕНА ПОДПИСКИ КЛИЕНТОМ
  // ============================================================

  group('отмена подписки', () {
    test('cancel от клиента отписывается и от источника', () async {
      // Счётчик вызовов `onCancel` на источнике. Если он == 1 —
      // значит, transformer корректно пробросил cancel наверх.
      var sourceCancelCount = 0;
      final controller = StreamController<int>(
        onCancel: () => sourceCancelCount++,
      );

      final stream = controller.stream.withInactivityTimeout(
        const Duration(milliseconds: 100),
      );

      // Подписываемся и сразу отменяем.
      final subscription = stream.listen((_) {});
      await subscription.cancel();

      // Даём время на обработку cancel.
      await Future.delayed(const Duration(milliseconds: 20));

      expect(sourceCancelCount, 1);
    });
  });

  // ============================================================
  // 6. ИДЕМПОТЕНТНОСТЬ ЗАКРЫТИЯ
  // ============================================================

  group('идемпотентность', () {
    test(
      'после срабатывания таймера onDone источника не ломает стрим',
      () async {
        // Сценарий: сервер «завис», watchdog сработал, стрим закрылся.
        // Потом сервер «ожил» и прислал onDone. Наш трансформер должен
        // это проигнорировать — не падать, не эмитить событий.
        final controller = StreamController<int>();
        final stream = controller.stream.withInactivityTimeout(
          const Duration(milliseconds: 50),
        );

        final events = <int>[];
        final errors = <Object>[];
        bool done = false;

        stream.listen(
          events.add,
          onError: errors.add,
          onDone: () => done = true,
        );

        // Ничего не эмитим — ждём срабатывания watchdog.
        await Future.delayed(const Duration(milliseconds: 150));

        // На этом моменте уже: одна ошибка, done == true.
        expect(errors.length, 1);
        expect(errors.first, isA<NetworkException>());
        expect(done, isTrue);

        // Теперь закрываем источник — он «ожил» и завершился.
        // Трансформер должен это проигнорировать: у него уже isClosed = true.
        await controller.close();
        await Future.delayed(const Duration(milliseconds: 20));

        // Второй ошибки не пришло, событий новых нет.
        expect(errors.length, 1);
        expect(events, isEmpty);
      },
    );
  });
}
