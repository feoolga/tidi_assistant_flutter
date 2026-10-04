// lib/widgets/rag_creation_progress.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/rag_creation_provider.dart';
import '../theme/app_theme.dart';

/// Виджет **прогресса** создания RAG-набора.
///
/// **Что показывает.** Читает `ragCreationProvider` и отображает
/// **текущую фазу** создания:
/// - `idle` — ничего (пустой `SizedBox`);
/// - `creatingRag` / `uploadingFiles` — спиннер + описание;
/// - `waitingReadiness` — `LinearProgressIndicator` + счётчики
///   документов («X из Y обработано»);
/// - `ready` — галочка + кнопка «Открыть чат»;
/// - `failed` — иконка ошибки + сообщение + кнопки действий.
///
/// **Роль в UI.** Используется в `CreateRagScreen` (D8.2)
/// **после** нажатия «Создать». Форма (имя, файлы) — **отдельно**,
/// потому что у неё свой жизненный цикл и свои заботы. Виджет
/// прогресса — **только** про **текущее состояние** создания.
///
/// **Что НЕ делает:**
/// - не управляет состоянием — это `RagCreationNotifier` (D6);
/// - не выбирает файлы — это форма (D8.2);
/// - не вызывает навигацию **напрямую** — через колбэки [onOpenChat],
///   [onCancel], [onRetry].
///
/// **Почему колбэки, а не прямая работа с провайдером.**
/// - Разделение ответственности: виджет **рисует**, экран **управляет**.
/// - Переиспользуемость: если виджет понадобится **в другом месте** —
///   колбэки уже готовы.
/// - Тестируемость: можно тестировать виджет **отдельно** с фейковыми
///   колбэками.
class RagCreationProgress extends ConsumerWidget {
  /// Колбэк «Открыть чат». Вызывается, когда пользователь нажимает
  /// кнопку в фазе `ready`.
  ///
  /// **Может быть `null`** — тогда кнопка **не** показывается.
  /// Это на случай, если виджет используется в **другом** контексте
  /// (например, в информационном режиме).
  final VoidCallback? onOpenChat;

  /// Колбэк «Отмена». Вызывается, когда пользователь хочет
  /// **прервать** создание (в фазах `creatingRag`/`uploadingFiles`/
  /// `waitingReadiness`) или **закрыть** ошибку (в `failed`).
  ///
  /// **Может быть `null`** — тогда кнопка **не** показывается.
  final VoidCallback? onCancel;

  /// Колбэк «Повторить». Вызывается, когда пользователь хочет
  /// **повторить** создание **после** ошибки.
  ///
  /// **Может быть `null`** — тогда кнопка **не** показывается.
  final VoidCallback? onRetry;

