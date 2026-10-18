// lib/widgets/message_bubble.dart
import 'package:flutter/material.dart';
import '../domain/models/attachment.dart';
import '../domain/models/message.dart';
import '../theme/app_theme.dart';
import 'attachment_preview.dart';
import 'typing_indicator.dart';
import '../core/utils/date_format.dart';
import 'message_sources.dart';
import '../domain/models/message_status.dart';

class MessageBubble extends StatelessWidget {
  final Message message;
  final bool isStreaming;

  const MessageBubble({
    super.key,
    required this.message,
    this.isStreaming = false,
  });

  @override
  Widget build(BuildContext context) {
    final isFromUser = message.isFromUser;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0, horizontal: 16.0),
      child: Row(
        mainAxisAlignment: isFromUser
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        children: [
          // Контейнер сообщения.
          //
          // **Ширина — разная для user и AI.**
          // - User: пузырь по содержимому, но не шире 75% ширины экрана.
          //   Так он выглядит компактно и «прижат» к правому краю —
          //   привычный паттерн мессенджеров.
          // - AI: пузырь **на всю ширину родителя** (по требованию техдира).
          //   Оборачиваем в `Expanded` — это виджет, который внутри `Row`
          //   говорит: «займи всё оставшееся место». Без `Expanded`
          //   `Container` сам не растянется — он по умолчанию «по содержимому».
          //
          // **Почему не через `maxWidth` для AI.** Потолок `maxWidth` **не
          // растягивает** `Container` — он лишь ограничивает сверху. Если
          // AI-сообщение короткое — пузырь останется узким, а нужен
          // полноширинный. Поэтому для AI — `Expanded`, для user — `maxWidth`.
          if (isFromUser)
            Container(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.75,
              ),
              padding: const EdgeInsets.symmetric(
                horizontal: 16.0,
                vertical: 12.0,
              ),
              decoration: _buildBubbleDecoration(isFromUser),
              child: _buildBubbleContent(context),
            )
          else
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16.0,
                  vertical: 12.0,
                ),
                decoration: _buildBubbleDecoration(isFromUser),
                child: _buildBubbleContent(context),
              ),
            ),
        ],
      ),
    );
  }

  /// Decoration пузыря — одинаковый для user и AI, кроме цвета/тени/бордера.
  ///
  /// Вынесено в отдельный метод, потому что эта часть **не зависит**
  /// от `Expanded`/`Container` обёртки — а значит, логично её
  /// переиспользовать, не дублируя.
  BoxDecoration _buildBubbleDecoration(bool isFromUser) {
    return BoxDecoration(
      // Цвет как в web-версии
      color: isFromUser
          ? AppTheme
                .primaryLight // #F2FBFA - фон пользователя
          : Colors.white, // Белый - фон AI
      borderRadius: BorderRadius.only(
        topLeft: const Radius.circular(16.0),
        topRight: const Radius.circular(16.0),
        bottomLeft: isFromUser
            ? const Radius.circular(16.0)
            : const Radius.circular(4.0),
        bottomRight: isFromUser
            ? const Radius.circular(4.0)
            : const Radius.circular(16.0),
      ),
      // Тень как в web
      boxShadow: isFromUser
          ? [] // У пользователя нет тени
          : [
              BoxShadow(
                color: Colors.grey.withValues(alpha: 0.1),
                spreadRadius: 1,
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
      // Бордер как в web
      border: isFromUser
          ? Border.all(
              color: AppTheme.primary.withValues(alpha: 0.3),
              width: 1.0,
            )
          : null,
    );
  }

  /// Содержимое пузыря — текст, вложения, источники, время.
  ///
  /// Вынесено из `build` по той же причине: эта часть **не зависит**
  /// от того, обёрнут ли контейнер в `Expanded` или нет.
  Widget _buildBubbleContent(BuildContext context) {
    final isFromUser = message.isFromUser;
    final bool showTypingIndicator =
        !isFromUser && message.text.isEmpty && isStreaming;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Текст, индикатор набора или пометка об ошибке.
        //
        // **Три сценария — в порядке приоритета:**
        // 1. Стрим идёт, текста нет → «typing indicator» (точки);
        // 2. Сообщение упало (status == failed) → пометка об ошибке;
        // 3. Обычный текст → просто текст.
        //
        // **Почему `failed` — до `text.isNotEmpty`.** У failed-сообщений
        // `text` **пустой** (сервер прервал генерацию). Если проверять
        // текст первым — failed «утонет» в пустоте и покажется пустой
        // пузырь с одним временем. Это и было проблемой на стенде.
        //
        // **Почему `failed` — после `showTypingIndicator`.** Если идёт
        // **текущий** стрим (пользователь только что отправил), а
        // предыдущее сообщение в истории оказалось failed — мы **не**
        // хотим, чтобы «typing indicator» перекрывался пометкой
        // об ошибке. `showTypingIndicator` привязан к **последнему**
        // пустому AI-сообщению — если оно **не** failed (стрим идёт),
        // покажем точки. Если failed — покажем ошибку.
        if (showTypingIndicator)
          const TypingIndicator()
        else if (message.status == MessageStatus.failed)
          _buildFailedContent()
        else if (message.text.isNotEmpty)
          Text(
            message.text,
            style: const TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 16,
              height: 1.4,
            ),
          ),

        // Вложения — если есть. Идут под текстом, над временем.
        if (message.attachments.isNotEmpty) ...[
          if (showTypingIndicator || message.text.isNotEmpty)
            const SizedBox(height: 8),
          _buildAttachments(message.attachments),
        ],

        // Sources — только у AI, только если непустые.
        // `document_chat` кладёт их в само сообщение,
        // `agentic_rag` — догружает отдельной ручкой (см.
        // `ChatNotifier._loadSourcesForMessage`). Здесь UI
        // просто показывает то, что уже есть в `Message`.
        if (!isFromUser &&
            message.sources != null &&
            message.sources!.isNotEmpty) ...[
          if (showTypingIndicator ||
              message.text.isNotEmpty ||
              message.attachments.isNotEmpty)
            const SizedBox(height: 4),
          MessageSources(sources: message.sources!),
        ],

        const SizedBox(height: 4),

        // Время.
        if (!showTypingIndicator)
          Text(
            formatTime(message.timestamp),
            style: TextStyle(
              color: isFromUser
                  ? AppTheme.textSecondary.withValues(alpha: 0.7)
                  : AppTheme.textSecondary.withValues(alpha: 0.5),
              fontSize: 10,
            ),
          ),
      ],
    );
  }

  /// Пометка о неудачной генерации ответа.
  ///
  /// Показывается, когда `message.status == MessageStatus.failed` —
  /// сервер **не смог** получить ответ (типичный случай —
  /// `client_disconnected` при обрыве SSE-стрима).
  ///
  /// **Что делаем:**
  /// - иконка ⚠ (`Icons.error_outline`) — **мягкий** сигнал, не красный;
  /// - текст «Не удалось получить ответ. Проверьте подключение
  ///   к интернету» — объясняет **причину** и **что делать**;
  /// - цвет — `AppTheme.textSecondary` (серый), **не** красный —
  ///   чтобы **не пугать** пользователя (это **не** критическая
  ///   ошибка его действий).
  ///
  /// **Что НЕ делаем:**
  /// - **не** показываем `message.errorMessage` (типа
  ///   `"client_disconnected"`) — это **техническая** деталь, она
  ///   остаётся в логах;
  /// - **не** показываем кнопку «Повторить» — это **следующая** итерация
  ///   (в беклоге, после показа);
  /// - **не** меняем фон/рамку пузыря — только содержимое.
  Widget _buildFailedContent() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          Icons.error_outline,
          size: 18,
          // Мягкий серый, а не красный — чтобы не пугать.
          color: AppTheme.textSecondary,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'Не удалось получить ответ. '
            'Проверьте подключение к интернету.',
            style: TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 14,
              height: 1.4,
              fontStyle: FontStyle.italic,
            ),
          ),
        ),
      ],
    );
  }

  /// Превью вложений внутри сообщения — компактный вид, без кнопки удаления.
  ///
  /// `Wrap` вместо `Row`: если файлов несколько и они не влезают по ширине,
  /// автоматически переносим на следующую строку. Компактный размер (60×60)
  /// выбран, чтобы превью не «съедало» пузырь сообщения.
  Widget _buildAttachments(List<Attachment> attachments) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final attachment in attachments)
          AttachmentPreview(
            attachment: attachment,
            compact: true,
            // В отправленном сообщении удалять вложения нельзя — сервер
            // уже принял их; onRemove оставляем null.
          ),
      ],
    );
  }
}
