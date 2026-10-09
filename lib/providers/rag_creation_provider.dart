// lib/providers/rag_creation_provider.dart

import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config/app_config.dart';
import '../core/errors/error_handler.dart';
import '../core/logger/app_logger.dart';
import '../core/utils/copy_with_marker.dart';
import '../domain/models/rag_document.dart';
import '../domain/models/rag_set.dart';
import '../domain/usecases/create_rag_usecase.dart';
import '../domain/usecases/start_rag_chat_usecase.dart';
import '../domain/usecases/watch_rag_readiness_usecase.dart';
import 'agent_provider.dart';
import 'session_provider.dart';

// ============================================================
// 1. ФАЗЫ СОЗДАНИЯ RAG
// ============================================================

/// Фазы жизненного цикла создания RAG-набора.
///
/// Жизненный цикл:
/// ```
/// idle
///   ↓ (start(...))
/// creatingRag       — создаём набор
///   ↓
/// uploadingFiles    — загружаем файлы
///   ↓
/// waitingReadiness  — ждём готовности (polling)
///   ↓
/// ready             — готово, можно открывать чат
/// ```
///
/// Плюс `failed` — на **любой** фазе возможна ошибка.
/// **Две разновидности `failed`:**
/// - `ragId == null` — набор не создан, всё потеряно;
/// - `ragId != null` + `isPartial == true` — набор создан, часть
///   файлов принята; UI показывает список и даёт выбор.
enum RagCreationPhase {
  idle,
  creatingRag,
  uploadingFiles,
  waitingReadiness,
  ready,
  failed,
}

// ============================================================
// 2. СОСТОЯНИЕ
// ============================================================

/// Состояние создания RAG-набора.
///
/// **Поля фазы `failed`:**
/// - [ragId] — если `!= null`, набор уже создан;
/// - [ragSet] — счётчики и статус набора;
/// - [uploadedDocuments] — список принятых документов;
/// - [isPartial] — `true`, если upload упал на середине;
/// - [uploadError] — текст ошибки upload (для отображения);
/// - [error] — общий текст ошибки (для SnackBar).
class RagCreationState {
  final RagCreationPhase phase;
  final String? name;
  final List<File> files;
  final String? ragId;
  final RagSet? ragSet;

  /// Список принятых документов набора.
  ///
  /// - при `ready` — то, что вернул `uploadDocuments`;
  /// - при `failed` с `isPartial: true` — перечитанный список
  ///   через `listDocuments` (в `CreateRagUseCase`);
  /// - пусто — во всех остальных фазах.
  final List<RagDocument> uploadedDocuments;

  /// `true` — upload упал, набор частично загружен.
  final bool isPartial;

  /// Текст ошибки upload — для отображения в теле блока прогресса
  /// при частичной загрузке.
  final String? uploadError;

  /// Общая ошибка фазы — для SnackBar (например, «не удалось создать
  /// набор», «не удалось создать чат»).
  final String? error;

  /// ID созданного чата (после `createChat`).
  final String? createdChatId;

  const RagCreationState({
    this.phase = RagCreationPhase.idle,
    this.name,
    this.files = const [],
    this.ragId,
    this.ragSet,
    this.uploadedDocuments = const [],
    this.isPartial = false,
    this.uploadError,
    this.error,
    this.createdChatId,
  });

  factory RagCreationState.initial() => const RagCreationState();

  RagCreationState copyWith({
    RagCreationPhase? phase,
    Object? name = copyWithUnset,
    List<File>? files,
    Object? ragId = copyWithUnset,
    Object? ragSet = copyWithUnset,
    List<RagDocument>? uploadedDocuments,
    bool? isPartial,
    Object? uploadError = copyWithUnset,
    Object? error = copyWithUnset,
    Object? createdChatId = copyWithUnset,
  }) {
    return RagCreationState(
      phase: phase ?? this.phase,
      name: isCopyWithUnset(name) ? this.name : name as String?,
      files: files ?? this.files,
      ragId: isCopyWithUnset(ragId) ? this.ragId : ragId as String?,
      ragSet: isCopyWithUnset(ragSet) ? this.ragSet : ragSet as RagSet?,
      uploadedDocuments: uploadedDocuments ?? this.uploadedDocuments,
      isPartial: isPartial ?? this.isPartial,
      uploadError: isCopyWithUnset(uploadError)
          ? this.uploadError
          : uploadError as String?,
      error: isCopyWithUnset(error) ? this.error : error as String?,
      createdChatId: isCopyWithUnset(createdChatId)
          ? this.createdChatId
          : createdChatId as String?,
    );
  }

  bool get isInProgress =>
      phase == RagCreationPhase.creatingRag ||
      phase == RagCreationPhase.uploadingFiles ||
      phase == RagCreationPhase.waitingReadiness;

  bool get hasError => error != null && error!.isNotEmpty;

  bool get isReady => phase == RagCreationPhase.ready;

