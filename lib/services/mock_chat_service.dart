// mock_chat_service.dart
import '../models/message.dart';

class MockChatService {
  // Храним сообщения в памяти
  final List<Message> _messages = [];

  // Генератор ID
  int _idCounter = 0;

  // Получить все сообщения
  Future<List<Message>> getMessages() async {
    // Если сообщений нет — создаём приветственное
    if (_messages.isEmpty) {
      _messages.addAll([
        Message(
          id: '${_idCounter++}',
          text: 'Привет! Я AI-ассистент. Задай мне вопрос!',
          isFromUser: false,
          timestamp: DateTime.now(),
        ),
      ]);
    }

    // Имитируем задержку сети (200ms)
    await Future.delayed(const Duration(milliseconds: 200));
    return List.from(_messages);
  }

  // Отправить сообщение
  Future<Map<String, Message>> sendMessage(String text) async {
    // Создаём сообщение пользователя
    final userMessage = Message(
      id: '${_idCounter++}',
      text: text,
      isFromUser: true,
      timestamp: DateTime.now(),
    );

    // Имитируем задержку ответа AI (1-2 секунды)
    await Future.delayed(const Duration(milliseconds: 1500));

    // Создаём ответ AI (мок)
    final aiResponse = _generateAIResponse(text);
    final aiMessage = Message(
      id: '${_idCounter++}',
      text: aiResponse,
      isFromUser: false,
      timestamp: DateTime.now(),
    );

    // Сохраняем в историю
    _messages.addAll([userMessage, aiMessage]);

    return {'user': userMessage, 'ai': aiMessage};
  }

  // Очистить историю
  Future<void> clearMessages() async {
    await Future.delayed(const Duration(milliseconds: 200));
    _messages.clear();

    // Добавляем приветственное сообщение
    _messages.add(
      Message(
        id: '${_idCounter++}',
        text: 'Чат очищен! Задайте новый вопрос.',
        isFromUser: false,
        timestamp: DateTime.now(),
      ),
    );
  }

  // Генерация ответа AI
  String _generateAIResponse(String userText) {
    // Простые заглушки для разных вопросов
    final responses = {
      'привет': 'Привет! Как я могу тебе помочь?',
      'как дела': 'У меня всё отлично! А как у тебя?',
      'погода': 'Сегодня замечательная погода для программирования! ☀️',
      'помощь':
          'Я твой AI-ассистент. Могу отвечать на вопросы, давать советы и помогать с задачами.',
      'спасибо': 'Пожалуйста! Всегда рад помочь! 😊',
    };

    // Ищем ключевые слова в сообщении
    for (final entry in responses.entries) {
      if (userText.toLowerCase().contains(entry.key)) {
        return entry.value;
      }
    }

    // Если нет совпадений — общий ответ
    final defaultResponses = [
      'Интересный вопрос! Я подумаю над этим.',
      'Хорошая мысль! Расскажи подробнее.',
      'Я понимаю, о чём ты говоришь. Давай обсудим детали.',
      'Отличный вопрос! Мне нужно немного времени, чтобы подумать.',
      'Спасибо за вопрос! Это очень важная тема.',
    ];

    return defaultResponses[DateTime.now().second % defaultResponses.length];
  }
}
