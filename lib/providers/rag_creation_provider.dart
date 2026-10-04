// lib/providers/rag_creation_provider.dart

import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config/app_config.dart';
import '../core/errors/error_handler.dart';
import '../core/logger/app_logger.dart';
import '../core/utils/copy_with_marker.dart';
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
///
/// **Почему отдельные фазы, а не просто «загрузка»:** UI
/// показывает **разные** сообщения и индикаторы в каждой фазе.
/// Плюс — фаза `failed` **сохраняет** контекст (например, `ragId`
/// уже создан, если упало на `uploadingFiles`).
enum RagCreationPhase {
  /// Ничего не происходит. Пользователь может начать создание.
  idle,

  /// Создаём RAG-набор (`RagRepository.create`).
  creatingRag,

  /// Загружаем файлы в набор (`RagRepository.uploadDocuments`).
  uploadingFiles,

  /// Ждём готовности набора (`WatchRagReadinessUseCase`).
  waitingReadiness,

  /// Набор готов. Можно открывать чат.
  ready,

  /// Ошибка на любой из фаз.
  failed,
}

// ============================================================
// 2. СОСТОЯНИЕ
// ============================================================

/// Состояние создания RAG-набора.
///
/// **Что здесь есть:**
/// - [phase] — что сейчас происходит (UI по нему решает, что рисовать);
/// - [name] — имя набора (для отображения в UI);
/// - [files] — выбранные файлы (для отображения списка);
/// - [ragId] — ID созданного набора (появляется после `create`);
/// - [ragSet] — актуальное состояние набора (со счётчиками документов);
/// - [error] — ошибка (для SnackBar);
/// - [createdChatId] — ID созданного чата (после `createChat`).
///
/// **Что НЕ здесь:**
/// - сам чат (`ChatSession`) — он в `sessionProvider` (SSOT);
/// - `agentId` — константа `AppConfig.ragChatAgentId`.
class RagCreationState {
  final RagCreationPhase phase;
  final String? name;
  final List<File> files;
  final String? ragId;
  final RagSet? ragSet;
  final String? error;
  final String? createdChatId;

  const RagCreationState({
    this.phase = RagCreationPhase.idle,
    this.name,
    this.files = const [],
    this.ragId,
    this.ragSet,
    this.error,
    this.createdChatId,
  });

  /// Начальное состояние — ничего не происходит.
  factory RagCreationState.initial() => const RagCreationState();

  RagCreationState copyWith({
    RagCreationPhase? phase,
    Object? name = copyWithUnset,
    List<File>? files,
    Object? ragId = copyWithUnset,
    Object? ragSet = copyWithUnset,
    Object? error = copyWithUnset,
    Object? createdChatId = copyWithUnset,
  }) {
    return RagCreationState(
      phase: phase ?? this.phase,
      name: isCopyWithUnset(name) ? this.name : name as String?,
      files: files ?? this.files,
      ragId: isCopyWithUnset(ragId) ? this.ragId : ragId as String?,
      ragSet: isCopyWithUnset(ragSet) ? this.ragSet : ragSet as RagSet?,
      error: isCopyWithUnset(error) ? this.error : error as String?,
      createdChatId: isCopyWithUnset(createdChatId)
          ? this.createdChatId
          : createdChatId as String?,
    );
  }

  // ---- Производные геттеры ----

  /// Идёт ли сейчас какая-то работа?
  bool get isInProgress =>
      phase == RagCreationPhase.creatingRag ||
      phase == RagCreationPhase.uploadingFiles ||
      phase == RagCreationPhase.waitingReadiness;

  /// Есть ли ошибка?
  bool get hasError => error != null && error!.isNotEmpty;

  /// Готов ли набор?
  bool get isReady => phase == RagCreationPhase.ready;

  @override
  String toString() {
    return 'RagCreationState(phase: $phase, name: $name, '
        'filesCount: ${files.length}, ragId: $ragId, '
        'hasError: $hasError)';
  }
}

