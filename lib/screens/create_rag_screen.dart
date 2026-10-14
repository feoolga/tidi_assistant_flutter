// lib/screens/create_rag_screen.dart

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config/app_config.dart';
import '../core/errors/error_handler.dart';
import '../core/logger/app_logger.dart';
import '../providers/rag_creation_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/app_snack_bar.dart';
import '../widgets/attachment_picker_helper.dart';
import '../widgets/rag_creation_progress.dart';

/// Экран создания RAG-набора.
///
/// **Роль.** **Полноэкранный** (не bottom sheet) — потому что это
/// **multi-step** flow: ввод → выбор файлов → ожидание индексации →
/// переход в чат. См. D8.1 — обсуждение форматов.
///
/// **Два состояния экрана:**
/// 1. **Форма** (`phase == idle`) — имя, описание, файлы, кнопка «Создать».
/// 2. **Прогресс** (после `start`) — встроенный `RagCreationProgress`
///    с фазами создания/загрузки/ожидания.
///
/// **Переключение** — по `phase` из `ragCreationProvider`.
///
/// **Обработка успеха.** Когда чат создан (`createdChatId != null`),
/// экран **закрывается** (`Navigator.pop`) — под ним `ChatScreen`,
/// который **сам** обновится, потому что читает сессию из
/// `sessionProvider`. Никаких `push` — **просто** возвращаемся.
///
/// **Что НЕ делает:**
/// - не создаёт чат — это `RagCreationNotifier.createChat()` (D6);
/// - не управляет polling — это `WatchRagReadinessUseCase` (D4.2);
/// - не открывается сам — это `ChatScreen` (D8.3).
class CreateRagScreen extends ConsumerStatefulWidget {
  const CreateRagScreen({super.key});

  @override
  ConsumerState<CreateRagScreen> createState() => _CreateRagScreenState();
}

class _CreateRagScreenState extends ConsumerState<CreateRagScreen> {
  // ============================================================
  // СОСТОЯНИЕ ФОРМЫ
  // ============================================================
  //
  // **Почему в `State`, а не в провайдере.**
  // Это **черновик формы**: имя, описание, выбранные файлы.
  // Он **не нужен** глобально — только на этом экране.
  // При закрытии экрана — **уничтожается**. Save-and-resume
  // **не** в MVP (обсудили).

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();

  /// Выбранные файлы — **до** создания набора.
  final List<File> _selectedFiles = [];

  /// Идёт ли сейчас открытие системного диалога выбора файлов.
  /// Защита от двойного тапа по кнопке «Добавить».
  bool _isPickingFiles = false;

  // ============================================================
  // ЖИЗНЕННЫЙ ЦИКЛ
  // ============================================================

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  // ============================================================
  // ДЕЙСТВИЯ — ВЫБОР ФАЙЛОВ
  // ============================================================

  /// Открыть диалог выбора файлов.
  ///
  /// **Мультивыбор включён** — `allowMultiple: true`. Список
  /// расширений — **общий** (`AppConfig.allowedFileExtensions`),
  /// RAG и `document_chat` **одинаковы**.
  ///
  /// **Проверка лимита.** Если пользователь выбрал **больше**, чем
  /// можно **добавить** — берём **первые** N и **предупреждаем**.
  Future<void> _pickFiles() async {
    if (_isPickingFiles) return;

    setState(() => _isPickingFiles = true);

    try {
      final picked = await AttachmentPickerHelper.pickFiles(
        allowMultiple: true,
      );

      if (picked.isEmpty) return;

      // После `await` виджет мог быть удалён (пользователь ушёл
      // с экрана, пока открывался системный диалог выбора файлов).
      // Проверяем `mounted` перед показом SnackBar и изменением state.
      if (!mounted) return;

      // Считаем, сколько ещё можно добавить.
      final currentCount = _selectedFiles.length;
      final availableSlots = AppConfig.ragMaxFilesPerBatch - currentCount;

      if (availableSlots <= 0) {
        AppSnackBar.showError(
          context,
          'Уже выбрано ${AppConfig.ragMaxFilesPerBatch} файлов — максимум',
        );
        return;
      }

      final toAdd = picked.take(availableSlots).toList();
      final skipped = picked.length - toAdd.length;

      setState(() {
        _selectedFiles.addAll(toAdd);
      });

      if (skipped > 0) {
        AppSnackBar.showError(
          context,
          'Добавлено ${toAdd.length}. Пропущено $skipped — превышен '
          'лимит ${AppConfig.ragMaxFilesPerBatch} файлов.',
        );
      }
    } catch (e, stackTrace) {
      final appException = ErrorHandler.handle(
        e,
        stackTrace,
        'Ошибка выбора файлов для RAG',
      );

      // После `await` виджет мог быть удалён — проверяем `mounted`.
      if (!mounted) return;
      AppSnackBar.showError(context, appException.userMessage);
    } finally {
      if (mounted) setState(() => _isPickingFiles = false);
    }
  }

