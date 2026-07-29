// lib/providers/agent_provider.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/agent.dart';
import '../services/agent_service.dart';
import '../services/service_factory.dart';

/// Провайдер для сервиса агентов
final agentServiceProvider = Provider<AgentService>((ref) {
  return ServiceFactory.getAgentService();
});

/// Провайдер для списка агентов (загружается асинхронно)
final agentsProvider = FutureProvider<List<Agent>>((ref) async {
  final service = ref.read(agentServiceProvider);
  return service.getAgents();
});

/// Провайдер для получения агента по ID
final agentByIdProvider = Provider.family<Agent?, String>((ref, id) {
  final agents = ref.watch(agentsProvider);
  // Если данные еще не загружены, возвращаем null
  if (agents is AsyncData<List<Agent>>) {
    try {
      return agents.value.firstWhere((agent) => agent.id == id);
    } catch (e) {
      return null;
    }
  }
  return null;
});