// ============================================================
// 3. NOTIFIER
// ============================================================

/// Нотифаер создания RAG-набора.
///
/// **Роль.** Оркестратор: вызывает UseCase-ы в правильном порядке,
/// обновляет state, пишет в `sessionProvider` при создании чата.
///
/// **Флоу «RAG по кнопке»:**
/// 1. UI вызывает `start(name, files)`.
/// 2. `CreateRagUseCase` — создаёт набор + загружает файлы +
///    перечитывает `RagSet`.
/// 3. `WatchRagReadinessUseCase` — эмитит `RagSet` каждые N секунд,
///    пока `hasPending == true`.
/// 4. Когда `hasPending == false` — `phase: ready`.
/// 5. UI показывает «Готово» + кнопку «Открыть чат».
/// 6. UI вызывает `createChat()`.
/// 7. `StartRagChatUseCase` — создаёт чат.
/// 8. Пишем в `sessionProvider`: `agentId=agentic_rag`,
///    `sessionId=chatId`, `ragId=...`, `agentDisplayName=name`.
/// 9. UI переходит в `ChatScreen`.
///
/// **Что НЕ делает:**
/// - не переключает экраны (это UI, D8);
/// - не показывает SnackBar (это UI, D8);
/// - не управляет списком RAG-наборов (это D7).
class RagCreationNotifier extends StateNotifier<RagCreationState> {
  // ============================================================
  // 3.1. ЗАВИСИМОСТИ
  // ============================================================

  final Ref _ref;
  final CreateRagUseCase _createRagUseCase;
  final WatchRagReadinessUseCase _watchRagReadinessUseCase;
  final StartRagChatUseCase _startRagChatUseCase;

  /// Текущая подписка на polling — нужна для отмены.
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
  /// **Шаги:**
  /// 1. `phase: creatingRag` — создаём набор.
  /// 2. `phase: uploadingFiles` — загружаем файлы.
  /// 3. `phase: waitingReadiness` — начинаем polling.
  /// 4. Когда набор готов (`hasPending == false`) — `phase: ready`.
  ///
  /// **При ошибке на любом шаге** — `phase: failed`, `error` заполнен.
  /// `ragId` сохраняется, если уже был создан.
  Future<void> start({
    required String name,
    String? description,
    required List<File> files,
    Map<String, dynamic>? config,
  }) async {
    // Отменяем предыдущий polling, если был.
    await _cancelReadinessSubscription();

    AppLogger.info(
      'RagCreationNotifier.start: name="$name", files=${files.length}',
    );

    // ---- Фаза 1: создание набора + загрузка ----
    state = state.copyWith(
      phase: RagCreationPhase.creatingRag,
      name: name,
      files: files,
      error: null,
      createdChatId: null,
    );

    RagSet createdSet;
    try {
      // Переключаем phase на uploadingFiles ПЕРЕД вызовом — чтобы UI
      // успел показать «Загружаем файлы…». Технически внутри
      // CreateRagUseCase идёт и create, и upload — но UI переключать
      // дважды неудобно.
      state = state.copyWith(phase: RagCreationPhase.uploadingFiles);

      createdSet = await _createRagUseCase.execute(
        name: name,
        description: description,
        files: files,
        config: config,
      );

      state = state.copyWith(ragId: createdSet.id, ragSet: createdSet);
      AppLogger.info(
        'RagCreationNotifier: набор создан, ragId=${createdSet.id}',
      );
    } catch (e, stackTrace) {
      _handleError(e, stackTrace, 'Ошибка создания RAG-набора');
      return;
    }

    // ---- Фаза 3: ожидание готовности ----
    state = state.copyWith(phase: RagCreationPhase.waitingReadiness);

    try {
      await _waitForReadiness(createdSet.id);
    } catch (e, stackTrace) {
      _handleError(e, stackTrace, 'Ошибка ожидания готовности');
      return;
    }
  }

