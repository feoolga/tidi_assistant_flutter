// lib/providers/agent_provider.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../domain/models/agent.dart';
import '../data/repositories/chat_repository.dart';
import '../data/datasources/remote/chat_api.dart';
import '../core/network/http_client.dart';

// ============================================================
// 1. ПРОВАЙДЕРЫ ДЛЯ НОВОЙ АРХИТЕКТУРЫ (РЕКОМЕНДУЕМЫЕ)
// ============================================================

/// Провайдер для HTTP клиента
final httpClientProvider = Provider<AppHttpClient>((ref) {
  return AppHttpClient();
});

/// Провайдер для ChatApi
final chatApiProvider = Provider<ChatApi>((ref) {
  final httpClient = ref.read(httpClientProvider);
  return ChatApi(httpClient: httpClient);
});

/// Провайдер для ChatRepository
final chatRepositoryProvider = Provider<ChatRepository>((ref) {
  final api = ref.read(chatApiProvider);
  return ChatRepository(api: api);
});

/// Провайдер для списка агентов (НОВЫЙ, через Repository)
final agentsProvider = FutureProvider<List<Agent>>((ref) async {
  final repository = ref.read(chatRepositoryProvider);
  return repository.getAgents();
});

/// Провайдер для получения агента по ID (НОВЫЙ)
final agentByIdProvider = Provider.family<Agent?, String>((ref, id) {
  final agents = ref.watch(agentsProvider);
  if (agents is AsyncData<List<Agent>>) {
    try {
      return agents.value.firstWhere((agent) => agent.id == id);
    } catch (e) {
      return null;
    }
  }
  return null;
});
