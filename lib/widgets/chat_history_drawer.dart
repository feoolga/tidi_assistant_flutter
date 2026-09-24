// lib/widgets/chat_history_drawer.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/errors/error_handler.dart';
import '../core/logger/app_logger.dart';
import '../core/utils/date_format.dart';
import '../domain/models/chat_session.dart';
import '../providers/agent_provider.dart';
import '../providers/chat_list_provider.dart';
import '../providers/chat_provider.dart';
import '../providers/session_provider.dart';
import '../theme/app_theme.dart';

class ChatHistoryDrawer extends ConsumerStatefulWidget {
  final void Function(String agentId, String chatId) onChatSelected;
  final VoidCallback? onChatCreated;
  final VoidCallback? onResetSession;

  const ChatHistoryDrawer({
    super.key,
    required this.onChatSelected,
    this.onChatCreated,
    this.onResetSession,
  });

  @override
  ConsumerState<ChatHistoryDrawer> createState() => _ChatHistoryDrawerState();
}

class _ChatHistoryDrawerState extends ConsumerState<ChatHistoryDrawer> {
  @override
  Widget build(BuildContext context) {
    // `chatsProvider` сам ждёт агентов и грузит чаты.
    // Никаких `ref.listen`, `_isLoaded`, `listenManual` — всё ушло.
    final chatsAsync = ref.watch(chatsProvider);

    return Drawer(
      child: Column(
        children: [
          // Header
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 48, 16, 16),
            decoration: BoxDecoration(
              color: AppTheme.primary,
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(16),
                bottomRight: Radius.circular(16),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'История чатов',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Все диалоги с AI-агентами',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.white.withValues(alpha: 0.8),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      _createNewChat(context);
                    },
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Новый чат'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: AppTheme.primary,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Список чатов — теперь через `.when()`.
          Expanded(child: _buildChatList(chatsAsync)),
        ],
      ),
    );
  }

  // ============================================================
  // ВСПОМОГАТЕЛЬНЫЕ МЕТОДЫ
  // ============================================================

  Future<void> _refreshChats() async {
    // `ref.invalidate` — «сбрось кэш и перезагрузи».
    // Эквивалент старого `notifier.refresh(agents: ...)`.
    ref.invalidate(chatsProvider);
  }

  void _createNewChat(BuildContext context) {
    // 1. Закрываем дровер
    Navigator.pop(context);

    // 2. Вызываем колбэк, который очистит локальное состояние
    widget.onChatCreated?.call();
  }

  /// Открыть диалог переименования чата.
  ///
  /// **Что делает:**
  /// 1. Показывает `AlertDialog` с `TextField`, предзаполненным
  ///    текущим названием (`chat.displayTitle`).
  /// 2. Ждёт, пока пользователь нажмёт «Сохранить» или «Отмена».
  /// 3. Если «Отмена» **или** пустой ввод **или** имя не изменилось —
  ///    молча выходит (не дёргает сервер зря).
  /// 4. Иначе — вызывает `ChatRepository.renameConversation`.
  /// 5. После успеха — `ref.invalidate(chatsProvider)` + `SnackBar`.
  /// 6. При ошибке — `SnackBar` с `ErrorHandler.getUserMessage`.
  Future<void> _showRenameDialog(ChatSession chat) async {
    // 1. Контроллер с текущим названием.
    //
    // `TextEditingController` создаётся **внутри** метода. Это ок,
    // потому что диалог живёт **короткое** время. `dispose` не нужен:
    // после закрытия диалога контроллер станет unreachable и его
    // заберёт GC.
    final controller = TextEditingController(text: chat.displayTitle);

    // 2. Показываем диалог и ждём ответа.
    //
    // `showDialog<String>` возвращает `Future<String?>`:
    // - `String` — если пользователь нажал «Сохранить» (мы вернули текст);
    // - `null` — если «Отмена» или закрыл по фону.
    final newTitle = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Переименовать чат'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Введите название',
            border: OutlineInputBorder(),
          ),
          textInputAction: TextInputAction.done,
          // `onSubmitted` — нажатие Enter на клавиатуре.
          // Эквивалент нажатия «Сохранить».
          onSubmitted: (value) => Navigator.pop(dialogContext, value.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.pop(dialogContext, controller.text.trim()),
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );

    // 3. Отмена или пустой ввод — выходим без запроса.
    if (newTitle == null || newTitle.isEmpty) return;

    // 4. Если название не изменилось — тоже не дёргаем сервер.
    if (newTitle == chat.displayTitle) return;

    // 5. Вызываем репозиторий.
    try {
      await ref
          .read(chatRepositoryProvider)
          .renameConversation(
            agentId: chat.agentId,
            conversationId: chat.id,
            title: newTitle,
          );

      // 6. Перезагружаем список чатов — обновлённый title появится.
      ref.invalidate(chatsProvider);

      // 7. Подтверждение пользователю.
      //
      // `mounted` — проверка, что виджет ещё в дереве. После `await`
      // виджет мог быть удалён (пользователь закрыл drawer, ушёл
      // на другой экран). Без проверки — краш.
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Чат переименован'),
          duration: Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ ${ErrorHandler.getUserMessage(e)}'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  /// Открыть диалог удаления чата.
  ///
  /// **Что делает:**
  /// 1. Показывает диалог подтверждения (удаление **необратимо**).
  /// 2. Если «Отмена» — выходит.
  /// 3. Иначе — вызывает `ChatRepository.deleteConversation`.
  /// 4. После успеха:
  ///    - если удалили **текущий** чат — очищает сессию
  ///      и создаёт новый чат (см. [_handleCurrentChatDeletion]);
  ///    - `ref.invalidate(chatsProvider)` — перезагрузка списка;
  ///    - `SnackBar` «Чат удалён».
  /// 5. При ошибке — `SnackBar` с `ErrorHandler.getUserMessage`.
  Future<void> _showDeleteDialog(ChatSession chat) async {
    // 1. Диалог подтверждения.
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Удалить чат?'),
        content: Text(
          'Чат «${chat.displayTitle}» и вся его история будут удалены. '
          'Это действие нельзя отменить.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );

    // 2. Отмена или закрытие по фону — выходим.
    if (confirmed != true) return;

    // 3. Вызываем репозиторий.
    try {
      await ref
          .read(chatRepositoryProvider)
          .deleteConversation(agentId: chat.agentId, conversationId: chat.id);

      // 4. Обрабатываем случай удаления **текущего** чата.
      //    Если это он — надо очистить сессию, иначе пользователь
      //    останется в несуществующем чате и получит 404
      //    при следующей отправке.
      await _handleCurrentChatDeletion(chat);

      // 5. Перезагружаем список чатов — удалённого чата больше нет.
      ref.invalidate(chatsProvider);

      // 6. Подтверждение.
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('🗑 Чат удалён'),
          duration: Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ ${ErrorHandler.getUserMessage(e)}'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  /// Обработать удаление **текущего** чата (того, что открыт в `ChatScreen`).
  ///
  /// **Зачем:** если удалить чат, в котором пользователь **сейчас**
  /// находится, `sessionProvider` продолжит указывать на несуществующий
  /// `conversationId`. При следующей отправке — `404`.
  ///
  /// **Что делаем:**
  /// 1. Читаем `sessionProvider` — смотрим, какой чат сейчас активен.
  /// 2. Если это **не** удаляемый чат — ничего не делаем.
  /// 3. Если **удаляемый** — очищаем сессию и создаём новый чат.
  ///
  /// **Почему через `ref.read`, а не `ref.watch`:**
  /// `watch` вызвал бы **перерисовку** `_ChatHistoryDrawerState` при
  /// любом изменении сессии. Нам это не нужно — мы просто **проверяем**
  /// и действуем один раз.
  Future<void> _handleCurrentChatDeletion(ChatSession chat) async {
    final session = ref.read(sessionProvider);

    // Удаляем не текущий — ничего не делаем.
    if (session.sessionId != chat.id) return;

    AppLogger.info(
      'Удалён текущий чат ${chat.id} — сбрасываем сессию и создаём новый',
    );

    // Сбрасываем сессию (agentId + sessionId → null).
    ref.read(sessionProvider.notifier).clearSession();

    // Создаём «новый чат» — очищаем сообщения, добавляем welcome.
    ref.read(chatProvider.notifier).createNewChat();
  }

  Widget _buildChatList(AsyncValue<List<ChatSession>> chatsAsync) {
    return chatsAsync.when(
      loading: () => const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: CircularProgressIndicator(),
        ),
      ),
      error: (error, stack) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 16),
              Text(
                'Ошибка загрузки чатов',
                style: TextStyle(fontSize: 16, color: Colors.grey[600]),
              ),
              Text(
                ErrorHandler.getUserMessage(error),
                style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _refreshChats,
                child: const Text('Повторить'),
              ),
            ],
          ),
        ),
      ),
      data: (chats) {
        if (chats.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.chat_bubble_outline, size: 48, color: Colors.grey),
                  SizedBox(height: 16),
                  Text(
                    'Нет чатов',
                    style: TextStyle(fontSize: 16, color: Colors.grey),
                  ),
                  Text(
                    'Начните новый диалог',
                    style: TextStyle(fontSize: 14, color: Colors.grey),
                  ),
                ],
              ),
            ),
          );
        }

        return RefreshIndicator(
          onRefresh: _refreshChats,
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: chats.length,
            itemBuilder: (context, index) {
              final chat = chats[index];
              return _ChatItem(
                chat: chat,
                onTap: () {
                  Navigator.pop(context);
                  widget.onChatSelected(chat.agentId, chat.id);
                },
                // Колбэки меню — открывают диалоги.
                // Замыкание захватывает `chat` — то есть **этот**
                // конкретный чат, а не тот, что был бы в `index`.
                onRename: () => _showRenameDialog(chat),
                onDelete: () => _showDeleteDialog(chat),
              );
            },
          ),
        );
      },
    );
  }
}

