// lib/domain/models/message_source.dart

/// Источник ответа AI — фрагмент документа, на который опирался ответ.
///
/// **Форматы от разных агентов.**
/// - `document_chat` шлёт sources прямо в `GET .../messages` — массив
///   **строк** (`["накладная.pdf", "договор.pdf (частично)"]`).
///   Маппер превращает строку в `MessageSource(filename: s)` —
///   остальные поля `null`.
/// - `agentic_rag` шлёт объекты через отдельную ручку
///   `GET .../chat/completions/{id}/sources`:
///   `{"order": 1, "chunk_id": "...", "document_id": "...",
///     "chunk_index": 0, "filename": "..."}`.
///   Здесь заполнены **все** поля.
///
/// **Про `order`.** Номер `[N]`, под которым фрагмент упоминается в
/// тексте ответа (`[1]`, `[2]`, ...). UI позже сможет подсветить
/// ссылки в тексте и связать их с sources. У `document_chat` — `null`.
///
/// **Про `chunkId` / `chunkIndex`.** Идентификаторы конкретного чанка
/// в индексе. Один документ обычно даёт **несколько** chunks — с
/// разными `chunkIndex`, но одним `documentId`. Пока UI не использует,
/// но пригодится для «показать фрагмент».
class MessageSource {
  /// Номер `[N]` в тексте ответа. `null` — если не пришёл.
  final int? order;

  /// ID чанка в индексе OpenSearch. `null` — если не пришёл.
  final String? chunkId;

  /// ID документа в RAG-наборе. `null` — если не пришёл.
  final String? documentId;

  /// Порядковый номер чанка внутри документа. `null` — если не пришёл.
  final int? chunkIndex;

  /// Имя файла — единственное поле, которое есть у обоих агентов.
  final String filename;

  const MessageSource({
    this.order,
    this.chunkId,
    this.documentId,
    this.chunkIndex,
    required this.filename,
  });

  /// Удобный конструктор для `document_chat` — только имя файла.
  factory MessageSource.fromFilename(String filename) {
    return MessageSource(filename: filename);
  }

  @override
  String toString() {
    return 'MessageSource(order: $order, filename: "$filename", '
        'documentId: $documentId, chunkIndex: $chunkIndex)';
  }
}
