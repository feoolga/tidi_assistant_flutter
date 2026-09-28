// lib/widgets/message_input.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/errors/file_exceptions.dart';
import '../core/logger/app_logger.dart';
import '../providers/attachment_draft_provider.dart';
import '../providers/session_provider.dart';
import '../theme/app_theme.dart';
import 'attachment_picker_helper.dart';
import 'attachment_preview.dart';

/// Поле ввода сообщения с кнопками «прикрепить», «микрофон», «отправить»
/// и списком превью прикреплённых файлов над полем ввода.
///
/// **Источники данных:**
/// - **вложения-черновики** — из `attachmentDraftProvider`
///   (список, статус загрузки, признак «все готовы»);
/// - **сессия** — из `sessionProvider` (чтобы блокировать прикрепление
///   в чужом чате);
/// - **флаг отправки** — приходит снаружи через `widget.isLoading`.
///
/// **Чего тут НЕТ:**
/// - `chatProvider` — этот виджет больше не знает про состояние чата.
///   Отправка сообщения — забота `ChatScreen` (он вызывает колбэк
///   `onSend`, а тот — `chatProvider.sendMessage`).
/// - Логика «все вложения готовы» — она переехала в геттер
///   `AttachmentDraftState.allAttachmentsReady`.
class MessageInput extends ConsumerStatefulWidget {
  /// Колбэк отправки — принимает текст. Может быть пустым,
  /// если отправляются только вложения.
  final Function(String) onSend;

  /// Идёт ли **отправка сообщения** (не загрузка файла!).
  ///
  /// Приходит из `ChatScreen` — тот читает `chatProvider.isLoading`.
  /// Пока `true` — блокируем и отправку, и прикрепление.
  ///
  /// **Не путать** с `attachmentDraftProvider.isLoading` — тот про
  /// **загрузку файла** и читается из провайдера напрямую.
  final bool isLoading;

  const MessageInput({super.key, required this.onSend, this.isLoading = false});

  @override
  ConsumerState<MessageInput> createState() => _MessageInputState();
}

