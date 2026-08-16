// lib/providers/chat_history_provider.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/chat_session.dart';
import '../models/message.dart';
import '../services/chat_history_service.dart';
import '../services/service_factory.dart';
import 'agent_provider.dart';

/// Провайдер для сервиса истории чатов
final chatHistoryServiceProvider = Provider<ChatHistoryService>((ref) {
  return ServiceFactory.getChatHistoryService();
});

/// Провайдер для получения чатов конкретного агента
final agentChatsProvider = FutureProvider.family<List<ChatSession>, String>((ref, agentId) async {
  final service = ref.read(chatHistoryServiceProvider);
  print('📦 Загружаем чаты для агента: $agentId');
  try {
    final chats = await service.getChats(agentId);
    print('✅ Загружено чатов для $agentId: ${chats.length}');
    return chats;
  } catch (e) {
    print('❌ Ошибка загрузки чатов для $agentId: $e');
    return [];
  }
});

/// Провайдер для получения сообщений конкретного чата
final chatMessagesProvider = FutureProvider.family<List<Message>, (String agentId, String chatId)>((ref, params) async {
  final service = ref.read(chatHistoryServiceProvider);
  final (agentId, chatId) = params;
  print('📦 Загружаем сообщения: agentId=$agentId, chatId=$chatId');
  try {
    final messages = await service.getMessages(agentId, chatId);
    print('✅ Загружено сообщений: ${messages.length}');
    return messages;
  } catch (e) {
    print('❌ Ошибка загрузки сообщений: $e');
    return [];
  }
});

/// Провайдер для получения ВСЕХ чатов (от всех агентов)
final allChatsProvider = FutureProvider<List<ChatSession>>((ref) async {
  final agentsAsync = ref.watch(agentsProvider);

  if (agentsAsync is AsyncLoading) {
    return [];
  }

  if (agentsAsync is AsyncError) {
    print('⚠️ Ошибка загрузки агентов: ${agentsAsync.error}');
    return [];
  }

  final agents = agentsAsync.value;
  if (agents == null || agents.isEmpty) {
    print('⚠️ Нет загруженных агентов');
    return [];
  }

  print('📦 Загружаем чаты для ${agents.length} агентов...');
  List<ChatSession> allChats = [];

  for (final agent in agents) {
    try {
      // 👇 ИСПОЛЬЗУЕМ agent.id, а не agentId
      final chats = await ref.read(agentChatsProvider(agent.id).future);
      allChats.addAll(chats);
    } catch (e) {
      print('⚠️ Не удалось загрузить чаты для агента ${agent.id}: $e');
    }
  }

  allChats.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  print('✅ Всего загружено чатов: ${allChats.length}');
  return allChats;
});

/// Провайдер для создания нового чата
final createChatProvider = FutureProvider.family<ChatSession, String>((ref, agentId) async {
  final service = ref.read(chatHistoryServiceProvider);
  return service.createChat(agentId);
});