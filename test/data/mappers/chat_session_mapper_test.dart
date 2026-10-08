// test/data/mappers/chat_session_mapper_test.dart

import 'package:flutter_test/flutter_test.dart';

import 'package:tidi_assistant_flutter/data/mappers/chat_session_mapper.dart';
import 'package:tidi_assistant_flutter/data/models/chat_session_dto.dart';

void main() {
  // ============================================================
  // ТЕСТ 1: RAG-чат — ragId прокидывается в домен
  // ============================================================

  test('toDomain: ragId прокидывается из DTO в домен', () {
    final dto = ChatSessionDto(
      id: 'chat-1',
      title: 'учеба в школе',
      ragId: 'rag-42',
      createdAt: DateTime.utc(2026, 10, 8, 6, 9, 24),
      updatedAt: DateTime.utc(2026, 10, 8, 6, 21, 43),
    );

    final session = ChatSessionMapper.toDomain(dto, 'agentic_rag');

    expect(session.ragId, 'rag-42');
    expect(session.agentId, 'agentic_rag');
    expect(session.id, 'chat-1');
  });

  // ============================================================
  // ТЕСТ 2: обычный чат — ragId = null
  // ============================================================

  test('toDomain: без rag_id в DTO → ragId = null', () {
    final dto = ChatSessionDto(
      id: 'chat-2',
      title: 'обычный чат',
      createdAt: DateTime.utc(2026, 10, 8),
      updatedAt: DateTime.utc(2026, 10, 8),
    );

    final session = ChatSessionMapper.toDomain(dto, 'document_chat');

    expect(session.ragId, isNull);
    expect(session.agentId, 'document_chat');
  });

  // ============================================================
  // ТЕСТ 3: ChatSessionDto.fromJson читает rag_id из JSON
  // ============================================================

  test('ChatSessionDto.fromJson: читает rag_id', () {
    final json = {
      'id': 'chat-3',
      'rag_id': 'rag-99',
      'title': 'RAG чат',
      'created_at': '2026-10-08T06:09:24.807597Z',
      'updated_at': '2026-10-08T06:21:43.266685Z',
    };

    final dto = ChatSessionDto.fromJson(json);

    expect(dto.ragId, 'rag-99');
  });

  // ============================================================
  // ТЕСТ 4: ChatSessionDto.fromJson без rag_id → null
  // ============================================================

  test('ChatSessionDto.fromJson: без rag_id → null', () {
    final json = {
      'id': 'chat-4',
      'title': 'обычный',
      'created_at': '2026-10-08T06:09:24.807597Z',
      'updated_at': '2026-10-08T06:21:43.266685Z',
    };

    final dto = ChatSessionDto.fromJson(json);

    expect(dto.ragId, isNull);
  });
}
