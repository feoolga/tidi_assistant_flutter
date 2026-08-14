// lib/services/service_factory.dart

import 'agent_service.dart';
import 'chat_history_service.dart';
import 'openai_chat_service.dart';
import 'mock_chat_service.dart';

class ServiceFactory {
  static const bool useMock = false;

  // 👇 ПРАВИЛЬНЫЙ URL (с портом 8005 и /api)
  static const String apiUrl = 'http://89.109.54.73:8005/api';

  static AgentService getAgentService() {
    return AgentService(baseUrl: apiUrl);
  }

  static ChatHistoryService getChatHistoryService() {
    return ChatHistoryService(baseUrl: apiUrl);
  }

  static dynamic getChatService() {
    if (useMock) {
      return MockChatService();
    } else {
      // 👇 ВОЗВРАЩАЕМ OpenAIChatService
      return OpenAIChatService(baseUrl: apiUrl);
    }
  }
}