  const RagCreationProgress({
    super.key,
    this.onOpenChat,
    this.onCancel,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(ragCreationProvider);

    // `idle` — ничего не показываем.
    if (state.phase == RagCreationPhase.idle) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppTheme.primary.withValues(alpha: 0.2),
          width: 1,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(state),
          const SizedBox(height: 16),
          _buildBody(state),
          const SizedBox(height: 20),
          _buildActions(state),
        ],
      ),
    );
  }

  // ============================================================
  // ЗАГОЛОВОК — ИКОНКА + ТЕКСТ
  // ============================================================

  /// Верхняя часть — иконка + описание фазы.
  Widget _buildHeader(RagCreationState state) {
    return Row(
      children: [
        _buildStatusIcon(state),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            _phaseTitle(state),
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppTheme.textPrimary,
            ),
          ),
        ),
      ],
    );
  }

  /// Иконка статуса — разная для разных фаз.
  Widget _buildStatusIcon(RagCreationState state) {
    switch (state.phase) {
      case RagCreationPhase.creatingRag:
      case RagCreationPhase.uploadingFiles:
      case RagCreationPhase.waitingReadiness:
        return const SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(
            strokeWidth: 2.5,
            valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primary),
          ),
        );
      case RagCreationPhase.ready:
        return const Icon(
          Icons.check_circle,
          color: AppTheme.primary,
          size: 28,
        );
      case RagCreationPhase.failed:
        return const Icon(Icons.error_outline, color: Colors.red, size: 28);
      case RagCreationPhase.idle:
        // Не должно случиться (проверка выше), но для exhaustive switch.
        return const SizedBox.shrink();
    }
  }

  /// Текст заголовка — по фазе.
  String _phaseTitle(RagCreationState state) {
    switch (state.phase) {
      case RagCreationPhase.creatingRag:
        return 'Создаём набор…';
      case RagCreationPhase.uploadingFiles:
        final filesCount = state.files.length;
        return 'Загружаем файлы ($filesCount)…';
      case RagCreationPhase.waitingReadiness:
        return 'Обрабатываем документы…';
      case RagCreationPhase.ready:
        return 'Готово!';
      case RagCreationPhase.failed:
        return 'Не удалось создать';
      case RagCreationPhase.idle:
        return '';
    }
  }

  // ============================================================
  // ТЕЛО — ДЕТАЛИ ФАЗЫ
  // ============================================================

  /// Середина — детали (счётчики, прогресс-бар, сообщение об ошибке).
  Widget _buildBody(RagCreationState state) {
    switch (state.phase) {
      case RagCreationPhase.creatingRag:
      case RagCreationPhase.uploadingFiles:
        return _buildUploadingBody(state);
      case RagCreationPhase.waitingReadiness:
        return _buildWaitingBody(state);
      case RagCreationPhase.ready:
        return _buildReadyBody(state);
      case RagCreationPhase.failed:
        return _buildFailedBody(state);
      case RagCreationPhase.idle:
        return const SizedBox.shrink();
    }
  }

  /// Тело для фаз создания/загрузки — просто текстовое пояснение.
  Widget _buildUploadingBody(RagCreationState state) {
    final text = state.phase == RagCreationPhase.creatingRag
        ? 'Это может занять несколько секунд…'
        : 'Загрузка ${state.files.length} файл(ов) на сервер…';

    return Text(
      text,
      style: const TextStyle(fontSize: 14, color: AppTheme.textSecondary),
    );
  }

  /// Тело для фазы ожидания — прогресс-бар + счётчики документов.
  Widget _buildWaitingBody(RagCreationState state) {
    final ragSet = state.ragSet;
    if (ragSet == null) {
      return const Text(
        'Начинаем обработку…',
        style: TextStyle(fontSize: 14, color: AppTheme.textSecondary),
      );
    }

    final counts = ragSet.documentsCounts;
    final percent = counts.readyPercent / 100; // 0.0 … 1.0

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: percent,
            minHeight: 6,
            backgroundColor: AppTheme.primaryLight,
            valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.primary),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          _waitingLabel(counts.ready, counts.total, counts.failed),
          style: const TextStyle(fontSize: 14, color: AppTheme.textSecondary),
        ),
        if (counts.hasFailures) ...[
          const SizedBox(height: 6),
          Text(
            'Не удалось обработать: ${counts.failed}',
            style: const TextStyle(fontSize: 13, color: Colors.red),
          ),
        ],
      ],
    );
  }

  /// Текст под прогресс-баром: «Готово: X из Y».
  String _waitingLabel(int ready, int total, int failed) {
    if (total == 0) return 'Ожидаем начала обработки…';
    return 'Готово: $ready из $total';
  }

  /// Тело для фазы `ready` — пояснение, что можно начинать.
  Widget _buildReadyBody(RagCreationState state) {
    return const Text(
      'Набор проиндексирован. Можно задавать вопросы по документам.',
      style: TextStyle(fontSize: 14, color: AppTheme.textSecondary),
    );
  }

  /// Тело для фазы `failed` — сообщение об ошибке.
  Widget _buildFailedBody(RagCreationState state) {
    return Text(
      state.error ?? 'Произошла неизвестная ошибка.',
      style: const TextStyle(fontSize: 14, color: Colors.red),
    );
  }

  // ============================================================
  // КНОПКИ ДЕЙСТВИЙ — РАЗНЫЕ ДЛЯ РАЗНЫХ ФАЗ
  // ============================================================

  /// Кнопки действий — зависят от фазы.
  ///
  /// - `creatingRag` / `uploadingFiles` / `waitingReadiness` —
  ///   кнопка «Отмена», если передан [onCancel].
  /// - `ready` — кнопка «Открыть чат», если передан [onOpenChat].
  /// - `failed` — кнопки «Повторить» (если [onRetry]) и «Отмена»
  ///   (если [onCancel]).
  /// - `idle` — ничего.
  Widget _buildActions(RagCreationState state) {
    switch (state.phase) {
      case RagCreationPhase.creatingRag:
      case RagCreationPhase.uploadingFiles:
      case RagCreationPhase.waitingReadiness:
        return _buildCancelButton();
      case RagCreationPhase.ready:
        return _buildOpenChatButton();
      case RagCreationPhase.failed:
        return _buildRetryAndCancelButtons();
      case RagCreationPhase.idle:
        return const SizedBox.shrink();
    }
  }

  Widget _buildCancelButton() {
    if (onCancel == null) return const SizedBox.shrink();
    return _outlinedButton(
      label: 'Отмена',
      onPressed: onCancel!,
      icon: Icons.close,
    );
  }

  Widget _buildOpenChatButton() {
    if (onOpenChat == null) return const SizedBox.shrink();
    return _filledButton(
      label: 'Открыть чат',
      onPressed: onOpenChat!,
      icon: Icons.chat_bubble_outline,
    );
  }

  Widget _buildRetryAndCancelButtons() {
    final hasRetry = onRetry != null;
    final hasCancel = onCancel != null;

    if (!hasRetry && !hasCancel) return const SizedBox.shrink();

    if (hasRetry && hasCancel) {
      return Row(
        children: [
          Expanded(
            child: _outlinedButton(
              label: 'Отмена',
              onPressed: onCancel!,
              icon: Icons.close,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _filledButton(
              label: 'Повторить',
              onPressed: onRetry!,
              icon: Icons.refresh,
            ),
          ),
        ],
      );
    }

    if (hasRetry) {
      return _filledButton(
        label: 'Повторить',
        onPressed: onRetry!,
        icon: Icons.refresh,
      );
    }

    return _outlinedButton(
      label: 'Отмена',
      onPressed: onCancel!,
      icon: Icons.close,
    );
  }

  // ============================================================
  // ХЕЛПЕРЫ КНОПОК — ЕДИНЫЙ СТИЛЬ
  // ============================================================

  Widget _filledButton({
    required String label,
    required VoidCallback onPressed,
    required IconData icon,
  }) {
    return SizedBox(
      height: 44,
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 18),
        label: Text(label),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppTheme.primary,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          elevation: 0,
        ),
      ),
    );
  }

  Widget _outlinedButton({
    required String label,
    required VoidCallback onPressed,
    required IconData icon,
  }) {
    return SizedBox(
      height: 44,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 18),
        label: Text(label),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppTheme.textPrimary,
          side: BorderSide(
            color: AppTheme.primary.withValues(alpha: 0.4),
            width: 1,
          ),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
    );
  }
}
