// test/domain/usecases/create_rag_usecase_test.dart

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tidi_assistant_flutter/core/config/app_config.dart';
import 'package:tidi_assistant_flutter/core/errors/rag_exceptions.dart';
import 'package:tidi_assistant_flutter/data/repositories/rag_repository.dart';
import 'package:tidi_assistant_flutter/domain/models/rag_config.dart';
import 'package:tidi_assistant_flutter/domain/models/rag_document.dart';
import 'package:tidi_assistant_flutter/domain/models/rag_set.dart';
import 'package:tidi_assistant_flutter/domain/models/rag_status.dart';
import 'package:tidi_assistant_flutter/domain/usecases/create_rag_usecase.dart';

// ============================================================
// FAKE — ПОДМЕНА RagRepository
// ============================================================

/// Fake для `RagRepository` — переопределяем только те методы,
/// которые **использует** `CreateRagUseCase`.
///
/// **Почему fake, а не mock.** Мокаем границу между слоями
/// (репозиторий), а не внутренность (HTTP-клиент). Никаких
/// новых зависимостей в `pubspec.yaml`.
class FakeRagRepository extends RagRepository {
  // ---- Настройки ответов ----
  RagSet? createResult;
  List<RagDocument>? uploadDocumentsResult;
  RagSet? getResult;

  // ---- Настройки ошибок ----
  Object? createError;
  Object? uploadDocumentsError;
  Object? getError;

  // ---- Записанные вызовы ----
  String? lastCreateName;
  String? lastCreateDescription;
  String? lastUploadRagId;
  int? lastUploadFilesCount;
  String? lastGetRagId;

  FakeRagRepository() : super();

  @override
  Future<RagSet> create({
    required String name,
    String? description,
    Map<String, dynamic>? config,
  }) async {
    lastCreateName = name;
    lastCreateDescription = description;
    if (createError != null) throw createError!;
    return createResult!;
  }

  @override
  Future<List<RagDocument>> uploadDocuments({
    required String ragId,
    required List<File> files,
  }) async {
    lastUploadRagId = ragId;
    lastUploadFilesCount = files.length;
    if (uploadDocumentsError != null) throw uploadDocumentsError!;
    return uploadDocumentsResult ?? const [];
  }

  @override
  Future<RagSet> get(String ragId) async {
    lastGetRagId = ragId;
    if (getError != null) throw getError!;
    return getResult!;
  }
}

// ============================================================
// ХЕЛПЕРЫ
// ============================================================

RagSet buildRagSet({
  String id = 'rag-1',
  String name = 'Тестовый',
  RagStatus status = RagStatus.empty,
  DocumentsCounts? documentsCounts,
  bool hasPending = false,
}) {
  return RagSet(
    id: id,
    name: name,
    status: status,
    documentsCounts: documentsCounts ?? const DocumentsCounts(),
    hasPending: hasPending,
    config: const RagConfig(),
    createdAt: DateTime(2026, 1, 1),
    updatedAt: DateTime(2026, 1, 1),
  );
}

/// Фиктивный `File` — только для передачи в UseCase.
///
/// **ВАЖНО:** файл **не** создаём на диске. В тестах fake-репозиторий
/// **не** читает содержимое — только получает список. Но `_validate`
/// в `CreateRagUseCase` **вызывает** `file.length()` → **упадёт**,
/// если файла нет.
///
/// Поэтому в тестах **создаём** реальные временные файлы и
/// **удаляем** их после теста. Иначе — `PathNotFoundException`.
File createTempFile({required String filename, int sizeBytes = 100}) {
  final dir = Directory.systemTemp.createTempSync('rag_test_');
  final file = File('${dir.path}/$filename');
  file.writeAsBytesSync(List.filled(sizeBytes, 0));
  return file;
}

/// Удалить временный файл (и папку).
void cleanupTempFile(File file) {
  try {
    file.parent.deleteSync(recursive: true);
  } catch (_) {
    // Игнорируем ошибки очистки — это best effort.
  }
}

// ============================================================
// ТЕСТЫ
// ============================================================

