// test/data/mappers/message_mapper_test.dart

import 'package:flutter_test/flutter_test.dart';

import 'package:tidi_assistant_flutter/data/mappers/message_mapper.dart';
import 'package:tidi_assistant_flutter/data/models/message_dto.dart';

void main() {
  // ============================================================
  // ТЕСТ 1: document_chat — массив строк
  // ============================================================

  test(
    'sources: document_chat — массив строк превращается в MessageSource',
    () {
      final dto = MessageDto.fromJson({
        'id': 'msg-1',
        'role': 'assistant',
        'content': 'ответ',
        'created_at': '2026-10-08T06:09:58.741980Z',
        'sources': ['file1.pdf', 'file2.pdf (частично)'],
      });

      expect(dto.sources, isNotNull);
      expect(dto.sources!.length, 2);
      expect(dto.sources![0].filename, 'file1.pdf');
      expect(dto.sources![0].order, isNull);
      expect(dto.sources![0].chunkId, isNull);
      expect(dto.sources![1].filename, 'file2.pdf (частично)');
    },
  );

  // ============================================================
  // ТЕСТ 2: agentic_rag — массив объектов с метаданными
  // ============================================================

  test('sources: agentic_rag — объекты с метаданными читаются полностью', () {
    final dto = MessageDto.fromJson({
      'id': 'msg-1',
      'role': 'assistant',
      'content': 'ответ',
      'created_at': '2026-10-08T06:09:58.741980Z',
      'sources': [
        {
          'order': 1,
          'chunk_id': 'chunk-a',
          'document_id': 'doc-1',
          'chunk_index': 0,
          'filename': 'file.pdf',
        },
      ],
    });

    expect(dto.sources, isNotNull);
    expect(dto.sources!.length, 1);
    final s = dto.sources!.first;
    expect(s.order, 1);
    expect(s.chunkId, 'chunk-a');
    expect(s.documentId, 'doc-1');
    expect(s.chunkIndex, 0);
    expect(s.filename, 'file.pdf');
  });

  // ============================================================
  // ТЕСТ 3: без sources → null
  // ============================================================

  test('sources: поле отсутствует → null', () {
    final dto = MessageDto.fromJson({
      'id': 'msg-1',
      'role': 'user',
      'content': 'вопрос',
      'created_at': '2026-10-08T06:09:58.741980Z',
    });

    expect(dto.sources, isNull);
  });

  // ============================================================
  // ТЕСТ 4: пустой массив → пустой список (не null)
  // ============================================================

  test('sources: пустой массив → пустой список', () {
    final dto = MessageDto.fromJson({
      'id': 'msg-1',
      'role': 'user',
      'content': 'вопрос',
      'created_at': '2026-10-08T06:09:58.741980Z',
      'sources': [],
    });

    expect(dto.sources, isNotNull);
    expect(dto.sources, isEmpty);
  });

  // ============================================================
  // ТЕСТ 5: объект без filename пропускается
  // ============================================================

  test('sources: объект без filename пропускается', () {
    final dto = MessageDto.fromJson({
      'id': 'msg-1',
      'role': 'assistant',
      'content': 'ответ',
      'created_at': '2026-10-08T06:09:58.741980Z',
      'sources': [
        {'order': 1}, // без filename — пропуск
        {'order': 2, 'filename': 'file.pdf'},
      ],
    });

    expect(dto.sources, isNotNull);
    expect(dto.sources!.length, 1);
    expect(dto.sources!.first.filename, 'file.pdf');
  });

  // ============================================================
  // ТЕСТ 6: MessageMapper.toDomain прокидывает sources
  // ============================================================

  test('MessageMapper.toDomain прокидывает sources из DTO в домен', () {
    final dto = MessageDto.fromJson({
      'id': 'msg-1',
      'role': 'assistant',
      'content': 'ответ',
      'created_at': '2026-10-08T06:09:58.741980Z',
      'sources': [
        {
          'order': 1,
          'chunk_id': 'chunk-a',
          'document_id': 'doc-1',
          'chunk_index': 0,
          'filename': 'file.pdf',
        },
      ],
    });

    final message = MessageMapper.toDomain(dto);

    expect(message.sources, isNotNull);
    expect(message.sources!.length, 1);
    expect(message.sources!.first.filename, 'file.pdf');
  });
}
