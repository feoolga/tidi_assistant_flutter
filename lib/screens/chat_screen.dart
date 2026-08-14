// lib/screens/chat_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/chat_provider.dart';  // 👈 НАШ НОВЫЙ ПРОВАЙДЕР
import '../widgets/message_bubble.dart';
import '../widgets/message_input.dart';
import '../widgets/chat_history_drawer.dart';

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
    // При создании экрана проверяем, есть ли сообщения
    // Если нет — будет показано приветственное (оно уже есть в ChatNotifier)
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  // ============================================================
  // ВСПОМОГАТЕЛЬНЫЕ МЕТОДЫ
  // ============================================================

  /// Прокрутка вниз (к последнему сообщению)
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

  /// Получить имя агента для отображения в AppBar
  String _getAgentName(String? agentId) {
    if (agentId == null) return 'AI Ассистент';
    
    // Пока просто возвращаем ID, позже можно будет загружать из списка агентов
    // или сделать маппинг
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

  /// Отправить сообщение
  void _sendMessage(String text) {
    // Получаем notifier и вызываем sendMessage
    ref.read(chatProvider.notifier).sendMessage(text);
    
    // Прокручиваем вниз после отправки
    Future.delayed(const Duration(milliseconds: 100), _scrollToBottom);
  }

  /// Загрузить чат из истории
  void _loadChat(String agentId, String chatId) {
    print('📂 Загружаем чат: agentId=$agentId, chatId=$chatId');
    ref.read(chatProvider.notifier).loadChat(agentId, chatId);
  }

  /// Очистить чат
  void _clearChat() {
    ref.read(chatProvider.notifier).clearChat();
  }

  /// Создать новый чат (сброс сессии)
  void _startNewChat() {
    ref.read(chatProvider.notifier).resetSession();
    // Показываем уведомление
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('🔄 Новый чат создан'),
        duration: Duration(seconds: 1),
      ),
    );
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    // 👇 ПОДПИСЫВАЕМСЯ НА СОСТОЯНИЕ ЧАТА
    final chatState = ref.watch(chatProvider);
    final messages = chatState.messages;
    final isLoading = chatState.isLoading;
    final currentAgentId = chatState.currentAgentId;
    final error = chatState.error;

    // Если есть ошибка — показываем SnackBar
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (error != null && error.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ $error'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
        // Очищаем ошибку после показа
        ref.read(chatProvider.notifier).clearError();
      }
    });

    return Scaffold(
      drawer: ChatHistoryDrawer(
        onChatSelected: (agentId, chatId) {
          print('📂 Выбран чат: agentId=$agentId, chatId=$chatId');
          _loadChat(agentId, chatId);
        },
        onChatCreated: _startNewChat,
        onResetSession: () {
          ref.read(chatProvider.notifier).resetSession();
        },
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
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            if (currentAgentId != null)
              Text(
                'Агент: $currentAgentId',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                ),
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
                ? const Center(
                    child: CircularProgressIndicator(),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    reverse: true,
                    padding: const EdgeInsets.all(8.0),
                    itemCount: messages.length,
                    itemBuilder: (context, index) {
                      final reversedIndex = messages.length - 1 - index;
                      final message = messages[reversedIndex];
                      return MessageBubble(message: message);
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
          MessageInput(
            onSend: _sendMessage,
            isLoading: isLoading,
          ),
        ],
      ),
    );
  }
}