void main() {
  // ============================================================
  // CreateRagUseCase
  // ============================================================

  group('CreateRagUseCase', () {
    // ---- HAPPY PATH ----

    test(
      'happy path: create → upload → get → возвращает обновлённый RagSet',
      () async {
        final file = createTempFile(filename: 'договор.pdf', sizeBytes: 100);
        addTearDown(() => cleanupTempFile(file));

        final createdSet = buildRagSet(id: 'rag-42', name: 'Регламенты');
        final updatedSet = buildRagSet(
          id: 'rag-42',
          name: 'Регламенты',
          status: RagStatus.ingesting,
          hasPending: true,
        );

        final repo = FakeRagRepository()
          ..createResult = createdSet
          ..uploadDocumentsResult = const []
          ..getResult = updatedSet;
        final useCase = CreateRagUseCase(repository: repo);

        final result = await useCase.execute(name: 'Регламенты', files: [file]);

        expect(result.id, 'rag-42');
        expect(result.status, RagStatus.ingesting);
        expect(result.hasPending, isTrue);

        // Проверяем, что все вызовы сделаны правильно.
        expect(repo.lastCreateName, 'Регламенты');
        expect(repo.lastUploadRagId, 'rag-42');
        expect(repo.lastUploadFilesCount, 1);
        expect(repo.lastGetRagId, 'rag-42');
      },
    );

    test('description пробрасывается в create', () async {
      final file = createTempFile(filename: 'акт.pdf');
      addTearDown(() => cleanupTempFile(file));

      final repo = FakeRagRepository()
        ..createResult = buildRagSet()
        ..getResult = buildRagSet();
      final useCase = CreateRagUseCase(repository: repo);

      await useCase.execute(
        name: 'Имя',
        description: 'Описание',
        files: [file],
      );

      expect(repo.lastCreateDescription, 'Описание');
    });

    // ---- ВАЛИДАЦИЯ ----

    test('пустое имя → ArgumentError', () async {
      final file = createTempFile(filename: 'файл.pdf');
      addTearDown(() => cleanupTempFile(file));

      final repo = FakeRagRepository();
      final useCase = CreateRagUseCase(repository: repo);

      expect(
        () => useCase.execute(name: '', files: [file]),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('имя из пробелов → ArgumentError', () async {
      final file = createTempFile(filename: 'файл.pdf');
      addTearDown(() => cleanupTempFile(file));

      final repo = FakeRagRepository();
      final useCase = CreateRagUseCase(repository: repo);

      expect(
        () => useCase.execute(name: '   ', files: [file]),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('имя длиннее лимита → ArgumentError', () async {
      final file = createTempFile(filename: 'файл.pdf');
      addTearDown(() => cleanupTempFile(file));

      final repo = FakeRagRepository();
      final useCase = CreateRagUseCase(repository: repo);

      final longName = 'a' * (AppConfig.ragMaxNameLength + 1);

      expect(
        () => useCase.execute(name: longName, files: [file]),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('пустой список файлов → ArgumentError', () async {
      final repo = FakeRagRepository();
      final useCase = CreateRagUseCase(repository: repo);

      expect(
        () => useCase.execute(name: 'Имя', files: const []),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('слишком много файлов → RagException.tooManyFilesInBatch', () async {
      final repo = FakeRagRepository();
      final useCase = CreateRagUseCase(repository: repo);

      final manyFiles = <File>[];
      for (var i = 0; i <= AppConfig.ragMaxFilesPerBatch; i++) {
        final file = createTempFile(filename: 'файл$i.pdf');
        manyFiles.add(file);
        addTearDown(() => cleanupTempFile(file));
      }

      expect(
        () => useCase.execute(name: 'Имя', files: manyFiles),
        throwsA(
          isA<RagException>().having(
            (e) => e.code,
            'code',
            'RAG_TOO_MANY_FILES_IN_BATCH',
          ),
        ),
      );
    });

    test('неподдерживаемый формат → RagException.unsupportedFormat', () async {
      final file = createTempFile(filename: 'файл.xyz');
      addTearDown(() => cleanupTempFile(file));

      final repo = FakeRagRepository();
      final useCase = CreateRagUseCase(repository: repo);

      expect(
        () => useCase.execute(name: 'Имя', files: [file]),
        throwsA(
          isA<RagException>().having(
            (e) => e.code,
            'code',
            'RAG_UNSUPPORTED_FORMAT',
          ),
        ),
      );
    });

    test('файл больше лимита → RagException.fileTooLarge', () async {
      // Создаём файл чуть больше лимита.
      final file = createTempFile(
        filename: 'big.pdf',
        sizeBytes: AppConfig.ragMaxFileSizeBytes + 1,
      );
      addTearDown(() => cleanupTempFile(file));

      final repo = FakeRagRepository();
      final useCase = CreateRagUseCase(repository: repo);

      expect(
        () => useCase.execute(name: 'Имя', files: [file]),
        throwsA(
          isA<RagException>().having(
            (e) => e.code,
            'code',
            'RAG_FILE_TOO_LARGE',
          ),
        ),
      );
    });

    // ---- ОШИБКИ РЕПОЗИТОРИЯ ----

    test('create упал → пробрасывает RagException', () async {
      final file = createTempFile(filename: 'файл.pdf');
      addTearDown(() => cleanupTempFile(file));

      final repo = FakeRagRepository()
        ..createError = RagException.limitReached();
      final useCase = CreateRagUseCase(repository: repo);

      expect(
        () => useCase.execute(name: 'Имя', files: [file]),
        throwsA(
          isA<RagException>().having(
            (e) => e.code,
            'code',
            'RAG_LIMIT_REACHED',
          ),
        ),
      );
    });

    test('uploadDocuments упал → пробрасывает RagException', () async {
      final file = createTempFile(filename: 'файл.pdf');
      addTearDown(() => cleanupTempFile(file));

      final repo = FakeRagRepository()
        ..createResult = buildRagSet(id: 'rag-1')
        ..uploadDocumentsError = RagException.uploadFailed();
      final useCase = CreateRagUseCase(repository: repo);

      expect(
        () => useCase.execute(name: 'Имя', files: [file]),
        throwsA(
          isA<RagException>().having(
            (e) => e.code,
            'code',
            'RAG_UPLOAD_FAILED',
          ),
        ),
      );
    });

    test('get упал → НЕ падаем, возвращаем набор от create', () async {
      final file = createTempFile(filename: 'файл.pdf');
      addTearDown(() => cleanupTempFile(file));

      final createdSet = buildRagSet(id: 'rag-1', status: RagStatus.empty);
      final repo = FakeRagRepository()
        ..createResult = createdSet
        ..getError = RagException.createFailed();
      final useCase = CreateRagUseCase(repository: repo);

      final result = await useCase.execute(name: 'Имя', files: [file]);

      expect(result.id, 'rag-1');
      expect(result.status, RagStatus.empty);
    });
  });
}
