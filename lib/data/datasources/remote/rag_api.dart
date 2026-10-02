// lib/data/datasources/remote/rag_api.dart

import 'dart:io';

import 'package:http/http.dart' as http;

import '../../../core/config/app_config.dart';
import '../../../core/network/http_client.dart';

/// API-слой для работы с RAG-наборами.
///
/// **Роль.** Тонкая обёртка над [AppHttpClient], которая знает
/// конкретные **URL-ы** и **параметры** эндпойнтов RAG. Держит URL-ы
/// в одном месте, чтобы [RagRepository] работал с методами, а не
/// со строками путей.
///
/// **Что НЕ делает:**
/// - не парсит JSON (это [RagRepository]);
/// - не разбирает статусы `4xx`/`5xx` (это [RagRepository]);
/// - не знает про домен (`RagSet`, `RagDocument`) — только
///   возвращает **сырые** `http.Response`.
///
/// **URL-префикс `/agents/agentic_rag/...`** — обязателен: мы ходим
/// **через мастер**, а не напрямую к агенту. `agentic_rag` — это
/// `agent_id` в реестре мастера (см. ответ бэкендера, вопрос 1).
/// **Не** `rag/<uuid>` — это значение поля `model` в теле запроса
/// `POST /v1/responses`, **другая** сущность.
class RagApi {
  /// Общий HTTP-клиент. Тот же, что у `ChatApi`/`AttachmentApi` —
  /// единый пул TCP-соединений.
  final AppHttpClient _httpClient;

  /// Префикс пути для всех RAG-эндпойнтов.
  ///
  /// Собирается из [AppConfig.ragAgentId] — если бэкендер
  /// переименует агента в реестре, поменяем **одно** место
  /// в `AppConfig`.
  static const String _prefix = '/agents/${AppConfig.ragAgentId}/v1/platform';

  RagApi({AppHttpClient? httpClient})
    : _httpClient = httpClient ?? AppHttpClient();

  // ============================================================
  // 1. НАБОРЫ (RAG SETS)
  // ============================================================

  /// POST /rags — создать новый RAG-набор.
  ///
  /// **Успех:** `201` с объектом набора.
  /// **Ошибки:** `409` — лимит наборов, `400` — невалидное тело.
  ///
  /// **Разбор статусов — задача [RagRepository].**
  Future<http.Response> createRag({
    required String name,
    String? description,
    Map<String, dynamic>? config,
  }) {
    final body = <String, dynamic>{
      'name': name,
      if (description != null) 'description': description,
      if (config != null) 'config': config,
    };

    return _httpClient.post('$_prefix/rags', body: body);
  }

  /// GET /rags — список своих наборов.
  ///
  /// **Успех:** `200` с `{"data": [...]}` (не массив напрямую —
  /// см. формат ответа в README ingestion-сервиса).
  Future<http.Response> listRags() {
    return _httpClient.get('$_prefix/rags');
  }

  /// GET /rags/{id} — один набор по id.
  ///
  /// **Успех:** `200` с объектом набора.
  /// **Ошибки:** `404` — не найден или чужой.
  Future<http.Response> getRag({required String ragId}) {
    return _httpClient.get('$_prefix/rags/$ragId');
  }

  /// PATCH /rags/{id} — частичное обновление набора.
  ///
  /// Бэкендер использует `exclude_unset`: не переданные поля
  /// **сохраняют** текущие значения.
  ///
  /// **Успех:** `200` с обновлённым объектом набора.
  /// **Ошибки:** `404`, `400`.
  Future<http.Response> updateRag({
    required String ragId,
    String? name,
    String? description,
    Map<String, dynamic>? config,
  }) {
    final body = <String, dynamic>{
      if (name != null) 'name': name,
      if (description != null) 'description': description,
      if (config != null) 'config': config,
    };

    return _httpClient.patch('$_prefix/rags/$ragId', body: body);
  }

