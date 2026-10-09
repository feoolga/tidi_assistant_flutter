// lib/widgets/rag_creation_progress.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/models/rag_document.dart';
import '../providers/rag_creation_provider.dart';
import '../theme/app_theme.dart';

/// Виджет **прогресса** создания RAG-набора.
///
/// **Фазы:**
/// - `idle` — ничего;
/// - `creatingRag` / `uploadingFiles` — спиннер + описание;
/// - `waitingReadiness` — прогресс-бар + счётчики;
/// - `ready` — галочка + кнопка «Открыть чат»;
/// - `failed` **без** `ragId` — ошибка + «Отмена» / «Повторить»;
/// - `failed` **с** `hasPartialResult` — список файлов
///   (принятые / не загруженные) + «Открыть чат» / «Удалить набор».
class RagCreationProgress extends ConsumerWidget {
  final VoidCallback? onOpenChat;
  final VoidCallback? onCancel;
  final VoidCallback? onRetry;

  /// Колбэк «Удалить набор» — вызывается после подтверждения
  /// в диалоге. Виджет сам показывает диалог, колбэк — уже
  /// **финальное** действие.
  final VoidCallback? onDeleteSet;

  const RagCreationProgress({
    super.key,
    this.onOpenChat,
    this.onCancel,
    this.onRetry,
    this.onDeleteSet,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(ragCreationProvider);

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
          _buildActions(context, state),
        ],
      ),
    );
  }

  // ============================================================
  // ЗАГОЛОВОК
  // ============================================================

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

  Widget _buildStatusIcon(RagCreationState state) {
    // Частичная загрузка — жёлтая иконка предупреждения.
    if (state.hasPartialResult) {
      return const Icon(
        Icons.warning_amber_rounded,
        color: Colors.orange,
        size: 28,
      );
    }

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
        return const SizedBox.shrink();
    }
  }

  String _phaseTitle(RagCreationState state) {
    if (state.hasPartialResult) {
      return 'Набор создан частично';
    }

    switch (state.phase) {
      case RagCreationPhase.creatingRag:
        return 'Создаём набор…';
      case RagCreationPhase.uploadingFiles:
        return 'Загружаем файлы (${state.files.length})…';
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
  // ТЕЛО
  // ============================================================

  Widget _buildBody(RagCreationState state) {
    if (state.hasPartialResult) {
      return _buildPartialBody(state);
    }

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

  Widget _buildUploadingBody(RagCreationState state) {
    final text = state.phase == RagCreationPhase.creatingRag
        ? 'Это может занять несколько секунд…'
        : 'Загрузка ${state.files.length} файл(ов) на сервер…';

    return Text(
      text,
      style: const TextStyle(fontSize: 14, color: AppTheme.textSecondary),
    );
  }

  Widget _buildWaitingBody(RagCreationState state) {
    final ragSet = state.ragSet;
    if (ragSet == null) {
      return const Text(
        'Начинаем обработку…',
        style: TextStyle(fontSize: 14, color: AppTheme.textSecondary),
      );
    }

    final counts = ragSet.documentsCounts;
    final percent = counts.readyPercent / 100;

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

  String _waitingLabel(int ready, int total, int failed) {
    if (total == 0) return 'Ожидаем начала обработки…';
    return 'Готово: $ready из $total';
  }

  Widget _buildReadyBody(RagCreationState state) {
    return const Text(
      'Набор проиндексирован. Можно задавать вопросы по документам.',
      style: TextStyle(fontSize: 14, color: AppTheme.textSecondary),
    );
  }

  /// Тело для `failed` **без** `ragId` — набора нет.
  Widget _buildFailedBody(RagCreationState state) {
    return Text(
      state.error ?? 'Произошла неизвестная ошибка.',
      style: const TextStyle(fontSize: 14, color: Colors.red),
    );
  }

  /// Тело для `failed` **с** `hasPartialResult` — частичная загрузка.
  ///
  /// Показываем:
  /// 1. Счётчик «Загружено N из M».
  /// 2. Список: принятые (✅) и не загруженные (❌).
  /// 3. Причину ошибки upload (из `uploadError`).
  Widget _buildPartialBody(RagCreationState state) {
    final total = state.files.length;
    final accepted = state.uploadedDocuments.length;
    final notUploaded = _computeNotUploadedFilenames(state);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Загружено $accepted из $total файл(ов).',
          style: const TextStyle(
            fontSize: 14,
            color: AppTheme.textPrimary,
            fontWeight: FontWeight.w500,
          ),
        ),
        if (state.uploadError != null && state.uploadError!.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            state.uploadError!,
            style: const TextStyle(fontSize: 13, color: Colors.red),
          ),
        ],
        const SizedBox(height: 12),
        // Принятые файлы — зелёная галочка.
        for (final doc in state.uploadedDocuments)
          _buildFileRow(
            icon: Icons.check_circle_outline,
            iconColor: AppTheme.primary,
            filename: doc.filename,
          ),
        // Не загруженные — красный крестик.
        for (final filename in notUploaded)
          _buildFileRow(
            icon: Icons.cancel_outlined,
            iconColor: Colors.red,
            filename: filename,
          ),
      ],
    );
  }

  /// Один рядок списка: иконка + имя файла.
  Widget _buildFileRow({
    required IconData icon,
    required Color iconColor,
    required String filename,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: iconColor),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              filename,
              style: const TextStyle(
                fontSize: 13,
                color: AppTheme.textPrimary,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Вычислить имена файлов, которые **не** принял сервер.
  ///
  /// Берём `state.files` (что выбрал пользователь) и **вычитаем**
  /// те, что есть в `state.uploadedDocuments` (что принял сервер).
  /// Сравнение — по имени файла (`basename`).
  ///
  /// **Про санитизацию имён.** Бекендер может «сплющивать» имена
  /// (`../../etc/passwd` → `passwd`). Для простых имён сравнение
  /// точно. Для сложных — может не совпасть. Пока оставляем
  /// простое сравнение — этого достаточно для MVP.
  List<String> _computeNotUploadedFilenames(RagCreationState state) {
    final uploadedNames = state.uploadedDocuments
        .map((RagDocument d) => d.filename)
        .toSet();

    return state.files
        .map((f) => f.uri.pathSegments.last)
        .where((name) => !uploadedNames.contains(name))
        .toList();
  }

  // ============================================================
  // КНОПКИ
  // ============================================================

  Widget _buildActions(BuildContext context, RagCreationState state) {
    // Частичная загрузка — свои кнопки.
    if (state.hasPartialResult) {
      return _buildPartialActions(context);
    }

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

  /// Кнопки при частичной загрузке:
  /// «Удалить набор» (outlined, красный) + «Открыть чат» (filled).
  ///
  /// «Удалить набор» — с **подтверждением** через `AlertDialog`.
  Widget _buildPartialActions(BuildContext context) {
    final hasDelete = onDeleteSet != null;
    final hasOpen = onOpenChat != null;

    if (!hasDelete && !hasOpen) return const SizedBox.shrink();

    final deleteButton = hasDelete
        ? _outlinedButton(
            label: 'Удалить набор',
            onPressed: () => _confirmDelete(context),
            icon: Icons.delete_outline,
            foregroundColor: Colors.red,
          )
        : null;

    final openButton = hasOpen
        ? _filledButton(
            label: 'Открыть чат',
            onPressed: onOpenChat!,
            icon: Icons.chat_bubble_outline,
          )
        : null;

    if (deleteButton != null && openButton != null) {
      return Row(
        children: [
          Expanded(child: deleteButton),
          const SizedBox(width: 12),
          Expanded(child: openButton),
        ],
      );
    }

    return deleteButton ?? openButton ?? const SizedBox.shrink();
  }

  /// Диалог подтверждения удаления набора. Необратимо.
  Future<void> _confirmDelete(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Удалить набор?'),
        content: const Text(
          'Набор и все загруженные файлы будут удалены. '
          'Это действие нельзя отменить.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      onDeleteSet?.call();
    }
  }

  // ============================================================
  // ХЕЛПЕРЫ КНОПОК
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
    Color? foregroundColor,
  }) {
    return SizedBox(
      height: 44,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 18),
        label: Text(label),
        style: OutlinedButton.styleFrom(
          foregroundColor: foregroundColor ?? AppTheme.textPrimary,
          side: BorderSide(
            color: (foregroundColor ?? AppTheme.primary).withValues(alpha: 0.4),
            width: 1,
          ),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
    );
  }
}
