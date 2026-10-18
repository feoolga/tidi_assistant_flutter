// lib/domain/models/message.dart

import 'attachment.dart';
import 'message_source.dart';
import 'message_status.dart';

/// Модель сообщения в чате.
/// Используется как для сообщений пользователя, так и для ответов AI.
class Message {
  // ============================================================
  // 1. ОСНОВНЫЕ ПОЛЯ (обязательные)
  // ============================================================

  /// Уникальный ID сообщения (генерируется на клиенте или приходит с сервера).
  final String id;

  /// Текст сообщения (собранный из токенов для AI, или введённый пользователем).
  final String text;

  /// `true` — сообщение от пользователя, `false` — от AI.
  final bool isFromUser;

  /// Время отправки/получения сообщения.
  final DateTime timestamp;

  // ============================================================
  // 2. ДОПОЛНИТЕЛЬНЫЕ ПОЛЯ (опциональные)
  // ============================================================

  /// ID агента, который ответил (только для сообщений AI).
  final String? agentId;

  /// ID сессии (чата) на бэкенде (только для сообщений AI).
  final String? sessionId;

  // ============================================================
  // 3. ВЛОЖЕНИЯ
  // ============================================================

  /// Вложения, прикреплённые к сообщению пользователя.
  ///
  /// Для сообщений AI — всегда пусто (AI не прикрепляет файлы).
  /// Для сообщений пользователя — файлы, отправленные вместе с текстом.
  /// UI использует это, чтобы показать превью файлов в истории сообщений.
  final List<Attachment> attachments;

  // ============================================================
  // 4. ПОЛЯ ДЛЯ БУДУЩЕГО
  // ============================================================

  /// Источники, на которые опирался AI при генерации ответа.
  ///
  /// Для `agentic_rag` — заполнены `order`/`chunkId`/`documentId`/
  /// `chunkIndex` (см. `MessageSource`). Для `document_chat` —
  /// только `filename`.
  ///
  /// `null` — если поле не пришло от сервера. Пустой список `[]` —
  /// если ответ не использовал источников.
  final List<MessageSource>? sources;

  /// Оценка/фидбэк от пользователя (лайк/дизлайк).
  ///
  /// Формат: `{"vote": 1 | -1 | null, "comment": "..." | null}` или `null`.
  final Map<String, dynamic>? feedback;

  /// Статус сообщения — по данным сервера.
  ///
  /// **Зачем нужен.** Сервер может вернуть сообщение с `status: "failed"`
  /// — например, если SSE-стрим оборвался (`client_disconnected`).
  /// В таком случае `text` **пустой**, и без визуальной пометки
  /// пользователь увидит «пустой пузырь» и не поймёт, что произошло.
  ///
  /// **Тип — не nullable.** Всегда есть **какой-то** статус:
  /// - `ok` — по умолчанию (если сервер не сказал обратного);
  /// - `failed` — генерация упала;
  /// - `pending` — обрабатывается.
  ///
  /// **Источник:** поле `status` из `GET .../messages`
  /// (см. README Agentic RAG). Для `document_chat` `status` **не**
  /// приходит — маппер поставит `ok` по умолчанию, и это корректно.
  final MessageStatus status;

  /// Текст ошибки, если `status == MessageStatus.failed`. Иначе `null`.
  ///
  /// **Пример значения:** `"client_disconnected"` — сервер прервал
  /// генерацию, потому что клиент отвалился от SSE-стрима. Значение
  /// **техническое** — для отладки и логов, **не** для показа
  /// пользователю напрямую. UI показывает общий текст
  /// «Не удалось получить ответ».
  ///
  /// **Имя `errorMessage`, а не `error`.** Согласовано с полем
  /// `Attachment.errorMessage` — «текст ошибки, привязанный к сущности».
  /// В DTO поле называется `error` (зеркало JSON), а в домене —
  /// `errorMessage` (смысловое имя). Переименование — в маппере.
  final String? errorMessage;

  // ============================================================
  // МАРКЕР ДЛЯ copyWith
  // ============================================================

  /// Специальный объект-маркер.
  /// Означает: "это поле не было передано в copyWith".
  static const _unset = Object();

  // ============================================================
  // 5. КОНСТРУКТОРЫ
  // ============================================================

  /// Основной конструктор — все поля обязательны (кроме опциональных).
  const Message({
    required this.id,
    required this.text,
    required this.isFromUser,
    required this.timestamp,
    this.agentId,
    this.sessionId,
    this.attachments = const [],
    this.sources,
    this.feedback,
    this.status = MessageStatus.ok,
    this.errorMessage,
  });

