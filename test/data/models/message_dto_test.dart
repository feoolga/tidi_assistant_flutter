// test/data/models/message_dto_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:tidi_assistant_flutter/data/models/message_dto.dart';

void main() {
  // ============================================================
  // ВАЛИДНЫЙ JSON
  // ============================================================

  group('валидный JSON', () {
    test('парсит все поля', () {
      final dto = MessageDto.fromJson({
        'id': 'msg-1',
        'role': 'assistant',
        'content': 'ответ',
        'created_at': '2026-11-05T14:35:00',
        'status': 'ok',
        'error': null,
      });

      expect(dto.id, 'msg-1');
      expect(dto.text, 'ответ');
      expect(dto.isFromUser, isFalse);
      expect(dto.timestamp, DateTime(2026, 11, 5, 14, 35));
      expect(dto.status, 'ok');
      expect(dto.error, isNull);
    });

    test('role: user → isFromUser: true', () {
      final dto = MessageDto.fromJson({
        'id': 'msg-1',
        'role': 'user',
        'content': 'вопрос',
        'created_at': '2026-11-05T14:35:00',
      });

      expect(dto.isFromUser, isTrue);
    });

    test('id числом приводится к строке', () {
      final dto = MessageDto.fromJson({
        'id': 42,
        'role': 'user',
        'content': 'вопрос',
        'created_at': '2026-11-05T14:35:00',
      });

      expect(dto.id, '42');
    });

    test('старый формат: isFromUser + text + timestamp', () {
      final dto = MessageDto.fromJson({
        'id': 'msg-1',
        'isFromUser': true,
        'text': 'старый формат',
        'timestamp': '2026-11-05T14:35:00',
      });

      expect(dto.isFromUser, isTrue);
      expect(dto.text, 'старый формат');
      expect(dto.timestamp, DateTime(2026, 11, 5, 14, 35));
    });
  });

  // ============================================================
  // НЕВАЛИДНЫЕ / ОТСУТСТВУЮЩИЕ ДАТЫ → null (не бросает)
  // ============================================================

  group('невалидные даты → timestamp = null (без исключения)', () {
    test('created_at = null', () {
      final dto = MessageDto.fromJson({
        'id': 'msg-1',
        'role': 'user',
        'content': 'вопрос',
        'created_at': null,
      });

      expect(dto.timestamp, isNull);
    });

    test('created_at = пустая строка', () {
      final dto = MessageDto.fromJson({
        'id': 'msg-1',
        'role': 'user',
        'content': 'вопрос',
        'created_at': '',
      });

      expect(dto.timestamp, isNull);
    });

    test('created_at = невалидная ISO-строка', () {
      final dto = MessageDto.fromJson({
        'id': 'msg-1',
        'role': 'user',
        'content': 'вопрос',
        'created_at': 'это не дата',
      });

      expect(dto.timestamp, isNull);
    });

    test('created_at = число', () {
      final dto = MessageDto.fromJson({
        'id': 'msg-1',
        'role': 'user',
        'content': 'вопрос',
        'created_at': 1730000000,
      });

      expect(dto.timestamp, isNull);
    });

    test('created_at отсутствует', () {
      final dto = MessageDto.fromJson({
        'id': 'msg-1',
        'role': 'user',
        'content': 'вопрос',
      });

      expect(dto.timestamp, isNull);
    });
  });

  // ============================================================
  // ID
  // ============================================================

  group('id', () {
    test('id отсутствует — генерируется непустой fallback', () {
      final dto = MessageDto.fromJson({
        'role': 'user',
        'content': 'вопрос',
        'created_at': '2026-11-05T14:35:00',
      });

      expect(dto.id, isNotEmpty);
    });

    test('id = null — генерируется непустой fallback', () {
      final dto = MessageDto.fromJson({
        'id': null,
        'role': 'user',
        'content': 'вопрос',
        'created_at': '2026-11-05T14:35:00',
      });

      expect(dto.id, isNotEmpty);
    });
  });

  // ============================================================
  // SOURCES
  // ============================================================

  group('sources', () {
    test('формат A (document_chat): массив строк', () {
      final dto = MessageDto.fromJson({
        'id': 'msg-1',
        'role': 'assistant',
        'content': 'ответ',
        'created_at': '2026-11-05T14:35:00',
        'sources': ['file1.pdf', 'file2.pdf'],
      });

      expect(dto.sources, isNotNull);
      expect(dto.sources!.length, 2);
      expect(dto.sources![0].filename, 'file1.pdf');
      expect(dto.sources![0].order, isNull);
    });

    test('формат B (agentic_rag): объекты с метаданными', () {
      final dto = MessageDto.fromJson({
        'id': 'msg-1',
        'role': 'assistant',
        'content': 'ответ',
        'created_at': '2026-11-05T14:35:00',
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

      expect(dto.sources!.length, 1);
      expect(dto.sources!.first.order, 1);
      expect(dto.sources!.first.chunkId, 'chunk-a');
      expect(dto.sources!.first.documentId, 'doc-1');
      expect(dto.sources!.first.chunkIndex, 0);
      expect(dto.sources!.first.filename, 'file.pdf');
    });

    test('sources отсутствует → null', () {
      final dto = MessageDto.fromJson({
        'id': 'msg-1',
        'role': 'user',
        'content': 'вопрос',
        'created_at': '2026-11-05T14:35:00',
      });

      expect(dto.sources, isNull);
    });

    test('sources = [] → пустой список', () {
      final dto = MessageDto.fromJson({
        'id': 'msg-1',
        'role': 'user',
        'content': 'вопрос',
        'created_at': '2026-11-05T14:35:00',
        'sources': [],
      });

      expect(dto.sources, isNotNull);
      expect(dto.sources, isEmpty);
    });

    test('объект без filename пропускается', () {
      final dto = MessageDto.fromJson({
        'id': 'msg-1',
        'role': 'assistant',
        'content': 'ответ',
        'created_at': '2026-11-05T14:35:00',
        'sources': [
          {'order': 1},
          {'order': 2, 'filename': 'file.pdf'},
        ],
      });

      expect(dto.sources!.length, 1);
      expect(dto.sources!.first.filename, 'file.pdf');
    });
  });
}