class _MessageInputState extends ConsumerState<MessageInput> {
  final TextEditingController _controller = TextEditingController();
  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_updateHasText);
    _updateHasText();
  }

  @override
  void dispose() {
    _controller.removeListener(_updateHasText);
    _controller.dispose();
    super.dispose();
  }

  void _updateHasText() {
    final hasText = _controller.text.trim().isNotEmpty;
    if (_hasText != hasText) {
      setState(() {
        _hasText = hasText;
      });
    }
  }

  // ============================================================
  // ОТПРАВКА
  // ============================================================

  void _sendMessage() {
    final text = _controller.text.trim();
    final draftState = ref.read(attachmentDraftProvider);
    final hasAttachments = draftState.hasAttachments;

    // Не отправляем, если есть незагруженные (или упавшие) вложения —
    // иначе сообщение уйдёт без файла, и пользователь не поймёт, почему
    // AI его «не увидел».
    if (hasAttachments && !draftState.allAttachmentsReady) {
      // Показываем подсказку — иначе пользователь подумает, что кнопка сломана.
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Дождитесь загрузки файлов'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    if ((text.isEmpty && !hasAttachments) || widget.isLoading) return;

    _controller.clear();
    setState(() => _hasText = false);
    widget.onSend(text);
  }

  // ============================================================
  // ПРИКРЕПЛЕНИЕ
  // ============================================================

  Future<void> _pickAndAttach() async {
    // Пока диалог возвращает один файл (allowMultiple: false).
    // Если включим мультивыбор — здесь нужна очередь, потому что
    // addAttachment защищён от повторного вызова через isLoading
    // в attachmentDraftProvider.
    try {
      final files = await AttachmentPickerHelper.pickFiles();
      if (files.isEmpty) return; // пользователь отменил

      for (final file in files) {
        await ref.read(attachmentDraftProvider.notifier).addAttachment(file);
      }
    } on FileException catch (e) {
      // Ошибка открытия диалога — показываем локально,
      // потому что в attachmentDraftProvider эта ошибка не попадает
      // (это ошибка на этапе выбора файла, до загрузки).
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ ${e.userMessage}'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    } catch (e, stackTrace) {
      AppLogger.logException(
        'Неожиданная ошибка при выборе файла',
        e,
        stackTrace,
      );
    }
  }

  // ============================================================
  // ФЛАГИ ДОСТУПНОСТИ
  // ============================================================

  /// Можно ли сейчас прикреплять файл.
  ///
  /// Блокируем, если:
  /// - идёт отправка сообщения (`widget.isLoading`);
  /// - идёт загрузка предыдущего вложения (`draftState.isLoading`);
  /// - открыт чужой чат (агент известен и не `document_chat`).
  ///
  /// **Почему `document_chat` захардкожен:** на текущий момент только
  /// этот агент принимает файлы. Когда появится `AgentConfig` с флагом
  /// `canUploadFiles`, проверим флаг вместо сравнения со строкой.
  bool _canAttach({
    required bool draftIsLoading,
    required String? currentAgentId,
  }) {
    if (widget.isLoading) return false;
    if (draftIsLoading) return false;
    if (currentAgentId != null && currentAgentId != 'document_chat') {
      return false;
    }
    return true;
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    final draftState = ref.watch(attachmentDraftProvider);
    final sessionState = ref.watch(sessionProvider);

    final hasAttachments = draftState.hasAttachments;
    final allAttachmentsReady = draftState.allAttachmentsReady;

    // Отправка доступна, если есть текст или вложения,
    // нет активной отправки, и все вложения готовы.
    final canSend =
        (_hasText || hasAttachments) &&
        !widget.isLoading &&
        allAttachmentsReady;

    final canAttach = _canAttach(
      draftIsLoading: draftState.isLoading,
      currentAgentId: sessionState.agentId,
    );

    return Container(
      padding: const EdgeInsets.all(12.0),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          top: BorderSide(
            color: AppTheme.primary.withValues(alpha: 0.2),
            width: 1.0,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Превью прикреплённых файлов — только если есть что показывать.
            if (hasAttachments) _buildAttachmentsBar(draftState),

            // Основная строка: прикрепить, микрофон, поле ввода, отправка.
            Row(
              children: [
                // 📎 Кнопка прикрепления файла
                IconButton(
                  onPressed: canAttach ? _pickAndAttach : null,
                  icon: Icon(
                    Icons.attach_file,
                    color: canAttach ? AppTheme.primary : Colors.grey[400],
                    size: 24,
                  ),
                  tooltip: 'Прикрепить файл',
                  padding: const EdgeInsets.all(8),
                  constraints: const BoxConstraints(),
                ),

                // 🎙️ Кнопка микрофона (заглушка на будущее)
                IconButton(
                  onPressed: widget.isLoading ? null : () {},
                  icon: Icon(
                    Icons.mic,
                    color: widget.isLoading
                        ? Colors.grey[400]
                        : AppTheme.primary,
                    size: 24,
                  ),
                  tooltip: 'Голосовое сообщение',
                  padding: const EdgeInsets.all(8),
                  constraints: const BoxConstraints(),
                ),

                const SizedBox(width: 4),

                // 📝 Поле ввода
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppTheme.primaryLight,
                      borderRadius: BorderRadius.circular(20.0),
                      border: Border.all(
                        color: _hasText
                            ? AppTheme.primary
                            : AppTheme.primary.withValues(alpha: 0.3),
                        width: 1.5,
                      ),
                    ),
                    child: TextField(
                      controller: _controller,
                      enabled: !widget.isLoading,
                      decoration: InputDecoration(
                        hintText: widget.isLoading
                            ? 'Ожидание ответа...'
                            : 'Ваше сообщение...',
                        hintStyle: TextStyle(
                          color: Colors.grey[400],
                          fontSize: 15,
                        ),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16.0,
                          vertical: 12.0,
                        ),
                        prefixIcon: null,
                        suffixIcon: null,
                      ),
                      style: const TextStyle(
                        fontSize: 16,
                        color: AppTheme.textPrimary,
                      ),
                      onSubmitted: (_) => _sendMessage(),
                      maxLines: null,
                      minLines: 1,
                    ),
                  ),
                ),

                const SizedBox(width: 8),

                // 🚀 Кнопка отправки
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: canSend ? AppTheme.primary : Colors.grey[300],
                  ),
                  child: IconButton(
                    onPressed: canSend ? _sendMessage : null,
                    icon: const Icon(
                      Icons.send_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // ПРЕВЬЮ ВЛОЖЕНИЙ
  // ============================================================

  /// Список превью прикреплённых файлов.
  ///
  /// Источник — `AttachmentDraftState.attachments` (черновик).
  /// Тап на крестик удаляет вложение из черновика — **не** с сервера
  /// (сервер сам подчистит «осиротевший» объект).
  Widget _buildAttachmentsBar(AttachmentDraftState draftState) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: SizedBox(
        height: 96, // 80 квадрат + место на крестик сверху
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          // Небольшой отступ сверху, чтобы крестик удаления не резался.
          padding: const EdgeInsets.only(top: 8),
          itemCount: draftState.attachments.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (context, index) {
            final attachment = draftState.attachments[index];
            return AttachmentPreview(
              attachment: attachment,
              onRemove: () {
                ref
                    .read(attachmentDraftProvider.notifier)
                    .removeAttachment(attachment.localId);
              },
            );
          },
        ),
      ),
    );
  }
}