  /// Есть ли **частичный** результат — набор с неполными файлами.
  ///
  /// Используется UI: при `true` показываем список файлов и кнопки
  /// «Открыть чат» / «Удалить набор».
  bool get hasPartialResult =>
      phase == RagCreationPhase.failed && ragId != null && isPartial;

  @override
  String toString() {
    return 'RagCreationState(phase: $phase, name: $name, '
        'filesCount: ${files.length}, ragId: $ragId, '
        'docsCount: ${uploadedDocuments.length}, '
        'isPartial: $isPartial, hasError: $hasError)';
  }
}

// ============================================================
// 3. NOTIFIER
// ============================================================

class RagCreationNotifier extends StateNotifier<RagCreationState> {
  // ============================================================
  // 3.1. ЗАВИСИМОСТИ
  // ============================================================

  final Ref _ref;
  final CreateRagUseCase _createRagUseCase;
  final WatchRagReadinessUseCase _watchRagReadinessUseCase;
  final StartRagChatUseCase _startRagChatUseCase;

  StreamSubscription<RagSet>? _readinessSubscription;

  RagCreationNotifier({
    required Ref ref,
    required CreateRagUseCase createRagUseCase,
    required WatchRagReadinessUseCase watchRagReadinessUseCase,
    required StartRagChatUseCase startRagChatUseCase,
  }) : _ref = ref,
       _createRagUseCase = createRagUseCase,
       _watchRagReadinessUseCase = watchRagReadinessUseCase,
       _startRagChatUseCase = startRagChatUseCase,
       super(RagCreationState.initial());

  // ============================================================
  // 3.2. ПУБЛИЧНЫЙ API
  // ============================================================

  /// Запустить создание RAG-набора.
  ///
  /// **Два пути:**
  /// - **полный успех** — все файлы приняты, дальше polling готовности,
  ///   `phase: ready`;
  /// - **частичный** — upload упал, набор есть, `phase: failed` +
  ///   `isPartial: true`, `uploadedDocuments` заполнен. Polling **не**
  ///   запускаем.
  Future<void> start({
    required String name,
    String? description,
    required List<File> files,
    Map<String, dynamic>? config,
  }) async {
    await _cancelReadinessSubscription();

    AppLogger.info(
      'RagCreationNotifier.start: name="$name", files=${files.length}',
    );

    state = state.copyWith(
      phase: RagCreationPhase.creatingRag,
      name: name,
      files: files,
      error: null,
      uploadError: null,
      isPartial: false,
      uploadedDocuments: const [],
      createdChatId: null,
    );

    CreateRagResult result;
    try {
      state = state.copyWith(phase: RagCreationPhase.uploadingFiles);

      result = await _createRagUseCase.execute(
        name: name,
        description: description,
        files: files,
        config: config,
      );
    } catch (e, stackTrace) {
      // `create` упал — набора нет. Всё как было.
      _handleError(e, stackTrace, 'Ошибка создания RAG-набора');
      return;
    }

    // Записываем данные набора — общие для успеха и частичной загрузки.
    state = state.copyWith(
      ragId: result.set.id,
      ragSet: result.set,
      uploadedDocuments: result.documents,
    );

    // ---- Частичная загрузка: не идём в polling ----
    if (result.isPartial) {
      AppLogger.warning(
        'RagCreationNotifier: частичная загрузка набора ${result.set.id}, '
        'принято ${result.documents.length} из ${files.length}',
      );
      state = state.copyWith(
        phase: RagCreationPhase.failed,
        isPartial: true,
        uploadError: result.uploadError?.userMessage,
      );
      return;
    }

    // ---- Полный успех: переходим к polling готовности ----
    AppLogger.info('RagCreationNotifier: набор создан, ragId=${result.set.id}');

    state = state.copyWith(phase: RagCreationPhase.waitingReadiness);

    try {
      await _waitForReadiness(result.set.id);
    } catch (e, stackTrace) {
      _handleError(e, stackTrace, 'Ошибка ожидания готовности');
    }
  }

  /// Создать чат с готовым RAG-набором.
  ///
  /// Вызывается **в двух случаях:**
  /// - при `phase: ready` — обычный путь;
  /// - при `hasPartialResult == true` — «Открыть чат» с частичным набором.
  ///
  /// **Возвращает** `true`, если чат создан успешно.
  Future<bool> createChat() async {
    final ragId = state.ragId;
    final name = state.name;

    if (ragId == null) {
      AppLogger.error('createChat вызван без ragId');
      _setError('RAG-набор ещё не создан');
      return false;
    }

    if (state.createdChatId != null) {
      AppLogger.debug('Чат уже создан: ${state.createdChatId}');
      return true;
    }

    AppLogger.info('RagCreationNotifier.createChat: ragId=$ragId');

    try {
      final session = await _startRagChatUseCase.execute(
        ragId: ragId,
        title: name,
      );

      _ref
          .read(sessionProvider.notifier)
          .setSession(
            AppConfig.ragChatAgentId,
            session.id,
            ragId: ragId,
            agentDisplayName: name,
          );

      state = state.copyWith(createdChatId: session.id);
      AppLogger.info('RagCreationNotifier: чат создан, id=${session.id}');
      return true;
    } catch (e, stackTrace) {
      _handleError(e, stackTrace, 'Ошибка создания чата с RAG-набором');
      return false;
    }
  }