// ============================================================
// _ChatItem — карточка одного чата в списке
// ============================================================

/// Карточка одного чата в списке `ChatHistoryDrawer`.
///
/// **Ответственности:**
/// - отобразить чат (аватар агента, название, время);
/// - показать контекстное меню (три точки) с действиями
///   «Переименовать» и «Удалить».
///
/// **Что НЕ делает:**
/// - не вызывает репозиторий — за это отвечают колбэки,
///   переданные сверху ([onRename], [onDelete]).
///
/// **Почему колбэки, а не прямая работа с репозиторием:**
/// - `_ChatItem` остаётся **чистым UI** — легко тестировать;
/// - вся логика (диалоги, обработка ошибок, `ref.invalidate`) —
///   в родителе, в одном месте;
/// - если завтра понадобится показать то же меню в другом месте —
///   `_ChatItem` переиспользуется без изменений.
class _ChatItem extends ConsumerWidget {
  /// Чат, который отображается.
  final ChatSession chat;

  /// Колбэк по тапу на карточку — открыть чат.
  final VoidCallback onTap;

  /// Колбэк «Переименовать» из меню. Может быть `null` —
  /// тогда пункт меню **не показывается** (нет смысла показывать
  /// действие, которое ничего не делает).
  final VoidCallback? onRename;

