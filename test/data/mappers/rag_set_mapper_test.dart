// test/data/mappers/rag_set_mapper_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:tidi_assistant_flutter/data/mappers/rag_set_mapper.dart';
import 'package:tidi_assistant_flutter/data/models/documents_counts_dto.dart';
import 'package:tidi_assistant_flutter/data/models/rag_config_dto.dart';
import 'package:tidi_assistant_flutter/data/models/rag_set_dto.dart';
import 'package:tidi_assistant_flutter/domain/models/rag_status.dart';

/// Маркер «не передали параметр».
///
/// Нужен, чтобы отличать «дефолт» от «явно null» в тестах
/// на fallback. Живёт **на верхнем уровне** файла, чтобы
/// быть `const` и использоваться в дефолтах параметров хелпера.
const _unset = Object();

void main() {
  group('RagSetMapper.toDomain', () {
    // Хелпер — создаёт DTO с разумными дефолтами.
    // «Обычные» тесты не задают `documents`, `config`, даты —
    // получают безопасные дефолты и не триггерят warnings.
    // Fallback-тесты явно передают `null` — это проверяет
    // срабатывание fallback.
    RagSetDto buildDto({
      String id = 'rag-1',
      String name = 'Тестовый набор',
      Object? description = _unset,
      String? status = 'empty',
      Object? documents = _unset,
      Object? chunksTotal = _unset,
      bool hasPending = false,
      bool hasIcon = false,
      Object? config = _unset,
      Object? createdAt = _unset,
      Object? updatedAt = _unset,
    }) {
      final now = DateTime(2026, 1, 1);
      return RagSetDto(
        id: id,
        name: name,
        description: identical(description, _unset)
            ? null
            : description as String?,
        status: status,
        documents: identical(documents, _unset)
            ? const DocumentsCountsDto()
            : documents as DocumentsCountsDto?,
        chunksTotal: identical(chunksTotal, _unset) ? 0 : chunksTotal as int?,
        hasPending: hasPending,
        hasIcon: hasIcon,
        config: identical(config, _unset)
            ? const RagConfigDto()
            : config as RagConfigDto?,
        createdAt: identical(createdAt, _unset) ? now : createdAt as DateTime?,
        updatedAt: identical(updatedAt, _unset) ? now : updatedAt as DateTime?,
      );
    }

    // ============================================================
    // HAPPY PATH
    // ============================================================

    group('happy path', () {
      test('маппит все поля корректно', () {
        final created = DateTime(2026, 1, 15);
        final updated = DateTime(2026, 1, 20);
        final dto = buildDto(
          id: 'rag-42',
          name: 'Регламенты',
          description: 'Описание набора',
          status: 'ready',
          documents: const DocumentsCountsDto(
            total: 5,
            ready: 3,
            failed: 1,
            pending: 1,
          ),
          chunksTotal: 152,
          hasPending: true,
          hasIcon: true,
          config: const RagConfigDto(
            prompt: 'Отвечай кратко',
            temperature: 0.5,
            topK: 7,
            scoreThreshold: 0.6,
          ),
          createdAt: created,
          updatedAt: updated,
        );

        final set = RagSetMapper.toDomain(dto);

        expect(set.id, 'rag-42');
        expect(set.name, 'Регламенты');
        expect(set.description, 'Описание набора');
        expect(set.status, RagStatus.ready);
        expect(set.documentsCounts.total, 5);
        expect(set.documentsCounts.ready, 3);
        expect(set.documentsCounts.failed, 1);
        expect(set.documentsCounts.pending, 1);
        expect(set.chunksTotal, 152);
        expect(set.hasPending, isTrue);
        expect(set.hasIcon, isTrue);
        expect(set.config.prompt, 'Отвечай кратко');
        expect(set.config.temperature, 0.5);
        expect(set.config.topK, 7);
        expect(set.config.scoreThreshold, 0.6);
        expect(set.createdAt, created);
        expect(set.updatedAt, updated);
      });
    });

    // ============================================================
    // ПАРСИНГ STATUS
    // ============================================================

    group('парсинг status', () {
      test('"empty" → empty', () {
        final set = RagSetMapper.toDomain(buildDto(status: 'empty'));
        expect(set.status, RagStatus.empty);
      });

      test('"ingesting" → ingesting', () {
        final set = RagSetMapper.toDomain(buildDto(status: 'ingesting'));
        expect(set.status, RagStatus.ingesting);
      });

      test('"ready" → ready', () {
        final set = RagSetMapper.toDomain(buildDto(status: 'ready'));
        expect(set.status, RagStatus.ready);
      });

      test('"failed" → failed', () {
        final set = RagSetMapper.toDomain(buildDto(status: 'failed'));
        expect(set.status, RagStatus.failed);
      });

      test('null → ArgumentError', () {
        // status — обязательное в домене, но опциональное в DTO.
        // Маппер решает: если null — это ошибка контракта.
        expect(
          () => RagSetMapper.toDomain(buildDto(status: null)),
          throwsA(isA<ArgumentError>()),
        );
      });

      test('незнакомый статус → ArgumentError', () {
        expect(
          () => RagSetMapper.toDomain(buildDto(status: 'paused')),
          throwsA(isA<ArgumentError>()),
        );
      });

      test('пустой статус → ArgumentError', () {
        expect(
          () => RagSetMapper.toDomain(buildDto(status: '')),
          throwsA(isA<ArgumentError>()),
        );
      });

      test('статус с неправильным регистром → ArgumentError', () {
        expect(
          () => RagSetMapper.toDomain(buildDto(status: 'READY')),
          throwsA(isA<ArgumentError>()),
        );
      });
    });

    // ============================================================
    // ВЛОЖЕННЫЕ ОБЪЕКТЫ — documents
    // ============================================================

    group('documents', () {
      test('null → пустой DocumentsCounts (все нули)', () {
        final dto = buildDto(documents: null);
        final set = RagSetMapper.toDomain(dto);

        expect(set.documentsCounts.total, 0);
        expect(set.documentsCounts.ready, 0);
        expect(set.documentsCounts.failed, 0);
        expect(set.documentsCounts.pending, 0);
      });

      test('все поля мапятся корректно', () {
        final dto = buildDto(
          documents: const DocumentsCountsDto(
            total: 10,
            ready: 5,
            failed: 2,
            pending: 3,
          ),
        );
        final set = RagSetMapper.toDomain(dto);

        expect(set.documentsCounts.total, 10);
        expect(set.documentsCounts.ready, 5);
        expect(set.documentsCounts.failed, 2);
        expect(set.documentsCounts.pending, 3);
      });
    });

    // ============================================================
    // ВЛОЖЕННЫЕ ОБЪЕКТЫ — config
    // ============================================================

    group('config', () {
      test('null → дефолтный RagConfig', () {
        final dto = buildDto(config: null);
        final set = RagSetMapper.toDomain(dto);

        expect(set.config.prompt, isNull);
        expect(set.config.temperature, 0.3);
        expect(set.config.topK, 5);
        expect(set.config.scoreThreshold, 0.4);
      });

      test('пустой RagConfigDto → дефолтные значения', () {
        final dto = buildDto(config: const RagConfigDto());
        final set = RagSetMapper.toDomain(dto);

        expect(set.config.temperature, 0.3);
        expect(set.config.topK, 5);
        expect(set.config.scoreThreshold, 0.4);
      });

      test('частичный config — дефолты для отсутствующих полей', () {
        // Только temperature задан, остальные — null.
        final dto = buildDto(config: const RagConfigDto(temperature: 0.9));
        final set = RagSetMapper.toDomain(dto);

        expect(set.config.temperature, 0.9);
        expect(set.config.topK, 5); // дефолт
        expect(set.config.scoreThreshold, 0.4); // дефолт
        expect(set.config.prompt, isNull);
      });

      test('полный config маппится корректно', () {
        final dto = buildDto(
          config: const RagConfigDto(
            prompt: 'Инструкция',
            temperature: 0.7,
            topK: 10,
            scoreThreshold: 0.8,
          ),
        );
        final set = RagSetMapper.toDomain(dto);

        expect(set.config.prompt, 'Инструкция');
        expect(set.config.temperature, 0.7);
        expect(set.config.topK, 10);
        expect(set.config.scoreThreshold, 0.8);
      });
    });

    // ============================================================
    // FALLBACK — chunksTotal
    // ============================================================

    group('fallback chunksTotal', () {
      test('null → 0', () {
        final dto = buildDto(chunksTotal: null);
        final set = RagSetMapper.toDomain(dto);

        expect(set.chunksTotal, 0);
      });

      test('явный 0 сохраняется', () {
        final dto = buildDto(chunksTotal: 0);
        final set = RagSetMapper.toDomain(dto);

        expect(set.chunksTotal, 0);
      });

      test('обычное значение сохраняется', () {
        final dto = buildDto(chunksTotal: 152);
        final set = RagSetMapper.toDomain(dto);

        expect(set.chunksTotal, 152);
      });
    });

    // ============================================================
    // FALLBACK — createdAt / updatedAt
    // ============================================================

    group('fallback createdAt', () {
      test('null → Unix epoch (1970-01-01 UTC)', () {
        final dto = buildDto(createdAt: null);
        final set = RagSetMapper.toDomain(dto);

        expect(set.createdAt, DateTime.utc(1970, 1, 1));
        expect(set.createdAt.year, 1970);
        expect(set.createdAt.month, 1);
        expect(set.createdAt.day, 1);
      });

      test('обычная дата сохраняется', () {
        final created = DateTime(2026, 5, 15);
        final dto = buildDto(createdAt: created);
        final set = RagSetMapper.toDomain(dto);

        expect(set.createdAt, created);
      });
    });

    group('fallback updatedAt', () {
      test('null → Unix epoch (1970-01-01 UTC)', () {
        final dto = buildDto(updatedAt: null);
        final set = RagSetMapper.toDomain(dto);

        expect(set.updatedAt, DateTime.utc(1970, 1, 1));
        expect(set.updatedAt.year, 1970);
      });

      test('обычная дата сохраняется', () {
        final updated = DateTime(2026, 5, 20);
        final dto = buildDto(updatedAt: updated);
        final set = RagSetMapper.toDomain(dto);

        expect(set.updatedAt, updated);
      });
    });

    // ============================================================
    // FALLBACK — description
    // ============================================================

    group('description', () {
      test('null сохраняется как null', () {
        final dto = buildDto(description: null);
        final set = RagSetMapper.toDomain(dto);

        expect(set.description, isNull);
      });

      test('строка сохраняется как есть', () {
        final dto = buildDto(description: 'Описание');
        final set = RagSetMapper.toDomain(dto);

        expect(set.description, 'Описание');
      });
    });

    // ============================================================
    // BOOL-флаги
    // ============================================================

    group('hasPending', () {
      test('false сохраняется', () {
        final dto = buildDto(hasPending: false);
        final set = RagSetMapper.toDomain(dto);

        expect(set.hasPending, isFalse);
      });

      test('true сохраняется', () {
        final dto = buildDto(hasPending: true);
        final set = RagSetMapper.toDomain(dto);

        expect(set.hasPending, isTrue);
      });
    });

    group('hasIcon', () {
      test('false сохраняется', () {
        final dto = buildDto(hasIcon: false);
        final set = RagSetMapper.toDomain(dto);

        expect(set.hasIcon, isFalse);
      });

      test('true сохраняется', () {
        final dto = buildDto(hasIcon: true);
        final set = RagSetMapper.toDomain(dto);

        expect(set.hasIcon, isTrue);
      });
    });
  });
}