  // ------------------------------------------------------------
  // 5.1. Создание сообщения из SSE-потока
  // ------------------------------------------------------------

  /// Используется, когда мы собираем сообщение из токенов SSE-потока.
  factory Message.fromStream({
    required String text,
    String? agentId,
    String? sessionId,
    String? messageId,
    bool isFromUser = false,
    List<MessageSource>? sources,
  }) {
    return Message(
      id: messageId ?? DateTime.now().millisecondsSinceEpoch.toString(),
      text: text,
      isFromUser: isFromUser,
      timestamp: DateTime.now(),
      agentId: agentId,
      sessionId: sessionId,
      sources: sources,
    );
  }

  // ------------------------------------------------------------
  // 5.2. Создание сообщения пользователя
  // ------------------------------------------------------------

  /// Удобный конструктор для быстрого создания сообщения пользователя.
  ///
  /// [attachments] — файлы, прикреплённые к этому сообщению.
  factory Message.fromUser({
    required String text,
    String? id,
    List<Attachment> attachments = const [],
  }) {
    return Message(
      id: id ?? DateTime.now().millisecondsSinceEpoch.toString(),
      text: text,
      isFromUser: true,
      timestamp: DateTime.now(),
      attachments: attachments,
    );
  }

  // ------------------------------------------------------------
  // 5.3. Создание сообщения AI
  // ------------------------------------------------------------

  /// Удобный конструктор для быстрого создания ответа AI.
  factory Message.fromAI({
    required String text,
    String? id,
    String? agentId,
    String? sessionId,
    List<MessageSource>? sources,
  }) {
    return Message(
      id: id ?? DateTime.now().millisecondsSinceEpoch.toString(),
      text: text,
      isFromUser: false,
      timestamp: DateTime.now(),
      agentId: agentId,
      sessionId: sessionId,
      sources: sources,
    );
  }

  // ============================================================
  // 6. СЕРИАЛИЗАЦИЯ
  // ============================================================

  /// Преобразует сообщение в JSON для отправки на бэкенд.
  ///
  /// **Внимание:** сейчас не используется — отправка идёт через
  /// `ChatRepository._buildInput`, а не через этот метод. Оставлен
  /// на случай будущей сериализации (например, кэширование на клиенте).
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'text': text,
      'isFromUser': isFromUser,
      'timestamp': timestamp.toIso8601String(),
      if (agentId != null) 'agentId': agentId,
      if (sessionId != null) 'sessionId': sessionId,
      if (sources != null) 'sources': sources,
      if (feedback != null) 'feedback': feedback,
      if (status != MessageStatus.ok) 'status': status.name,
      if (errorMessage != null) 'errorMessage': errorMessage,
    };
  }

  // ============================================================
  // 7. КОПИРОВАНИЕ (immutable-паттерн)
  // ============================================================

  /// Создаёт копию сообщения с изменёнными полями.
  ///
  /// Nullable-поля (`agentId`, `sessionId`, `sources`, `feedback`)
  /// используют маркер [_unset], чтобы отличать «не передали»
  /// от «передали null для сброса».
  Message copyWith({
    String? id,
    String? text,
    bool? isFromUser,
    DateTime? timestamp,
    Object? agentId = _unset,
    Object? sessionId = _unset,
    List<Attachment>? attachments,
    Object? sources = _unset,
    Object? feedback = _unset,
    MessageStatus? status,
    Object? errorMessage = _unset,
  }) {
    return Message(
      id: id ?? this.id,
      text: text ?? this.text,
      isFromUser: isFromUser ?? this.isFromUser,
      timestamp: timestamp ?? this.timestamp,
      agentId: identical(agentId, _unset) ? this.agentId : agentId as String?,
      sessionId: identical(sessionId, _unset)
          ? this.sessionId
          : sessionId as String?,
      attachments: attachments ?? this.attachments,
      sources: identical(sources, _unset)
          ? this.sources
          : sources as List<MessageSource>?,
      feedback: identical(feedback, _unset)
          ? this.feedback
          : feedback as Map<String, dynamic>?,
      status: status ?? this.status,
      errorMessage: identical(errorMessage, _unset)
          ? this.errorMessage
          : errorMessage as String?,
    );
  }

  // ============================================================
  // 8. ОТЛАДКА
  // ============================================================

  @override
  String toString() {
    final preview = text.length > 20 ? '${text.substring(0, 20)}...' : text;
    return 'Message(id: $id, text: "$preview", isFromUser: $isFromUser, '
        'agentId: $agentId, sessionId: $sessionId, sources: $sources)';
  }
}