  /// Создать чат с готовым RAG-набором.
  ///
  /// Вызывается **после** того, как `phase == ready` и пользователь
  /// нажал «Открыть чат».
  ///
  /// **Что делает:**
  /// 1. Вызывает `StartRagChatUseCase`.
  /// 2. Пишет сессию в `sessionProvider` — SSOT.
  /// 3. Сохраняет `createdChatId` в state.
  ///
  /// **Возвращает** `true`, если чат создан успешно.
  /// **Возвращает** `false`, если ошибка (UI покажет `error`).
  Future<bool> createChat() async {
    final ragId = state.ragId;
    final name = state.name;

    if (ragId == null) {
      AppLogger.error('createChat вызван без ragId');
      _setError('RAG-набор ещё не создан');
      return false;
    }

    // Уже создан — не создаём повторно.
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

      // Пишем в SSOT — sessionProvider.
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

  /// Сбросить состояние в `idle`.
  ///
  /// Используется:
  /// - при нажатии «Отмена» в UI;
  /// - при закрытии экрана создания;
  /// - при возврате из `ready`.
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
  // 3.3. ПРИВАТНЫЕ МЕТОДЫ — POLLING
  // ============================================================

  /// Запустить polling готовности и дождаться результата.
  ///
  /// **Как работает.** Подписывается на `Stream<RagSet>`
  /// от `WatchRagReadinessUseCase`. Каждое событие:
  /// - обновляем `ragSet` в state (для UI — прогресс);
  /// - если `hasPending == false` — завершаем.
  ///
  /// **Ошибка в стриме** — пробрасываем через `throw`.
  /// **Завершение стрима без `ready`** — это нормально: UseCase
  /// закрывает стрим **только** когда готово (или ошибка).
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

    // Проверяем: если дошли сюда без ошибки и стрим закрыт —
    // значит, набор готов.
    if (state.ragSet != null && !state.ragSet!.hasPending) {
      state = state.copyWith(phase: RagCreationPhase.ready);
    }
  }

  /// Отменить текущую подписку на polling (если есть).
  Future<void> _cancelReadinessSubscription() async {
    if (_readinessSubscription != null) {
      await _readinessSubscription!.cancel();
      _readinessSubscription = null;
    }
  }

  // ============================================================
  // 3.4. ПРИВАТНЫЕ МЕТОДЫ — ОБРАБОТКА ОШИБОК
  // ============================================================

  /// Обработать ошибку — превратить в `RagException` и записать
  /// в state.
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

  /// Просто установить сообщение об ошибке.
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

/// Провайдер `CreateRagUseCase`.
final createRagUseCaseProvider = Provider<CreateRagUseCase>((ref) {
  final repository = ref.read(ragRepositoryProvider);
  return CreateRagUseCase(repository: repository);
});

/// Провайдер `WatchRagReadinessUseCase`.
final watchRagReadinessUseCaseProvider = Provider<WatchRagReadinessUseCase>((
  ref,
) {
  final repository = ref.read(ragRepositoryProvider);
  return WatchRagReadinessUseCase(repository: repository);
});

/// Провайдер `StartRagChatUseCase`.
final startRagChatUseCaseProvider = Provider<StartRagChatUseCase>((ref) {
  final repository = ref.read(chatRepositoryProvider);
  return StartRagChatUseCase(chatRepository: repository);
});

/// Провайдер для `RagCreationNotifier`.
final ragCreationProvider =
    StateNotifierProvider<RagCreationNotifier, RagCreationState>((ref) {
      return RagCreationNotifier(
        ref: ref,
        createRagUseCase: ref.read(createRagUseCaseProvider),
        watchRagReadinessUseCase: ref.read(watchRagReadinessUseCaseProvider),
        startRagChatUseCase: ref.read(startRagChatUseCaseProvider),
      );
    });
