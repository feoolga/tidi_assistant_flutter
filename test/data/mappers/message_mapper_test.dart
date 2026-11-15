// test/data/mappers/message_mapper_test.dart

import 'package:flutter_test/flutter_test.dart';

import 'package:tidi_assistant_flutter/data/mappers/message_mapper.dart';
import 'package:tidi_assistant_flutter/data/models/message_dto.dart';
import 'package:tidi_assistant_flutter/domain/models/message_status.dart';

void main() {
  // ============================================================
  // timestamp
  // ============================================================

  group('timestamp', () {
    test('валидная дата — прокидывается как есть', () {
      final dto = MessageDto.fromJson({
        'id': 'msg-1',
        'role': 'user',
        'content': 'вопрос',
        'created_at': '2026-11-05T14:35:00',
      });

      final message = MessageMapper.toDomain(dto);

      expect(message.timestamp, DateTime(2026, 11, 5, 14, 35));
    });

    test('timestamp = null → подставляется DateTime.now() (fallback)', () {
      final dto = MessageDto.fromJson({
        'id': 'msg-1',
        'role': 'user',
        'content': 'вопрос',
        'created_at': null,
      });

      final before = DateTime.now();
      final message = MessageMapper.toDomain(dto);
      final after = DateTime.now();

      // Проверяем, что timestamp — «сейчас» (в пределах ±1 сек).
      // Не проверяем на равенство — тест был бы flaky.
      expect(
        message.timestamp.isAfter(before) ||
            message.timestamp.isAtSameMomentAs(before),
        isTrue,
      );
      expect(
        message.timestamp.isBefore(after) ||
            message.timestamp.isAtSameMomentAs(after),
        isTrue,
      );
    });
  });

  // ============================================================
  // status
  // ============================================================

  group('status', () {
    test('"ok" → MessageStatus.ok', () {
      final dto = MessageDto.fromJson({
        'id': 'msg-1',
        'role': 'assistant',
        'content': 'ответ',
        'created_at': '2026-11-05T14:35:00',
        'status': 'ok',
      });

      expect(MessageMapper.toDomain(dto).status, MessageStatus.ok);
    });

    test('"failed" → MessageStatus.failed', () {
      final dto = MessageDto.fromJson({
        'id': 'msg-1',
        'role': 'assistant',
        'content': '',
        'created_at': '2026-11-05T14:35:00',
        'status': 'failed',
        'error': 'client_disconnected',
      });

      final message = MessageMapper.toDomain(dto);

      expect(message.status, MessageStatus.failed);
      expect(message.errorMessage, 'client_disconnected');
    });

    test('"pending" → MessageStatus.pending', () {
      final dto = MessageDto.fromJson({
        'id': 'msg-1',
        'role': 'assistant',
        'content': '',
        'created_at': '2026-11-05T14:35:00',
        'status': 'pending',
      });

      expect(MessageMapper.toDomain(dto).status, MessageStatus.pending);
    });

    test('status отсутствует → MessageStatus.ok (безопасный дефолт)', () {
      final dto = MessageDto.fromJson({
        'id': 'msg-1',
        'role': 'user',
        'content': 'вопрос',
        'created_at': '2026-11-05T14:35:00',
      });

      expect(MessageMapper.toDomain(dto).status, MessageStatus.ok);
    });

    test('незнакомый status → MessageStatus.ok + не падает', () {
      final dto = MessageDto.fromJson({
        'id': 'msg-1',
        'role': 'assistant',
        'content': 'ответ',
        'created_at': '2026-11-05T14:35:00',
        'status': 'cancelled',
      });

      expect(MessageMapper.toDomain(dto).status, MessageStatus.ok);
    });
  });

  // ============================================================
  // sources (старые тесты, не трогаем)
  // ============================================================

  test('document_chat: sources из строк', () {
    final dto = MessageDto.fromJson({
      'id': 'msg-1',
      'role': 'assistant',
      'content': 'ответ',
      'created_at': '2026-10-08T06:09:58.741980Z',
      'sources': ['file1.pdf', 'file2.pdf (частично)'],
    });

    final message = MessageMapper.toDomain(dto);

    expect(message.sources, isNotNull);
    expect(message.sources!.length, 2);
    expect(message.sources![0].filename, 'file1.pdf');
  });

  test('agentic_rag: sources из объектов', () {
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

    expect(message.sources!.length, 1);
    expect(message.sources!.first.filename, 'file.pdf');
  });
}
