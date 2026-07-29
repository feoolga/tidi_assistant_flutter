// lib/services/service_factory.dart

import 'agent_service.dart';
import 'chat_history_service.dart';
import 'master_chat_service.dart';
import 'mock_chat_service.dart';

class ServiceFactory {
  // Используем реальный сервис
  static const bool useMock = false;

  // Базовый URL для API
  static const String apiUrl = 'http://89.109.54.73:8005/api';

  // 📌 НОВОЕ: Сервис для агентов
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
      return MasterChatService(baseUrl: apiUrl);
    }
  }
}
