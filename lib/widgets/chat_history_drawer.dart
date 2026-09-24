// lib/widgets/chat_history_drawer.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../domain/models/chat_session.dart';
import '../providers/chat_list_provider.dart';
import '../providers/agent_provider.dart';
import '../theme/app_theme.dart';
import '../core/utils/date_format.dart';
import '../core/errors/error_handler.dart';

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
              );
            },
          ),
        );
      },
    );
  }
}

// ============================================================
// _ChatItem — без изменений
// ============================================================

class _ChatItem extends ConsumerWidget {
  final ChatSession chat;
  final VoidCallback onTap;

  const _ChatItem({required this.chat, required this.onTap});

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
      trailing: Text(
        // Если дата обновления неизвестна — показываем прочерк.
        // Не подставляем `DateTime.now()`: это выглядело бы как
        // «только что», хотя на самом деле мы не знаем дату.
        chat.updatedAt != null ? formatRelative(chat.updatedAt!) : '—',
        style: TextStyle(fontSize: 11, color: Colors.grey[500]),
      ),
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    );
  }
}
