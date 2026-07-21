// lib/screens/chat_screen.dart

import 'package:flutter/material.dart';
import '../models/message.dart';
import '../models/agent.dart';
import '../services/chat_service.dart';
import '../services/service_factory.dart';
import '../widgets/message_bubble.dart';
import '../widgets/message_input.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _chatService = ServiceFactory.getChatService();
  final ScrollController _scrollController = ScrollController();

  List<Message> _messages = [];
  bool _isLoading = false;
  
  // 👇 НОВЫЕ ПЕРЕМЕННЫЕ ДЛЯ ОТСЛЕЖИВАНИЯ АГЕНТА
  String? _currentAgentId;
  String? _currentAgentName;
  bool _isFirstMessage = true; // Флаг для первого сообщения

  @override
  void initState() {
    super.initState();
    _loadMessages();
    
    // Устанавливаем имя агента по умолчанию
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

  Future<void> _sendMessage(String text) async {
    setState(() => _isLoading = true);

    try {
      // 1. Отправляем сообщение и получаем результат
      final result = await _chatService.sendMessage(text);

      // 2. Создаем сообщение пользователя
      final userMessage = Message(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        text: text,
        isFromUser: true,
        timestamp: DateTime.now(),
      );

      // 3. 👇 ОБНОВЛЯЕМ ИНФОРМАЦИЮ ОБ АГЕНТЕ (если она есть)
      if (result.agentId != null && result.sessionId != null) {
        setState(() {
          _currentAgentId = result.agentId;
          _currentAgentName = Agent.getNameById(result.agentId!);
          _isFirstMessage = false;
        });
        print('🔄 Текущий агент: $_currentAgentName (${_currentAgentId})');
      }

      // 4. Создаем сообщение ассистента с информацией об агенте
      final aiMessage = Message(
        id: result.messageId ?? DateTime.now().millisecondsSinceEpoch.toString(),
        text: result.text,
        isFromUser: false,
        timestamp: DateTime.now(),
        agentId: result.agentId,      // 👈 Сохраняем ID агента
        sessionId: result.sessionId,  // 👈 Сохраняем ID сессии
      );

      // 5. Добавляем оба сообщения в список
      setState(() {
        _messages.add(userMessage);
        _messages.add(aiMessage);
        _isLoading = false;
      });

      // 6. Прокручиваем вниз
      _scrollToBottom();
    } catch (e) {
      setState(() => _isLoading = false);

      // Показываем ошибку в SnackBar
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
    // 👇 СБРАСЫВАЕМ СОСТОЯНИЕ АГЕНТА ПРИ ОЧИСТКЕ ЧАТА
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
      appBar: AppBar(
        // 👇 ДИНАМИЧЕСКИЙ ЗАГОЛОВОК С ИМЕНЕМ АГЕНТА
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _currentAgentName ?? 'AI Ассистент',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            // 👇 ПОКАЗЫВАЕМ ID АГЕНТА МЕЛКИМ ШРИФТОМ (для отладки)
            if (_currentAgentId != null)
              Text(
                'ID: $_currentAgentId',
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.normal,
                  opacity: 0.6,
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
          // Список сообщений
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
          // 👇 ПОКАЗЫВАЕМ ИНФОРМАЦИЮ О ТЕКУЩЕМ АГЕНТЕ (для отладки)
          if (_currentAgentId != null && !_isFirstMessage)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              color: Colors.grey[100],
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.memory,
                    size: 14,
                    color: Colors.grey[600],
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Агент: $_currentAgentName',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
          // Поле ввода
          MessageInput(
            onSend: _sendMessage,
            isLoading: _isLoading,
          ),
        ],
      ),
    );
  }
}