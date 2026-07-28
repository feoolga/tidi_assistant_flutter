import 'master_chat_service.dart';
import 'mock_chat_service.dart';

class ServiceFactory {
  // Используем реальный сервис
  static const bool useMock = false;

  // Базовый URL для API
  static const String apiUrl = 'http://89.109.54.73:8005/api';

  static dynamic getChatService() {
    if (useMock) {
      return MockChatService();
    } else {
      // Используем MasterChatService
      return MasterChatService(baseUrl: apiUrl);
    }
  }
}
