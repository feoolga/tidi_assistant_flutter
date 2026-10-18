// lib/widgets/message_markdown.dart

import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import '../theme/app_theme.dart';

/// Рендер текста ответа AI **в формате Markdown**.
///
/// **Что делает:**
/// 1. **Экранирует** `[N]` → `\[N\]` — чтобы маркдаун не пытался
///    превратить их в **ссылки** (у нас `[1]`, `[2]` — это источники,
///    а не ссылки). Тапабельность `[N]` — отдельная фича (в беклоге).
/// 2. **Рендерит** markdown через `MarkdownBody` (**без** своего
///    скролла — встраивается в существующий `ListView`).
/// 3. **Стилизует** элементы под **Тиффани** (`AppTheme.primary`):
///    ссылки, inline-код, блоки кода.
///
/// **Что НЕ делает:**
/// - **не** управляет **скроллом** (`MarkdownBody` **без** скролла);
/// - **не** обрабатывает **тап** **по** `[N]` (**потом**, **в** беклоге);
/// - **не** рендерит **картинки** из markdown (**AI** **их** **не**
///   присылает; если понадобится — добавим `imageBuilder`).
///
/// **Где** **используется:** `MessageBubble` — **только** **для**
/// **AI**-сообщений (**!isFromUser**) **после** **завершения** **стрима**
/// (**isStreaming == false**). **Во** **время** **стрима** —
/// **простой** `Text` (**см.** `MessageBubble`).
class MessageMarkdown extends StatelessWidget {
  /// Markdown-текст ответа AI (**как** **его** **прислал** **сервер**).
  final String text;

  const MessageMarkdown({super.key, required this.text});

  // ============================================================
  // ЭКРАНИРОВАНИЕ [N]
  // ============================================================

  /// Регулярка **для** **голых** `[N]` (**не** **трогает** `[1](url)`
  /// **и** `[текст]`).
  ///
  /// **Разбор:**
  /// - `\[` — **литеральный** `[`;
  /// - `(\d+)` — **одна** **или** **больше** **цифр** (**группа** 1);
  /// - `\]` — **литеральный** `]`;
  /// - `(?!\()` — **negative** **lookahead**: **не** **следует** `(`.
  ///
  /// **Что** **матчит:** `[1]`, `[42]`, `[123]`.
  /// **Что** **НЕ** **матчит:** `[1](url)`, `[текст]`, `[[1]]`.
  ///
  /// **`static final`** — **создаётся** **один** **раз** **на** **весь**
  /// **класс** (**RegExp** **нельзя** `const`).
  static final RegExp _sourceLinkPattern = RegExp(r'\[(\d+)\](?!\()');

  /// Заменить **голые** `[N]` **на** **экранированные** `\[N\]`.
  ///
  /// **Пример:**
  /// - `"Ответ [1], [2] и [3](url)."` →
  ///   `"Ответ \[1\], \[2\] и [3](url)."`
  ///
  /// **Почему** `\$1` (**с** **обратным** **слэшем**): **в** **regex**
  /// `$1` — **подстановка** **группы** 1. **Чтобы** **получить**
  /// **буквальный** `\[`**N**`\]` — **экранируем** **слэшем**:
  /// `r'\[$1\]'` → **`\[`** + **значение** **группы** + **`\]`**.
  ///
  /// **Dart:** **raw** **строка** `r'...'` — **чтобы** **не** **было**
  /// **двойного** **экранирования** (`\\[` **vs** `\[`).
  static String _escapeSourceLinks(String text) {
    return text.replaceAllMapped(
      _sourceLinkPattern,
      (match) => '\\[${match.group(1)}\\]',
    );
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    // Экранируем `[N]` перед рендером.
    final safeText = _escapeSourceLinks(text);

    return MarkdownBody(
      data: safeText,
      // **`selectable: false`** — **не** **даём** **выделять** **текст**
      // **долгим** **тапом**. Пока **не** **надо** (**пользователь**
      // **может** **захотеть** **копировать** — **тогда** **включим**).
      // **`MarkdownBody`** **не** **скроллится** — **встроится** **в**
      // **`ListView`** **`MessageBubble`**.
      styleSheet: _buildStyleSheet(context),
    );
  }

  // ============================================================
  // СТИЛИ
  // ============================================================

  /// Стили **маркдауна** **под** **Тиффани**.
  ///
  /// **Берём** **базовую** **тему** (**`MarkdownStyleSheet.fromTheme`**) —
  /// **чтобы** **размеры** **и** **шрифты** **были** **консистентны**
  /// **с** **остальным** **приложением**. **Переопределяем** **только**
  /// **цвета** **и** **фоны** **под** **Тиффани**:
  /// - **ссылки** — **`AppTheme.primary`**;
  /// - **inline-код** — **фон** **`AppTheme.primaryLight`**;
  /// - **блок** **кода** — **фон** **`AppTheme.primaryLight`**,
  ///   **padding**, **скругление**.
  ///
  /// **Что** **НЕ** **переопределяем:**
  /// - **`h1`/`h2`/`h3`** — **пусть** **будут** **по** **теме**
  ///   (**Material** **выглядит** **нормально**);
  /// - **`blockquote`** — **по** **теме**.
  ///
  /// **Если** **на** **реальном** **кейсе** **что-то** **выглядит** **не**
  /// **так** — **поправим** (**добавим** **поля**).
  MarkdownStyleSheet _buildStyleSheet(BuildContext context) {
    final base = MarkdownStyleSheet.fromTheme(Theme.of(context));

    return base.copyWith(
      // Ссылки — Тиффани, с подчёркиванием.
      a: base.a?.copyWith(
        color: AppTheme.primary,
        decoration: TextDecoration.underline,
        decorationColor: AppTheme.primary,
      ),

      // Inline-код — фон primaryLight, моноширинный шрифт.
      code: base.code?.copyWith(
        backgroundColor: AppTheme.primaryLight,
        color: AppTheme.textPrimary,
        fontFamily: 'monospace',
      ),

      // Блок кода — фон primaryLight, padding, скругление.
      codeblockDecoration: BoxDecoration(
        color: AppTheme.primaryLight,
        borderRadius: BorderRadius.circular(8),
      ),
      codeblockPadding: const EdgeInsets.all(12),

      // Основной текст — как в обычном MessageBubble
      // (16, height 1.4) — чтобы переход стрим→markdown не «прыгал».
      p: const TextStyle(
        color: AppTheme.textPrimary,
        fontSize: 16,
        height: 1.4,
      ),
    );
  }
}