  /// Убрать файл из списка выбранных.
  void _removeFile(File file) {
    setState(() => _selectedFiles.remove(file));
  }

  // ============================================================
  // ДЕЙСТВИЯ — СОЗДАНИЕ
  // ============================================================

  /// Запустить создание RAG-набора.
  ///
  /// **Валидация на клиенте** — **минимум**: имя непустое, файлы
  /// непустые. **Полная** валидация (длина, размер, MIME) —
  /// в `CreateRagUseCase._validate`.
  Future<void> _startCreation() async {
    final name = _nameController.text.trim();
    final description = _descriptionController.text.trim();

    // Валидация — синхронная, `await` ещё не было, `mounted` не нужен.
    if (name.isEmpty) {
      AppSnackBar.showError(context, 'Введите имя набора');
      return;
    }
    if (_selectedFiles.isEmpty) {
      AppSnackBar.showError(context, 'Выберите хотя бы один файл');
      return;
    }

    await ref
        .read(ragCreationProvider.notifier)
        .start(
          name: name,
          description: description.isEmpty ? null : description,
          files: List.from(_selectedFiles),
        );
  }

  /// Отменить создание и вернуться к форме.
  ///
  /// **Файлы не трогаем** — пользователь может продолжить с ними.
  void _cancelCreation() {
    AppLogger.info('CreateRagScreen: отмена создания');
    ref.read(ragCreationProvider.notifier).reset();
  }

  /// Повторить создание с теми же параметрами.
  Future<void> _retryCreation() async {
    AppLogger.info('CreateRagScreen: повтор создания');
    await _startCreation();
  }

