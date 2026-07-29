// lib/services/agent_service.dart

import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/agent.dart';

class AgentService {
  final String _baseUrl;

  // Кэш агентов (чтобы не запрашивать каждый раз)
  List<Agent>? _cachedAgents;

  AgentService({required String baseUrl}) : _baseUrl = baseUrl;

  /// Получить список агентов с бэкенда
  Future<List<Agent>> getAgents() async {
    // Если уже загружены — возвращаем кэш
    if (_cachedAgents != null) {
      return _cachedAgents!;
    }

    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/agents'),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        final agents = data.map((json) => Agent.fromJson(json)).toList();
        _cachedAgents = agents; // Сохраняем в кэш
        return agents;
      } else {
        throw Exception('Ошибка загрузки агентов: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Не удалось загрузить агентов: $e');
    }
  }

  /// Получить агента по ID
  Agent? getAgentById(String id) {
    return _cachedAgents?.firstWhere(
      (agent) => agent.id == id,
      orElse: () => throw Exception('Агент с ID $id не найден'),
    );
  }
}
