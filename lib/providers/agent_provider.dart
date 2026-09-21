// lib/providers/agent_provider.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../domain/models/agent.dart';
import '../data/repositories/chat_repository.dart';
import '../data/datasources/remote/chat_api.dart';
import '../core/network/http_client.dart';
import '../data/datasources/remote/attachment_api.dart';
import '../data/repositories/attachment_repository.dart';

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

/// Провайдер для AttachmentApi
///
/// Работает с тем же httpClient, что и chatApi, — общий пул соединений.
final attachmentApiProvider = Provider<AttachmentApi>((ref) {
  final httpClient = ref.read(httpClientProvider);
  return AttachmentApi(httpClient: httpClient);
});

/// Провайдер для AttachmentRepository
///
/// Используется в ChatNotifier для загрузки вложений.
final attachmentRepositoryProvider = Provider<AttachmentRepository>((ref) {
  final api = ref.read(attachmentApiProvider);
  return AttachmentRepository(api: api);
});

/// Провайдер для списка агентов (НОВЫЙ, через Repository)
final agentsProvider = FutureProvider<List<Agent>>((ref) async {
  final repository = ref.read(chatRepositoryProvider);
  return repository.getAgents();
});

/// Провайдер для поиска агента по ID через `Map`.
///
/// **Почему `Map`, а не `family`:**
/// - один провайдер на всё приложение, а не отдельный на каждый `id`;
/// - поиск O(1) вместо `list.firstWhere(...)` — O(n);
/// - не нужен `try/catch` вокруг `firstWhere` (он бросает `StateError`);
/// - `null` при поиске означает ровно одно: «не найден или ещё загружается».
///
/// `valueOrNull` возвращает `null`, пока `agentsProvider` в состоянии
/// `AsyncLoading` или `AsyncError`. В этом случае `Map` пустой — UI
/// покажет fallback (`?`), как и раньше.
///
/// Пример использования:
/// ```dart
/// final agent = ref.watch(agentsByIdProvider)[chat.agentId];
/// ```
final agentsByIdProvider = Provider<Map<String, Agent>>((ref) {
  final agents = ref.watch(agentsProvider).valueOrNull ?? const [];
  return {for (final agent in agents) agent.id: agent};
});
