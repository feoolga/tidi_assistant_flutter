// lib/domain/usecases/watch_rag_readiness_usecase.dart

import 'dart:async';

import '../../core/config/app_config.dart';
import '../../core/errors/error_handler.dart';
import '../../core/logger/app_logger.dart';
import '../../data/repositories/rag_repository.dart';
import '../models/rag_set.dart';

/// UseCase ожидания готовности RAG-набора.
///
/// **Что делает.** Возвращает [Stream] с обновлениями `RagSet`
/// каждые [AppConfig.ragPollInterval] секунд, пока `hasPending == true`.
/// Как только `hasPending == false` — эмитит финальный `RagSet`
/// и **закрывает** стрим.
///
/// **Что НЕ делает (MVP):**
/// - не выносит polling в отдельный сервис — логика внутри;
/// - не делает retry при ошибке `get` — **одна** ошибка закрывает стрим;
/// - не хранит историю обновлений — только **последнее** состояние.
///
/// **Таймаут.** Если за [AppConfig.ragPollTimeout] готовность не
/// наступила — кидает [RagException] в стрим и закрывает его.
///
/// **Отмена.** Если клиент отписался — таймер отменяется,
/// контроллер закрывается. Без утечек.
class WatchRagReadinessUseCase {
  final RagRepository _repository;

  WatchRagReadinessUseCase({required RagRepository repository})
    : _repository = repository;

  Stream<RagSet> execute({required String ragId}) {
    final controller = StreamController<RagSet>();

    Timer? timer;
    final startedAt = DateTime.now();
    bool isClosed = false;

    void close({Object? error, StackTrace? stackTrace}) {
      if (isClosed) return;
      isClosed = true;
      timer?.cancel();
      if (error != null) {
        controller.addError(error, stackTrace);
      }
      controller.close();
    }

    Future<void> poll() async {
      try {
        // Проверяем таймаут ДО запроса.
        if (DateTime.now().difference(startedAt) > AppConfig.ragPollTimeout) {
          close(
            error: ErrorHandler.handle(
              StateError('RAG polling timeout'),
              StackTrace.current,
              'RAG-набор $ragId не готов за '
              '${AppConfig.ragPollTimeout.inMinutes} мин',
              {'ragId': ragId},
            ),
          );
          return;
        }

        final set = await _repository.get(ragId);
        if (isClosed) return;
        controller.add(set);

        if (!set.hasPending) {
          AppLogger.info('RAG-набор готов: $ragId');
          close();
        }
      } catch (e, stackTrace) {
        close(error: e, stackTrace: stackTrace);
      }
    }

    // Первый запрос — сразу, без задержки.
    // `scheduleMicrotask` — чтобы клиент успел подписаться.
    scheduleMicrotask(poll);

    // Далее — периодически.
    timer = Timer.periodic(AppConfig.ragPollInterval, (_) => poll());

    controller.onCancel = () {
      isClosed = true;
      timer?.cancel();
    };

    return controller.stream;
  }
}
