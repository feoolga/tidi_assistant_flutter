// lib/screens/chat_screen.dart
import 'package:flutter/material.dart';
import '../models/message.dart';
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

  @override
  void initState() {
    super.initState();
    _loadMessages();
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
      // 1. Отправляем сообщение и получаем ответ
      final result = await _chatService.sendMessage(text);

      // 2. Создаем сообщение пользователя
      final userMessage = Message(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        text: text,
        isFromUser: true,
        timestamp: DateTime.now(),
      );

      // 3. Создаем сообщение ассистента из ответа
      final aiMessage = Message(
        id:
            result['messageId'] ??
            DateTime.now().millisecondsSinceEpoch.toString(),
        text: result['text'],
        isFromUser: false,
        timestamp: DateTime.now(),
      );

      // 4. Добавляем оба сообщения в список
      setState(() {
        _messages.add(userMessage);
        _messages.add(aiMessage);
        _isLoading = false;
      });

      // 5. Прокручиваем вниз
      _scrollToBottom();
    } catch (e) {
      setState(() => _isLoading = false);

      // Показываем ошибку в SnackBar
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('❌ Ошибка: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _clearChat() async {
    setState(() => _isLoading = true);
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
    // Немного ждем, пока UI обновится
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          0, // reverse = true, поэтому 0 = конец списка
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
        title: const Text('AI Assistant Chat'),
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
                    reverse: true, // Новые сообщения снизу
                    padding: const EdgeInsets.all(8.0),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      // Инвертируем индекс для reverse
                      final reversedIndex = _messages.length - 1 - index;
                      final message = _messages[reversedIndex];
                      return MessageBubble(message: message);
                    },
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
