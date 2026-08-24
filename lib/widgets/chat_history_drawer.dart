// lib/widgets/chat_history_drawer.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../domain/models/chat_session.dart';
import '../providers/chat_list_provider.dart';
import '../domain/models/agent.dart';
import '../providers/agent_provider.dart';
import '../theme/app_theme.dart';
import '../providers/chat_provider.dart';

// 👇 МЕНЯЕМ НА ConsumerStatefulWidget
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

// 👇 НОВЫЙ STATE-КЛАСС
class _ChatHistoryDrawerState extends ConsumerState<ChatHistoryDrawer> {
  // 👇 ФЛАГ ДЛЯ ПРЕДОТВРАЩЕНИЯ ПОВТОРНОЙ ЗАГРУЗКИ
  bool _isLoaded = false;

  @override
  Widget build(BuildContext context) {
    final chats = ref.watch(allChatsProvider);
    final isLoading = ref.watch(chatListLoadingProvider);
    final error = ref.watch(chatListErrorProvider);

    // 👇 ЗАГРУЖАЕМ ТОЛЬКО ОДИН РАЗ
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_isLoaded) {
        _loadChats();
        _isLoaded = true;
      }
    });

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

          // Список чатов
          Expanded(child: _buildChatList(chats, isLoading, error)),
        ],
      ),
    );
  }

  // ============================================================
  // ВСПОМОГАТЕЛЬНЫЕ МЕТОДЫ
  // ============================================================

  void _loadChats() {
    final agentsState = ref.read(agentsProvider);
    if (agentsState is AsyncData<List<Agent>>) {
      final notifier = ref.read(chatListNotifierProvider.notifier);
      notifier.updateAgents(agentsState.value);
      notifier.loadAllChats(agentsState.value);
    }
  }

  Future<void> _refreshChats() async {
    final agentsState = ref.read(agentsProvider);
    if (agentsState is AsyncData<List<Agent>>) {
      final notifier = ref.read(chatListNotifierProvider.notifier);
      await notifier.refresh(agents: agentsState.value);
    }
  }

  void _createNewChat(BuildContext context) async {
    Navigator.pop(context);

    // Обновляем список чатов
    await _refreshChats();

    widget.onChatCreated?.call();

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('🆕 Создан новый чат'),
          duration: Duration(seconds: 1),
        ),
      );
    }
  }

  Widget _buildChatList(
    List<ChatSession> chats,
    bool isLoading,
    String? error,
  ) {
    if (isLoading && chats.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (error != null && chats.isEmpty) {
      return Center(
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
                error,
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
      );
    }

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
    final agent = ref.watch(agentByIdProvider(chat.agentId));

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
        _formatTime(chat.updatedAt),
        style: TextStyle(fontSize: 11, color: Colors.grey[500]),
      ),
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    );
  }

  String _formatTime(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inDays > 0) {
      return '${diff.inDays}д';
    } else if (diff.inHours > 0) {
      return '${diff.inHours}ч';
    } else if (diff.inMinutes > 0) {
      return '${diff.inMinutes}м';
    } else {
      return 'только что';
    }
  }
}
