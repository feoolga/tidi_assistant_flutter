// lib/screens/chat_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart'; // 👈 ДОБАВИТЬ
import '../models/message.dart';
import '../models/agent.dart';
import '../services/service_factory.dart';
import '../providers/agent_provider.dart'; // 👈 ДОБАВИТЬ
import '../widgets/message_bubble.dart';
import '../widgets/message_input.dart';
import '../widgets/chat_history_drawer.dart';
import '../providers/chat_history_provider.dart';

class ChatScreen extends ConsumerStatefulWidget {
  // 👈 ИЗМЕНИТЬ
  const ChatScreen({super.key});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState(); // 👈 ИЗМЕНИТЬ
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  // 👈 ИЗМЕНИТЬ
  final _chatService = ServiceFactory.getChatService();
  final ScrollController _scrollController = ScrollController();

  List<Message> _messages = [];
  bool _isLoading = false;

  String? _currentAgentId;
  String? _currentAgentName;
  bool _isFirstMessage = true;

  @override
  void initState() {
    super.initState();
    _loadMessages();
    _currentAgentName = 'AI Ассистент';
  }

  Future<void> _loadMessages() async {
    setState(() => _isLoading = true);
    try {
      final messages = await _chatService.getMessages();
      setState(() {
        _messages = messages;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Ошибка: $e')));
    }
  }

  Future<void> _loadChatMessages(String agentId, String chatId) async {
    setState(() => _isLoading = true);

    try {
      // Загружаем сообщения через провайдер
      final messages = await ref.read(
        chatMessagesProvider((agentId, chatId)).future,
      );

      setState(() {
        _messages = messages;
        _isLoading = false;
        _currentAgentId = agentId;
        _currentAgentName = _getAgentName(agentId);
        _isFirstMessage = false;
      });

      // Сохраняем сессию в сервисе для продолжения диалога
      _chatService.setSession(agentId, chatId);

      _scrollToBottom();
    } catch (e) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Ошибка загрузки сообщений: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // 👇 НОВЫЙ МЕТОД: получаем имя агента по ID из загруженного списка
  String _getAgentName(String agentId) {
    // Получаем состояние провайдера агентов
    final agentsAsync = ref.read(agentsProvider);

    // Если данные загружены, ищем агента
    if (agentsAsync is AsyncData<List<Agent>>) {
      try {
        final agent = agentsAsync.value.firstWhere(
          (a) => a.id == agentId,
          orElse: () => throw Exception('Агент не найден'),
        );
        return agent.name;
      } catch (e) {
        print('⚠️ Агент с ID $agentId не найден');
        return 'AI Ассистент';
      }
    }

    // Если данные еще не загружены, возвращаем дефолтное имя
    return 'AI Ассистент';
  }

  Future<void> _sendMessage(String text) async {
    setState(() => _isLoading = true);

    try {
      final result = await _chatService.sendMessage(text);

      final userMessage = Message(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        text: text,
        isFromUser: true,
        timestamp: DateTime.now(),
      );

      // 👇 ИСПРАВЛЕНО: используем _getAgentName вместо Agent.getNameById
      if (result.agentId != null && result.sessionId != null) {
        setState(() {
          _currentAgentId = result.agentId;
          _currentAgentName = _getAgentName(result.agentId!); // 👈 ИЗМЕНЕНО
          _isFirstMessage = false;
        });
        print('🔄 Текущий агент: $_currentAgentName (${_currentAgentId})');
      }

      final aiMessage = Message(
        id:
            result.messageId ??
            DateTime.now().millisecondsSinceEpoch.toString(),
        text: result.text,
        isFromUser: false,
        timestamp: DateTime.now(),
        agentId: result.agentId,
        sessionId: result.sessionId,
      );

      setState(() {
        _messages.add(userMessage);
        _messages.add(aiMessage);
        _isLoading = false;
      });

      _scrollToBottom();
    } catch (e) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Ошибка: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  Future<void> _clearChat() async {
    setState(() {
      _isLoading = true;
      _currentAgentId = null;
      _currentAgentName = 'AI Ассистент';
      _isFirstMessage = true;
    });

    try {
      await _chatService.clearMessages();
      await _loadMessages();
    } catch (e) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Ошибка очистки: $e')));
    }
  }

  void _startNewChat() {
    setState(() {
      _messages.clear();
      _currentAgentId = null;
      _currentAgentName = 'AI Ассистент';
      _isFirstMessage = true;
      _isLoading = false;
    });

    _chatService.resetSession();
    print('🔄 Новый чат создан');
  }

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: ChatHistoryDrawer(
        onChatSelected: (agentId, chatId) {
          print('📂 Выбран чат: agentId=$agentId, chatId=$chatId');
          _loadChatMessages(agentId, chatId);
          // TODO: загрузить выбранный чат
        },
        onChatCreated: _startNewChat,
        onResetSession: () {
          _chatService.resetSession();
        },
      ),
      appBar: AppBar(
        leading: Builder(
          // 👈 ОБЕРНИ В Builder
          builder: (context) => IconButton(
            icon: const Icon(Icons.menu),
            onPressed: () {
              Scaffold.of(context).openDrawer(); // 👈 ТЕПЕРЬ РАБОТАЕТ
            },
            tooltip: 'История чатов',
          ),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _currentAgentName ?? 'AI Ассистент',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
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
          Expanded(
            child: _isLoading && _messages.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    controller: _scrollController,
                    reverse: true,
                    padding: const EdgeInsets.all(8.0),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      final reversedIndex = _messages.length - 1 - index;
                      final message = _messages[reversedIndex];
                      return MessageBubble(message: message);
                    },
                  ),
          ),
          if (_currentAgentId != null && !_isFirstMessage)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              color: Colors.grey[100],
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.memory, size: 14, color: Colors.grey[600]),
                  const SizedBox(width: 4),
                  Text(
                    'Агент: $_currentAgentId',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                ],
              ),
            ),
          MessageInput(onSend: _sendMessage, isLoading: _isLoading),
        ],
      ),
    );
  }
}
