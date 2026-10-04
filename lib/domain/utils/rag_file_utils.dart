// lib/domain/utils/rag_file_utils.dart

import '../../core/config/app_config.dart';

/// Утилиты для работы с **файлами RAG-набора**.
///
/// Отдельно от `attachmentMimeTypeFromFilename` (для `document_chat`),
/// потому что **разные** сценарии:
/// - `document_chat` — только PDF/JPG/PNG (MinerU, OCR);
/// - RAG — PDF, DOCX, DOC, TXT, MD, JPG, PNG (docling, текстовые
///   форматы).
///
/// **Что **не** делаем здесь:**
/// - не ходим в файловую систему (это UseCase);
/// - не валидируем размер (это UseCase);
/// - не работаем с `Attachment` — только **RAG**-специфика.

/// Определить MIME-тип **RAG-файла** по имени.
///
/// Смотрим **только** на **расширение** — имя файла либо пришло от
/// сервера (уже сохранённое), либо выбрано пользователем (мы не
/// можем надёжно определить MIME без содержимого).
///
/// **Поддерживаемые форматы** (см. `AppConfig.ragAllowedFileExtensions`):
/// - `pdf` → `application/pdf`
/// - `docx` → `application/vnd.openxmlformats-officedocument.wordprocessingml.document`
/// - `doc` → `application/msword`
/// - `txt` → `text/plain`
/// - `md` → `text/markdown`
/// - `jpg` / `jpeg` → `image/jpeg`
/// - `png` → `image/png`
///
/// **Неизвестное расширение** → `application/octet-stream`. Так
/// валидация по `AppConfig.ragAllowedMimeTypes` **отсеет** файл
/// **до** отправки.
///
/// Пример:
/// ```dart
/// ragMimeTypeFromFilename('договор.pdf')    // → 'application/pdf'
/// ragMimeTypeFromFilename('приказ.docx')    // → 'application/vnd...wordprocessingml.document'
/// ragMimeTypeFromFilename('note.txt')        // → 'text/plain'
/// ragMimeTypeFromFilename('file.xyz')        // → 'application/octet-stream'
/// ```
String ragMimeTypeFromFilename(String filename) {
  final lower = filename.toLowerCase();

  // PDF
  if (lower.endsWith('.pdf')) return 'application/pdf';

  // Word
  if (lower.endsWith('.docx')) {
    return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
  }
  if (lower.endsWith('.doc')) return 'application/msword';

  // Текстовые
  if (lower.endsWith('.txt')) return 'text/plain';
  if (lower.endsWith('.md')) return 'text/markdown';

  // Картинки
  if (lower.endsWith('.jpg')) return 'image/jpeg';
  if (lower.endsWith('.jpeg')) return 'image/jpeg';
  if (lower.endsWith('.png')) return 'image/png';

  // Неизвестное — отсеется валидацией.
  return 'application/octet-stream';
}

/// Разрешён ли **RAG-файл** с таким MIME?
///
/// Проверяет **членство** в `AppConfig.ragAllowedMimeTypes`.
/// `octet-stream` (неизвестный MIME) **не** входит — вернёт `false`.
///
/// **Почему отдельная функция.** Логика «MIME разрешён» —
/// **RAG-специфичная**. Если завтра **расширим** список (например,
/// добавим `.csv`) — правка **в одном** месте: `AppConfig`.
bool isRagAllowedMimeType(String mimeType) {
  return AppConfig.ragAllowedMimeTypes.contains(mimeType);
}
