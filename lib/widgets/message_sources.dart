// lib/widgets/message_sources.dart

import 'package:flutter/material.dart';

import '../domain/models/message_source.dart';
import '../theme/app_theme.dart';

/// Сворачиваемый блок «Источники (N)» под ответом AI.
///
/// **Что показывает.** Список источников, на которые опирался AI:
/// - для `agentic_rag` — с номерами `[N]` (порядок в тексте ответа)
///   и именами файлов;
/// - для `document_chat` — просто имена файлов (без `order`).
///
/// **Зачем сворачивание.** Sources могут быть длинными (10–20 файлов
/// на сложный ответ). Разворачивать их всегда — визуальный шум.
/// По умолчанию свёрнут; пользователь тапает, если хочет увидеть.
///
/// **Состояние — локальное.** Отдельный `StatefulWidget` — потому что
/// «свёрнуто/развёрнуто» никому, кроме этого виджета, не нужно.
/// Хранить в `provider` — оверкилл.
///
/// **Не показываем пустой список.** Если `sources` пустой или `null` —
/// родитель (MessageBubble) вообще не должен этот виджет вызывать.
class MessageSources extends StatefulWidget {
  /// Список источников. Не пустой (родитель гарантирует).
  final List<MessageSource> sources;

  const MessageSources({super.key, required this.sources});

  @override
  State<MessageSources> createState() => _MessageSourcesState();
}

class _MessageSourcesState extends State<MessageSources> {
  bool _isExpanded = false;

  void _toggle() {
    setState(() => _isExpanded = !_isExpanded);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.only(top: 8),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: AppTheme.primary.withValues(alpha: 0.15),
            width: 1,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [_buildHeader(), if (_isExpanded) _buildList()],
      ),
    );
  }

  /// Заголовок — тап открывает/закрывает список.
  Widget _buildHeader() {
    return InkWell(
      onTap: _toggle,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.menu_book_outlined, size: 16, color: AppTheme.primary),
            const SizedBox(width: 6),
            Text(
              'Источники (${widget.sources.length})',
              style: const TextStyle(
                fontSize: 13,
                color: AppTheme.primary,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              _isExpanded ? Icons.expand_less : Icons.expand_more,
              size: 18,
              color: AppTheme.primary,
            ),
          ],
        ),
      ),
    );
  }

  /// Развёрнутый список источников.
  Widget _buildList() {
    return Padding(
      padding: const EdgeInsets.only(top: 6, left: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final source in widget.sources) _buildSourceItem(source),
        ],
      ),
    );
  }

  /// Одна строка источника.
  ///
  /// Если у source есть `order` (agentic_rag) — показываем `[N]` перед
  /// именем файла. Иначе (document_chat) — нейтральный маркер `•`.
  Widget _buildSourceItem(MessageSource source) {
    final prefix = source.order != null ? '[${source.order}]' : '•';

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 32,
            child: Text(
              prefix,
              style: const TextStyle(
                fontSize: 12,
                color: AppTheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              source.filename,
              style: const TextStyle(
                fontSize: 13,
                color: AppTheme.textSecondary,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
