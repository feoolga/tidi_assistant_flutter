// lib/services/service_factory.dart

import 'agent_service.dart';
import 'chat_history_service.dart';
import 'master_chat_service.dart';  // 👈 МЕНЯЕМ ИМПОРТ

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

  /// Возвращает сервис для работы с чатом
  /// Используем MasterChatService (он умеет работать с мастер-роутингом)
  static MasterChatService getChatService() {  // 👈 МЕНЯЕМ ТИП ВОЗВРАТА
    return MasterChatService(baseUrl: apiUrl);
  }
}