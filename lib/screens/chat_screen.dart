// lib/screens/chat_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/logger/app_logger.dart';
import '../providers/chat_provider.dart';
import '../providers/session_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/chat_history_drawer.dart';
import '../widgets/message_bubble.dart';
import '../widgets/message_input.dart';

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final ScrollController _scrollController = ScrollController();

  // ============================================================
  // ЖИЗНЕННЫЙ ЦИКЛ
  // ============================================================

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  // ============================================================
  // ВСПОМОГАТЕЛЬНЫЕ МЕТОДЫ
  // ============================================================

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  /// Получить имя агента для отображения в AppBar.
  String _getAgentName(String? agentId) {
    if (agentId == null) return 'AI Ассистент';

    final agentNames = {
      'chat': 'Чат-агент',
      'epoz': 'ЕПоЗ',
      'ocr': 'OCR',
      'document_chat': 'Документы',
    };
    return agentNames[agentId] ?? 'AI Ассистент';
  }

  // ============================================================
  // МЕТОДЫ-ОБРАБОТЧИКИ СОБЫТИЙ
  // ============================================================

  void _sendMessage(String text) {
    ref.read(chatProvider.notifier).sendMessage(text: text);
    Future.delayed(const Duration(milliseconds: 100), _scrollToBottom);
  }

  void _loadChat(String agentId, String chatId) {
    AppLogger.info('Загружаем чат: агент=$agentId, чат=$chatId');
    ref.read(chatProvider.notifier).loadChat(agentId, chatId);
  }

  void _clearChat() {
    ref.read(chatProvider.notifier).clearChat();
  }

  void _startNewChat() {
    ref.read(chatProvider.notifier).createNewChat();
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    // Подписываемся на состояние чата (сообщения, загрузка, стриминг).
    final chatState = ref.watch(chatProvider);
    final messages = chatState.messages;
    final isLoading = chatState.isLoading;

    // Сессия — из SSOT (`sessionProvider`), не из `chatState`.
    // `select` — чтобы `ChatScreen` перестраивался только при смене
    // `agentId`, а не при каждом изменении сессии.
    final currentAgentId = ref.watch(sessionProvider.select((s) => s.agentId));

    // Показ ошибки — как side effect, через `ref.listen`.
    //
    // `select` — подписываемся ТОЛЬКО на поле `error`, а не на весь
    // `ChatState`. Callback сработает один раз на изменение, а не на
    // каждый build. Side effects в `build` (через `addPostFrameCallback`)
    // — антипаттерн: `build` вызывается часто, callback'и копятся.
    ref.listen<String?>(chatProvider.select((s) => s.error), (previous, next) {
      if (next == null || next.isEmpty) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ $next'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
      // Очищаем ошибку после показа — чтобы `SnackBar` не показался
      // повторно при следующем изменении state.
      ref.read(chatProvider.notifier).clearError();
    });

    // Показ информационного сообщения — тоже через `ref.listen`.
    ref.listen<String?>(chatProvider.select((s) => s.infoMessage), (
      previous,
      next,
    ) {
      if (next == null || next.isEmpty) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('ℹ️ $next'),
          backgroundColor: AppTheme.primary,
          duration: const Duration(seconds: 3),
        ),
      );
      ref.read(chatProvider.notifier).clearInfoMessage();
    });

    return Scaffold(
      drawer: ChatHistoryDrawer(
        onChatSelected: (agentId, chatId) {
          AppLogger.info('Выбран чат: агент=$agentId, чат=$chatId');
          _loadChat(agentId, chatId);
        },
        onChatCreated: _startNewChat,
      ),
      appBar: AppBar(
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.menu),
            onPressed: () {
              Scaffold.of(context).openDrawer();
            },
            tooltip: 'История чатов',
          ),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _getAgentName(currentAgentId),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            if (currentAgentId != null)
              Text(
                'Агент: $currentAgentId',
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: _clearChat,
            tooltip: 'Очистить чат',
          ),
        ],
      ),
      body: Column(
        children: [
          // ============================================================
          // ОСНОВНОЙ СПИСОК СООБЩЕНИЙ
          // ============================================================
          Expanded(
            child: messages.isEmpty && isLoading
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    controller: _scrollController,
                    reverse: true,
                    padding: const EdgeInsets.all(8.0),
                    itemCount: messages.length,
                    itemBuilder: (context, index) {
                      final reversedIndex = messages.length - 1 - index;
                      final message = messages[reversedIndex];

                      final bool isStreamingForThisMessage =
                          chatState.isStreaming &&
                          !message.isFromUser &&
                          message.text.isEmpty;

                      return MessageBubble(
                        message: message,
                        isStreaming: isStreamingForThisMessage,
                      );
                    },
                  ),
          ),

          // ============================================================
          // ИНДИКАТОР ТЕКУЩЕГО АГЕНТА
          // ============================================================
          if (currentAgentId != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              color: Colors.grey[100],
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.memory, size: 14, color: Colors.grey[600]),
                  const SizedBox(width: 4),
                  Text(
                    'Агент: $currentAgentId',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                ],
              ),
            ),

          // ============================================================
          // ПОЛЕ ВВОДА СООБЩЕНИЯ
          // ============================================================
          MessageInput(onSend: _sendMessage, isLoading: isLoading),
        ],
      ),
    );
  }
}