  /// Удалить созданный (возможно — частично) RAG-набор.
  ///
  /// Используется кнопкой «Удалить набор» при частичной загрузке.
  /// После удаления — `reset()`, состояние возвращается в `idle`.
  Future<bool> deleteRagSet() async {
    final ragId = state.ragId;
    if (ragId == null) {
      AppLogger.warning('deleteRagSet вызван без ragId — просто reset');
      reset();
      return true;
    }

    AppLogger.info('RagCreationNotifier.deleteRagSet: ragId=$ragId');

    try {
      final repo = _ref.read(ragRepositoryProvider);
      await repo.delete(ragId);
      AppLogger.info('RagCreationNotifier: набор удалён, ragId=$ragId');
      reset();
      return true;
    } catch (e, stackTrace) {
      final appException = ErrorHandler.handle(
        e,
        stackTrace,
        'Ошибка удаления RAG-набора',
        {'ragId': ragId},
      );
      _setError(appException.userMessage);
      return false;
    }
  }

  /// Сбросить состояние в `idle`.
  void reset() {
    AppLogger.info('RagCreationNotifier.reset');
    unawaited(_cancelReadinessSubscription());
    state = RagCreationState.initial();
  }

  /// Очистить ошибку после показа SnackBar.
  void clearError() {
    if (state.error == null) return;
    state = state.copyWith(error: null);
  }

  // ============================================================
  // 3.3. POLLING
  // ============================================================

  Future<void> _waitForReadiness(String ragId) async {
    final completer = Completer<void>();

    final stream = _watchRagReadinessUseCase.execute(ragId: ragId);

    _readinessSubscription = stream.listen(
      (set) {
        AppLogger.debug(
          'RagCreationNotifier: ragSet обновлён, '
          'status=${set.status.name}, hasPending=${set.hasPending}',
        );
        state = state.copyWith(ragSet: set);
      },
      onError: (Object error, StackTrace stackTrace) {
        if (!completer.isCompleted) {
          completer.completeError(error, stackTrace);
        }
      },
      onDone: () {
        if (!completer.isCompleted) {
          completer.complete();
        }
      },
      cancelOnError: true,
    );

    await completer.future;

    if (state.ragSet != null && !state.ragSet!.hasPending) {
      state = state.copyWith(phase: RagCreationPhase.ready);
    }
  }

  Future<void> _cancelReadinessSubscription() async {
    if (_readinessSubscription != null) {
      await _readinessSubscription!.cancel();
      _readinessSubscription = null;
    }
  }

  // ============================================================
  // 3.4. ОБРАБОТКА ОШИБОК
  // ============================================================

  void _handleError(Object error, StackTrace stackTrace, String context) {
    final appException = ErrorHandler.handle(error, stackTrace, context, {
      'ragId': state.ragId,
      'name': state.name,
    });

    state = state.copyWith(
      phase: RagCreationPhase.failed,
      error: appException.userMessage,
    );
  }

  void _setError(String message) {
    state = state.copyWith(phase: RagCreationPhase.failed, error: message);
  }

  // ============================================================
  // 3.5. ОЧИСТКА
  // ============================================================

  @override
  void dispose() {
    unawaited(_cancelReadinessSubscription());
    super.dispose();
  }
}

// ============================================================
// 4. ПРОВАЙДЕР
// ============================================================

final createRagUseCaseProvider = Provider<CreateRagUseCase>((ref) {
  final repository = ref.read(ragRepositoryProvider);
  return CreateRagUseCase(repository: repository);
});

final watchRagReadinessUseCaseProvider = Provider<WatchRagReadinessUseCase>((
  ref,
) {
  final repository = ref.read(ragRepositoryProvider);
  return WatchRagReadinessUseCase(repository: repository);
});

final startRagChatUseCaseProvider = Provider<StartRagChatUseCase>((ref) {
  final repository = ref.read(chatRepositoryProvider);
  return StartRagChatUseCase(chatRepository: repository);
});

final ragCreationProvider =
    StateNotifierProvider<RagCreationNotifier, RagCreationState>((ref) {
      return RagCreationNotifier(
        ref: ref,
        createRagUseCase: ref.read(createRagUseCaseProvider),
        watchRagReadinessUseCase: ref.read(watchRagReadinessUseCaseProvider),
        startRagChatUseCase: ref.read(startRagChatUseCaseProvider),
      );
    });