  /// Колбэк «Удалить» из меню. Может быть `null` — аналогично.
  final VoidCallback? onDelete;

  const _ChatItem({
    required this.chat,
    required this.onTap,
    this.onRename,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final agent = ref.watch(agentsByIdProvider)[chat.agentId];

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: AppTheme.primary.withValues(alpha: 0.1),
        child: Text(
          agent?.name.substring(0, 1).toUpperCase() ?? '?',
          style: const TextStyle(
            color: AppTheme.primary,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      title: Text(
        chat.displayTitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
      ),
      subtitle: Text(
        agent?.name ?? 'AI Ассистент',
        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
      ),
      // `trailing` — правая часть строки. Было одно `Text` с временем,
      // стало `Row` из двух элементов: время + `PopupMenuButton`.
      //
      // `mainAxisSize: MainAxisSize.min` — `Row` занимает **минимум**
      // ширины. Без него `Row` растянется на всю доступную ширину,
      // и меню уедет к самому краю — некрасиво.
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Время (или прочерк, если дата неизвестна).
          Text(
            chat.updatedAt != null ? formatRelative(chat.updatedAt!) : '—',
            style: TextStyle(fontSize: 11, color: Colors.grey[500]),
          ),

          // Контекстное меню — три точки.
          //
          // Показываем, **только** если есть хотя бы один колбэк.
          // Если оба `null` — пользователь ничего не сможет сделать,
          // и показывать «пустое» меню бессмысленно.
          if (onRename != null || onDelete != null)
            PopupMenuButton<String>(
              // `icon` — три точки. Можно не указывать (это дефолт),
              // но явно — читаемее.
              icon: const Icon(Icons.more_vert, size: 20),

              // `tooltip` — подсказка при долгом тапе.
              tooltip: 'Действия с чатом',

              // `onSelected` — вызывается, когда пользователь выбрал
              // пункт меню. `value` — то, что мы указали в `PopupMenuItem`.
              onSelected: (value) {
                switch (value) {
                  case 'rename':
                    onRename?.call();
                  case 'delete':
                    onDelete?.call();
                }
              },

              // `itemBuilder` — строит список пунктов меню.
              // Вызывается **один раз** при открытии меню.
              itemBuilder: (menuContext) => [
                // Пункт «Переименовать» — только если есть колбэк.
                if (onRename != null)
                  const PopupMenuItem<String>(
                    value: 'rename',
                    child: Row(
                      children: [
                        Icon(Icons.edit_outlined, size: 18),
                        SizedBox(width: 12),
                        Text('Переименовать'),
                      ],
                    ),
                  ),

                // Пункт «Удалить» — только если есть колбэк.
                // Красный цвет — визуально выделяем опасное действие.
                if (onDelete != null)
                  const PopupMenuItem<String>(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(Icons.delete_outline, size: 18, color: Colors.red),
                        SizedBox(width: 12),
                        Text('Удалить', style: TextStyle(color: Colors.red)),
                      ],
                    ),
                  ),
              ],
            ),
        ],
      ),
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    );
  }
}
