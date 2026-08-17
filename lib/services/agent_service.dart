// lib/services/agent_service.dart

import 'dart:convert';
import '../models/agent.dart';
import '../core/network/http_client.dart';
import '../core/config/app_config.dart';

/// Сервис для работы с агентами (OpenAI-совместимый API)
class AgentService {
  // ============================================================
  // 1. ЗАВИСИМОСТИ
  // ============================================================
  
  /// HTTP клиент для отправки запросов
  final AppHttpClient _httpClient;
  
  /// Базовый URL (берем из конфига, но пока оставляем для совместимости)
  final String _baseUrl;
  
  /// Кэш агентов (чтобы не запрашивать каждый раз)
  List<Agent>? _cachedAgents;
  
  // ============================================================
  // 2. КОНСТРУКТОР
  // ============================================================
  
  /// Создает сервис с HTTP клиентом.
  /// 
  /// [baseUrl] - оставляем для обратной совместимости,
  /// но фактически используем AppConfig.baseUrl
  AgentService({
    String? baseUrl,
    AppHttpClient? httpClient,
  })  : _baseUrl = baseUrl ?? AppConfig.baseUrl,
        _httpClient = httpClient ?? AppHttpClient();
  
  // ============================================================
  // 3. ПОЛУЧЕНИЕ АГЕНТОВ
  // ============================================================
  
  /// Получить список агентов с бэкенда.
  /// 
  /// Использует GET /v1/models (OpenAI-совместимый формат).
  /// 
  /// Результат кэшируется, чтобы не делать повторные запросы.
  Future<List<Agent>> getAgents() async {
    // Если уже загружены — возвращаем кэш
    if (_cachedAgents != null) {
      print('📦 AgentService: используем кэш (${_cachedAgents!.length} агентов)');
      return _cachedAgents!;
    }
    
    try {
      print('📦 AgentService: запрашиваем список агентов...');
      
      // ---- 1. Отправляем GET-запрос через наш клиент ----
      final response = await _httpClient.get('/v1/models');
      
      // ---- 2. Проверяем статус ----
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        
        // Ожидаем формат: { "object": "list", "data": [...] }
        final List<dynamic> models = data['data'] as List<dynamic>? ?? [];
        
        // Фильтруем: исключаем "auto" (это не агент, а специальное значение)
        final agents = models
            .where((item) => item['id'] != 'auto')
            .map((json) => Agent.fromJson(json))
            .toList();
        
        // Сохраняем в кэш
        _cachedAgents = agents;
        
        print('✅ AgentService: загружено ${agents.length} агентов');
        return agents;
      } else {
        throw Exception('Ошибка загрузки агентов: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ AgentService: ошибка: $e');
      throw Exception('Не удалось загрузить агентов: $e');
    }
  }
  
  // ============================================================
  // 4. ПОЛУЧЕНИЕ АГЕНТА ПО ID
  // ============================================================
  
  /// Получить агента по ID из кэша.
  /// 
  /// Если агент не найден или кэш пуст — возвращает null.
  Agent? getAgentById(String id) {
    if (_cachedAgents == null) {
      print('⚠️ AgentService: кэш пуст, вызовите getAgents() сначала');
      return null;
    }
    
    try {
      return _cachedAgents!.firstWhere(
        (agent) => agent.id == id,
        orElse: () => throw Exception('Агент с ID $id не найден'),
      );
    } catch (e) {
      print('⚠️ AgentService: агент $id не найден');
      return null;
    }
  }
  
  // ============================================================
  // 5. ПРОВЕРКА СУЩЕСТВОВАНИЯ АГЕНТА
  // ============================================================
  
  /// Проверяет, существует ли агент с таким ID.
  bool hasAgent(String id) {
    if (_cachedAgents == null) return false;
    return _cachedAgents!.any((agent) => agent.id == id);
  }
  
  // ============================================================
  // 6. УПРАВЛЕНИЕ КЭШЕМ
  // ============================================================
  
  /// Сбрасывает кэш.
  /// 
  /// Используется при выходе из системы или принудительном обновлении.
  void clearCache() {
    _cachedAgents = null;
    print('🗑️ AgentService: кэш очищен');
  }
  
  /// Принудительно обновляет кэш (игнорирует существующий).
  Future<List<Agent>> refreshCache() async {
    print('🔄 AgentService: принудительное обновление кэша...');
    _cachedAgents = null;
    return await getAgents();
  }
}