  /// DELETE /rags/{id} — удалить набор (soft-delete + фоновая уборка).
  ///
  /// **Успех:** `204 No Content` (без тела) — **предполагаем**;
  /// бэкендер не уточнил. Если `200` — тоже ок.
  /// **Ошибки:** `404`.
  ///
  /// **Что происходит с чатами.** Они **не удаляются**
  /// автоматически, остаются «висячими» (по ответу бэкендера).
  /// UI показывает плашку «набор удалён».
  Future<http.Response> deleteRag({required String ragId}) {
    return _httpClient.delete('$_prefix/rags/$ragId');
  }

  // ============================================================
  // 2. ИКОНКА НАБОРА
  // ============================================================

  /// PUT /rags/{id}/icon — загрузить иконку (multipart).
  ///
  /// **Поле формы — `file`** (по умолчанию). Если бэкендер ждёт
  /// другое (например, `icon`) — передадим явно. Пока — дефолт.
  ///
  /// **Не бросает на `>= 400`** (multipart-запрос): `413` — файл
  /// слишком большой, `415` — формат не поддерживается. Разбор
  /// статусов — [RagRepository].
  Future<http.Response> uploadIcon({
    required String ragId,
    required File file,
  }) {
    return _httpClient.multipart(
      '$_prefix/rags/$ragId/icon',
      method: 'PUT',
      files: [file],
      timeout: AppConfig.timeout,
    );
  }

  /// GET /rags/{id}/icon — получить иконку (байты PNG).
  ///
  /// **Успех:** `200` с телом-картинкой.
  /// **Ошибки:** `404` — иконки нет.
  ///
  /// **Формат ответа:** скорее всего `image/png`
  /// (бэкендер переупаковывает в PNG фиксированного размера).
  /// Мы **не** парсим — возвращаем сырой `http.Response`.
  Future<http.Response> getIcon({required String ragId}) {
    return _httpClient.get('$_prefix/rags/$ragId/icon');
  }

  // ============================================================
  // 3. ДОКУМЕНТЫ
  // ============================================================

  /// POST /rags/{id}/documents — загрузить **пачку** файлов.
  ///
  /// **Успех:** `202` с `{"documents": [...]}` — список принятых
  /// и дубликатов.
  /// **Ошибки:** `413` — файл слишком большой, `409` — лимит
  /// наборов (не документов), `400`.
  ///
  /// **Важно про частичную загрузку.** Запрос **не атомарный**:
  /// сервер пишет файлы по очереди, каждый со своим коммитом.
  /// Ошибка на 5-м оставляет **первые 4 принятыми**, а **ответа
  /// фронт не получает**. После любой ошибки — **перечитать**
  /// `GET .../documents`.
  ///
  /// **Поле формы — `files`** (согласно ответу бэкендера).
  ///
  /// **Таймаут** — [AppConfig.ragUploadTimeout] (15 мин) —
  /// пачка из N файлов может быть долгой.
  Future<http.Response> uploadDocuments({
    required String ragId,
    required List<File> files,
  }) {
    return _httpClient.multipart(
      '$_prefix/rags/$ragId/documents',
      method: 'POST',
      files: files,
      fileField: 'files',
      timeout: AppConfig.ragUploadTimeout,
    );
  }

  /// GET /rags/{id}/documents — список документов набора.
  ///
  /// **Успех:** `200` с массивом документов (или с обёрткой `data`).
  /// **Ошибки:** `404` — набор не найден.
  Future<http.Response> listDocuments({required String ragId}) {
    return _httpClient.get('$_prefix/rags/$ragId/documents');
  }

  /// DELETE /rags/{id}/documents/{doc_id} — удалить документ.
  ///
  /// **Успех:** `204 No Content` (предполагаем).
  /// **Ошибки:** `404`.
  Future<http.Response> deleteDocument({
    required String ragId,
    required String documentId,
  }) {
    return _httpClient.delete('$_prefix/rags/$ragId/documents/$documentId');
  }
}
