// lib/core/utils/stream_with_inactivity_timeout.dart

import 'dart:async';

import '../errors/network_exceptions.dart';

/// Трансформер стрима, который **закрывает его ошибкой**, если в течение
/// заданного времени не приходит **ни одного** события.
///
/// **Зачем нужен.** В SSE-стриме (и любом долгоживущем стриме)
/// возможна ситуация: сервер прислал несколько событий, а потом
/// **замолчал**, не закрыв соединение. TCP ещё жив, `await for` в
/// потребителе **висит бесконечно**. Watchdog решает это: если за
/// N секунд не пришло событий — считаем соединение «повисшим» и
/// эмитим [NetworkException.timeout].
///
/// **Что считать «событием».** Любое, что приходит из исходного стрима.
/// В нашем случае — включая heartbeat-маркер `_heartbeat` (эмитится
/// `SseParser` на каждую строку `: ping`). Heartbeat нужен именно для
/// того, чтобы watchdog **сбрасывался** во время долгого «раздумья»
/// сервера: агент `agentic_rag` обрабатывает сложные вопросы 56+ секунд,
/// но heartbeat приходит каждые ~15 секунд — значит, watchdog с таймаутом
/// 60 секунд не сработает зря.
///
/// **Почему в `core/utils`, а не в `SseParser`.** Это **универсальная**
/// утилита. Она не знает ни про SSE, ни про HTTP, ни про `ChatResponseDto`.
/// Работает для **любого** `Stream<S>`. Если в будущем появится второй
/// долгоживущий стрим (например, поток для голосового ввода или
/// фоновая синхронизация) — `withInactivityTimeout` применяется к нему
/// так же.
///
/// **Как использовать:**
/// ```dart
/// final safeStream = eventStream.withInactivityTimeout(
///   AppConfig.streamInactivityTimeout,
/// );
/// ```
class InactivityTimeoutTransformer<S> extends StreamTransformerBase<S, S> {
  /// Через сколько секунд тишины закрывать стрим.
  final Duration timeout;

  /// Создаёт трансформер с заданным таймаутом.
  const InactivityTimeoutTransformer(this.timeout);

  @override
  Stream<S> bind(Stream<S> source) {
    // 1. Контроллер — выдаёт события наружу.
    final controller = StreamController<S>();

    // 2. Текущий таймер. Меняется на каждое событие: старый отменяется,
    //    создаётся новый. `null` — после закрытия стрима (не нужно
    //    создавать новые таймеры).
    Timer? timer;

    // 3. Флаг «стрим уже закрыт». Защищает от попытки эмитить событие
    //    или создавать таймер после закрытия. Без флага возможны
    //    ошибки «Cannot add event to a closed controller».
    bool isClosed = false;

    // 4. Подписка на источник — присвоим сразу после listen.
    //    `late` потому что `listen` ссылается на `subscription`
    //    в `onCancel` замыкании.
    late StreamSubscription<S> subscription;

    // 5. Единая точка «закрыть стрим». Отменяет таймер, отписывается
    //    от источника, эмитит ошибку (если есть), закрывает контроллер.
    //    Идемпотентна: повторный вызов ничего не делает.
    void closeWith({Object? error, StackTrace? stackTrace}) {
      if (isClosed) return;
      isClosed = true;
      timer?.cancel();
      timer = null;
      subscription.cancel();
      if (error != null) {
        controller.addError(error, stackTrace);
      }
      controller.close();
    }

    // 6. Сброс таймера: отменяем старый, создаём новый.
    //    В Dart у `Timer` нет `reset()` — только `cancel()` + новый.
    //    Это правильная идиома для «сброса» таймера.
    void resetTimer() {
      if (isClosed) return;
      timer?.cancel();
      timer = Timer(timeout, () {
        // Таймер выстрелил: за timeout не пришло ни одного события.
        // Закрываем стрим с ошибкой «сервер долго не отвечает».
        closeWith(
          error: NetworkException.timeout(),
          stackTrace: StackTrace.current,
        );
      });
    }

    // 7. Запускаем таймер сразу при подписке — чтобы покрыть случай,
    //    когда сервер «молчит» ещё до первого события. Это важно:
    //    без этого сценария `streamInactivityTimeout` не защитил бы
    //    от «зависшего до первого события» соединения.
    resetTimer();

    // 8. Подписываемся на источник.
    subscription = source.listen(
      // На каждое событие — сбрасываем таймер и пробрасываем дальше.
      (event) {
        if (isClosed) return;
        resetTimer();
        controller.add(event);
      },
      // На ошибку — закрываем стрим с той же ошибкой.
      // Таймер не сбрасываем — ошибка уже означает конец.
      onError: (Object error, StackTrace stackTrace) {
        closeWith(error: error, stackTrace: stackTrace);
      },
      // На нормальное завершение — закрываем стрим без ошибки.
      onDone: () {
        closeWith();
      },
      // Если источник кинет ошибку — не продолжаем подписку.
      // По умолчанию `cancelOnError: false`, но нам нужно именно
      // завершить стрим при первой ошибке — см. `closeWith`.
      cancelOnError: false,
    );

    // 9. Если клиент отписался от нашего стрима — закрываем всё.
    //    Без этого источник продолжит эмитить в закрытый контроллер.
    controller.onCancel = () {
      closeWith();
    };

    return controller.stream;
  }
}

/// Сахар для удобного вызова: `stream.withInactivityTimeout(duration)`.
///
/// Расширение на любой `Stream<S>` — семантически продолжает
/// стандартные методы вроде `.map`, `.where`, `.whereType`. Помещается
/// в тот же namespace, поэтому читается как часть Dart API.
extension StreamInactivityTimeoutExtension<S> on Stream<S> {
  /// Обернуть стрим watchdog'ом: если за [timeout] не придёт ни одного
  /// события — стрим закроется с [NetworkException.timeout].
  ///
  /// **Пример использования:**
  /// ```dart
  /// final safeStream = eventStream.withInactivityTimeout(
  ///   AppConfig.streamInactivityTimeout,
  /// );
  /// ```
  Stream<S> withInactivityTimeout(Duration timeout) {
    return transform(InactivityTimeoutTransformer<S>(timeout));
  }
}