  /// Открыть чат: создать его (если ещё не создан) и закрыть экран.
  Future<void> _openChat() async {
    final notifier = ref.read(ragCreationProvider.notifier);
    final success = await notifier.createChat();

    if (!success) {
      // Ошибка уже в state — покажется через ref.listen.
      return;
    }

    if (!mounted) return;

    // Сбрасываем состояние перед выходом — чтобы при повторном
    // открытии экрана пользователь увидел пустую форму.
    notifier.reset();

    // Возвращаемся в ChatScreen — он уже в стеке.
    // Он сам перерисуется, потому что читает sessionProvider.
    Navigator.of(context).pop();
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    final creationState = ref.watch(ragCreationProvider);
    final showForm = creationState.phase == RagCreationPhase.idle;

    // Side effect: показ ошибок через SnackBar.
    //
    // `select` — подписываемся ТОЛЬКО на `error`, чтобы callback
    // срабатывал один раз на изменение, а не на каждый build.
    ref.listen<String?>(ragCreationProvider.select((s) => s.error), (
      previous,
      next,
    ) {
      if (next == null || next.isEmpty) return;
      AppSnackBar.showError(context, next);
      ref.read(ragCreationProvider.notifier).clearError();
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Создать RAG-набор',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: _handleBack,
          tooltip: 'Назад',
        ),
      ),
      body: SafeArea(
        child: showForm
            ? _buildForm(creationState)
            : _buildProgress(creationState),
      ),
    );
  }

  /// Обработка кнопки «Назад».
  ///
  /// Если идёт процесс — **подтверждение**. Иначе — простой `pop`.
  Future<void> _handleBack() async {
    final state = ref.read(ragCreationProvider);
    if (state.isInProgress) {
      await _confirmCancel();
    } else {
      if (mounted) Navigator.of(context).pop();
    }
  }

  // ============================================================
  // ФОРМА
  // ============================================================

  Widget _buildForm(RagCreationState state) {
    // Пересобираем `canCreate` на каждом `build`.
    // `_nameController` может меняться, `_selectedFiles` тоже.
    final canCreate =
        _nameController.text.trim().isNotEmpty &&
        _selectedFiles.isNotEmpty &&
        !_isPickingFiles;

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildNameField(),
                const SizedBox(height: 16),
                _buildDescriptionField(),
                const SizedBox(height: 24),
                _buildFilesSection(),
              ],
            ),
          ),
        ),
        _buildBottomCreateButton(canCreate),
      ],
    );
  }

  Widget _buildNameField() {
    return TextField(
      controller: _nameController,
      textInputAction: TextInputAction.next,
      maxLength: AppConfig.ragMaxNameLength,
      onChanged: (_) => setState(() {}), // для пересчёта `canCreate`
      decoration: InputDecoration(
        labelText: 'Имя набора *',
        hintText: 'Например: Регламенты 2026',
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppTheme.primary, width: 2),
        ),
        counterText: '',
      ),
    );
  }

  Widget _buildDescriptionField() {
    return TextField(
      controller: _descriptionController,
      textInputAction: TextInputAction.done,
      maxLength: AppConfig.ragMaxDescriptionLength,
      maxLines: 3,
      decoration: InputDecoration(
        labelText: 'Описание (опционально)',
        hintText: 'Кратко опишите, что за документы',
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppTheme.primary, width: 2),
        ),
        counterText: '',
      ),
    );
  }

  Widget _buildFilesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Text(
              'Файлы',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '(${_selectedFiles.length}/${AppConfig.ragMaxFilesPerBatch})',
              style: const TextStyle(
                fontSize: 14,
                color: AppTheme.textSecondary,
              ),
            ),
            const Spacer(),
            TextButton.icon(
              onPressed: _isPickingFiles ? null : _pickFiles,
              icon: _isPickingFiles
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.add, size: 20),
              label: const Text('Добавить'),
              style: TextButton.styleFrom(foregroundColor: AppTheme.primary),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (_selectedFiles.isEmpty)
          _buildEmptyFilesPlaceholder()
        else
          _buildFilesList(),
      ],
    );
  }

  Widget _buildEmptyFilesPlaceholder() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppTheme.primaryLight,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: AppTheme.primary.withValues(alpha: 0.2),
          width: 1,
        ),
      ),
      child: const Column(
        children: [
          Icon(Icons.upload_file_outlined, size: 40, color: AppTheme.primary),
          SizedBox(height: 8),
          Text(
            'Файлы не выбраны',
            style: TextStyle(fontSize: 14, color: AppTheme.textSecondary),
          ),
          SizedBox(height: 4),
          Text(
            AppConfig.allowedFormatsDescription,
            style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildFilesList() {
    return Column(
      children: [
        for (final file in _selectedFiles)
          _FileChip(file: file, onRemove: () => _removeFile(file)),
      ],
    );
  }

  Widget _buildBottomCreateButton(bool canCreate) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        border: Border(
          top: BorderSide(
            color: AppTheme.primary.withValues(alpha: 0.2),
            width: 1,
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 48,
          child: ElevatedButton.icon(
            onPressed: canCreate ? _startCreation : null,
            icon: const Icon(Icons.add_circle_outline, size: 20),
            label: const Text('Создать RAG-набор'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white,
              disabledBackgroundColor: Colors.grey[300],
              disabledForegroundColor: Colors.grey[600],
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 0,
            ),
          ),
        ),
      ),
    );
  }

  // ============================================================
  // ПРОГРЕСС
  // ============================================================

  Widget _buildProgress(RagCreationState state) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          const SizedBox(height: 24),
          RagCreationProgress(
            onOpenChat: _openChat,
            onCancel: _cancelCreation,
            onRetry: _retryCreation,
          ),
        ],
      ),
    );
  }

  // ============================================================
  // ПОДТВЕРЖДЕНИЕ ОТМЕНЫ
  // ============================================================

  Future<void> _confirmCancel() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Отменить создание?'),
        content: const Text(
          'Набор уже создаётся. Если вы уйдёте сейчас, '
          'процесс будет прерван — но набор останется в системе. '
          'Продолжить можно будет позже.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Остаться'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Уйти'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      ref.read(ragCreationProvider.notifier).reset();
      if (mounted) Navigator.of(context).pop();
    }
  }
}

// ============================================================
// ЧИП ФАЙЛА
// ============================================================

/// Чип одного файла в списке выбранных.
///
/// **Почему не `AttachmentPreview`.** Тот работает с доменной моделью
/// `Attachment` и показывает **превью** (картинку/иконку + имя + статус
/// загрузки). У нас — просто `File` **до** создания набора:
/// нет ни статуса, ни `remoteId`. Проще **свой** компактный виджет.
class _FileChip extends StatelessWidget {
  final File file;
  final VoidCallback onRemove;

  const _FileChip({required this.file, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    final name = file.uri.pathSegments.last;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.primaryLight,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: AppTheme.primary.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.insert_drive_file_outlined,
            size: 20,
            color: AppTheme.primary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              name,
              style: const TextStyle(fontSize: 14, color: AppTheme.textPrimary),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            onPressed: onRemove,
            icon: const Icon(Icons.close, size: 18),
            color: AppTheme.textSecondary,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            tooltip: 'Удалить',
          ),
        ],
      ),
    );
  }
}
