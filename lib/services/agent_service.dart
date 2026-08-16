// lib/services/agent_service.dart

import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/agent.dart';

/// Сервис для работы с агентами (OpenAI-совместимый API)
class AgentService {
  final String _baseUrl;

  // Кэш агентов (чтобы не запрашивать каждый раз)
  List<Agent>? _cachedAgents;

  AgentService({required String baseUrl}) : _baseUrl = baseUrl;

  // ============================================================
  // ПОЛУЧЕНИЕ АГЕНТОВ
  // ============================================================

  /// Получить список агентов с бэкенда
  /// GET /v1/models (OpenAI-совместимый формат)
  Future<List<Agent>> getAgents() async {
    // Если уже загружены — возвращаем кэш
    if (_cachedAgents != null) {
      return _cachedAgents!;
    }

    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/v1/models'),
        headers: {
          'Content-Type': 'application/json',
          'X-User-Id': '11111111-1111-1111-1111-111111111111',
        },
      );

      print('📦 AgentService: статус ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        // Ожидаем формат: { "object": "list", "data": [...] }
        final List<dynamic> models = data['data'] as List<dynamic>? ?? [];
        
        // Фильтруем: исключаем "auto" (это не агент)
        final agents = models
            .where((item) => item['id'] != 'auto')
            .map((json) => Agent.fromJson(json))
            .toList();
        
        _cachedAgents = agents;
        print('✅ Загружено агентов: ${agents.length}');
        return agents;
      } else {
        throw Exception('Ошибка загрузки агентов: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Не удалось загрузить агентов: $e');
    }
  }

  // ============================================================
  // ПОЛУЧЕНИЕ АГЕНТА ПО ID
  // ============================================================

  /// Получить агента по ID из кэша
  Agent? getAgentById(String id) {
    if (_cachedAgents == null) return null;
    try {
      return _cachedAgents!.firstWhere(
        (agent) => agent.id == id,
        orElse: () => throw Exception('Агент с ID $id не найден'),
      );
    } catch (e) {
      return null;
    }
  }

  // ============================================================
  // ПРОВЕРКА СУЩЕСТВОВАНИЯ АГЕНТА
  // ============================================================

  /// Проверяет, существует ли агент с таким ID
  bool hasAgent(String id) {
    if (_cachedAgents == null) return false;
    return _cachedAgents!.any((agent) => agent.id == id);
  }

  // ============================================================
  // СБРОС КЭША
  // ============================================================

  /// Сбрасывает кэш (например, при выходе из системы)
  void clearCache() {
    _cachedAgents = null;
  }
}