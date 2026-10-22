// lib/domain/services/chat_sources_fetcher.dart

import '../../core/logger/app_logger.dart';
import '../../data/repositories/chat_repository.dart';
import '../models/message_source.dart';

/// Один **батч** **sources** — **для** **конкретного** `messageId`.
///
/// **Зачем** **класс** **вместо** `MapEntry<String, List<MessageSource>>`:
/// - **семантическое** **имя** (`SourcesBatch` **читается** **лучше**,
///   **чем** `MapEntry`);
/// - **можно** **расширить** (**например**, **добавить** `error` **поле**,
///   **если** **sources** **не** **загрузились** — **на** **будущее**).
class SourcesBatch {
  final String messageId;
  final List<MessageSource> sources;

  const SourcesBatch({required this.messageId, required this.sources});
}

/// Сервис **загрузки** **sources** **для** **сообщений**.
///
/// **Ответственность**:
/// - **загрузить** **sources** **для** **одного** **сообщения**
///   (**сценарий** «**после** **стрима**»);
/// - **загрузить** **sources** **для** **многих** **сообщений**
///   **параллельно** (**сценарий** «**история**»).
///
/// **Что** **НЕ** **делает**:
/// - **не** **управляет** **state** (**это** `ChatNotifier`);
/// - **не** **применяет** **sources** **к** **сообщениям** (**это** `ChatNotifier`);
/// - **не** **читает** **провайдеры** (**зависимости** — **через** **конструктор**).
///
/// **Почему** **stateless**: **каждый** **вызов** — **независимый**.
/// **State** — **в** `ChatNotifier`.
///
/// **Почему** **не** **бросает** **при** **ошибке**: **sources** — **вторичны**.
/// **Ошибка** **загрузки** **одного** **сообщения** **не** **должна** **ронять**
/// **весь** **ход** (**ответ** **уже** **получен**, **пользователь** **его** **видит**).
/// **Ошибки** **логируем** **внутри**, **возвращаем** **пустой** **список**.
class ChatSourcesFetcher {
  final ChatRepository _repository;

  ChatSourcesFetcher({required ChatRepository repository})
    : _repository = repository;

  /// Загрузить **sources** **для** **одного** **сообщения**.
  ///
  /// **Когда** **используется**: **после** **стрима**
  /// (`ChatStreamCompleted`), **если** **это** **RAG-чат**.
  ///
  /// **Поведение** **при** **ошибке**: **логируем**, **возвращаем** `[]`.
  /// **Не** **пробрасываем** — **ответ** **уже** **получен**, **sources**
  /// **вторичны**.
  ///
  /// [agentId] — **id** **агента** (**для** **пути**
  /// `/agents/{agentId}/v1/chat/completions/{id}/sources`);
  /// [messageId] — **id** **ответа** (`resp_<uuid>`).
  Future<List<MessageSource>> fetchForMessage({
    required String agentId,
    required String messageId,
  }) async {
    try {
      final sources = await _repository.getSources(
        agentId: agentId,
        messageId: messageId,
      );
      AppLogger.debug(
        'ChatSourcesFetcher: для $messageId загружено ${sources.length} sources',
      );
      return sources;
    } catch (e, stackTrace) {
      // **Не** **роняем** — sources **вторичны**.
      AppLogger.logException(
        'ChatSourcesFetcher: ошибка загрузки sources для $messageId',
        e,
        stackTrace,
        {'agentId': agentId, 'messageId': messageId},
      );
      return const [];
    }
  }

  /// Загрузить **sources** **для** **многих** **сообщений** **параллельно**.
  ///
  /// **Когда** **используется**: **при** **загрузке** **истории**
  /// **RAG-чата** (`ChatNotifier.loadChat`).
  ///
  /// **Поведение**:
  /// - **параллельно** **запрашивает** **sources** **для** **всех** `messageIds`;
  /// - **ошибки** **отдельных** **запросов** — **логируем**, **не** **роняем**;
  /// - **возвращает** **только** **те** **батчи**, **где** **sources** **не** **пусты**.
  ///
  /// **Почему** **не** **возвращаем** **пустые** **батчи**: **в** `ChatNotifier`
  /// **у** **сообщения** **либо** **есть** **sources**, **либо** `null`
  /// (**не** **загружены**). **Пустой** `[]` **семантически** **означает**
  /// «**sources** **загружены**, **их** **нет**» — **это** **другой** **смысл**,
  /// **не** **тот**, **что** **нам** **нужен** (**«не** **загружены»**).
  ///
  /// **Почему** **параллельно**: 10 **последовательных** **запросов** =
  /// ~2 **секунды**. **Параллельно** = ~200 **мс** (**время** **самого**
  /// **долгого**).
  ///
  /// **Порядок** **батчей** **не** **гарантирован** — **вызывающий** **код**
  /// **не** **должен** **на** **него** **полагаться** (**собираем** **Map**,
  /// **где** **порядок** **не** **важен**).
  Future<List<SourcesBatch>> fetchForHistory({
    required String agentId,
    required List<String> messageIds,
  }) async {
    if (messageIds.isEmpty) {
      return const [];
    }

    AppLogger.info(
      'ChatSourcesFetcher: параллельная загрузка sources для '
      '${messageIds.length} сообщений',
    );

    // **Параллельно** **запрашиваем** **sources** **для** **всех**.
    //
    // **Почему** **через** **`map`** **+** **`Future.wait`**, **а** **не**
    // **`Future.forEach`**: **`forEach`** — **последовательно**.
    // **`Future.wait`** — **параллельно** (**все** **запускаются**
    // **одновременно**).
    //
    // **`async`** **внутри** **`map`** — **чтобы** **каждый** **запрос**
    // **сам** **ловил** **свою** **ошибку** (**try/catch** **внутри**).
    // **Иначе** **один** **упавший** **`getSources`** **→** **весь**
    // **`Future.wait`** **бросает** **исключение**.
    final results = await Future.wait(
      messageIds.map((messageId) async {
        try {
          final sources = await _repository.getSources(
            agentId: agentId,
            messageId: messageId,
          );
          if (sources.isEmpty) {
            return null; // **не** **включаем** **пустые**
          }
          return SourcesBatch(messageId: messageId, sources: sources);
        } catch (e, stackTrace) {
          AppLogger.logException(
            'ChatSourcesFetcher: ошибка загрузки sources для $messageId',
            e,
            stackTrace,
            {'agentId': agentId, 'messageId': messageId},
          );
          return null; // **не** **включаем** **упавшие**
        }
      }),
    );

    // **Фильтруем** `null` (**упавшие** **и** **пустые**).
    final batches = results.whereType<SourcesBatch>().toList();

    AppLogger.info(
      'ChatSourcesFetcher: загружено sources для '
      '${batches.length} из ${messageIds.length}',
    );

    return batches;
  }
}
