// lib/services/service_factory.dart

import 'agent_service.dart';
import 'chat_history_service.dart';
import 'master_chat_service.dart';
import '../data/repositories/chat_repository.dart';
import '../data/datasources/remote/chat_api.dart';
import '../core/network/http_client.dart';

/// Фабрика для создания сервисов.
///
/// ВНИМАНИЕ! Этот файл УСТАРЕВАЕТ.
/// Новые провайдеры используют ChatRepository напрямую.
///
/// @deprecated Используйте провайдеры из agent_provider.dart и chat_provider.dart
class ServiceFactory {
  // ============================================================
  // 1. КОНСТАНТЫ (для обратной совместимости)
  // ============================================================

  @Deprecated('Используйте AppConfig.baseUrl')
  static const String apiUrl = 'http://89.109.54.73:8005/api';

  // ============================================================
  // 2. ФАБРИЧНЫЕ МЕТОДЫ
  // ============================================================

  /// Создает AgentService (старый, скоро удалим)
  @Deprecated('Используйте chatRepositoryProvider.getAgents()')
  static AgentService getAgentService() {
    return AgentService(baseUrl: apiUrl);
  }

  /// Создает ChatHistoryService (НОВЫЙ, использует Repository)
  static ChatHistoryService getChatHistoryService() {
    // Создаем зависимости
    final httpClient = AppHttpClient();
    final chatApi = ChatApi(httpClient: httpClient);
    final repository = ChatRepository(api: chatApi);

    // Возвращаем сервис с Repository
    return ChatHistoryService(repository: repository);
  }

  /// Создает MasterChatService (старый, скоро удалим)
  @Deprecated('Используйте ChatRepository.sendMessage()')
  static MasterChatService getChatService() {
    return MasterChatService(baseUrl: apiUrl);
  }
}
