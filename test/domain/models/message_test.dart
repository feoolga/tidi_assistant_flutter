import 'package:flutter_test/flutter_test.dart';
import 'package:tidi_assistant_flutter/domain/models/attachment.dart';
import 'package:tidi_assistant_flutter/domain/models/message.dart';

void main() {
  // Готовим "эталонное" сообщение, чтобы не писать его в каждом тесте
  Message buildMessage() => Message(
    id: '1',
    text: 'Привет',
    isFromUser: false,
    timestamp: DateTime(2026, 1, 1),
    agentId: 'epoz',
    sessionId: 's1',
  );

  // --- БАЗОВЫЙ ТЕСТ: ничего не сломалось ---
  test('copyWith без параметров возвращает копию с теми же полями', () {
    final msg = buildMessage();
    final copy = msg.copyWith();

    expect(copy.text, 'Привет');
    expect(copy.agentId, 'epoz');
    expect(copy.sessionId, 's1');
  });

  // --- ГЛАВНЫЙ ТЕСТ: тот самый sentinel ---
  test('copyWith сбрасывает agentId в null', () {
    final msg = buildMessage();
    final cleared = msg.copyWith(agentId: null);

    expect(cleared.agentId, isNull);
    expect(cleared.sessionId, 's1'); // не тронули — осталось
  });

  test('copyWith сбрасывает sessionId в null', () {
    final msg = buildMessage();
    final cleared = msg.copyWith(sessionId: null);

    expect(cleared.sessionId, isNull);
    expect(cleared.agentId, 'epoz');
  });

  test('copyWith сбрасывает sources в null', () {
    final msg = Message(
      id: '2',
      text: 'hi',
      isFromUser: false,
      timestamp: DateTime(2026, 1, 1),
      sources: ['накладная.pdf'],
    );

    final cleared = msg.copyWith(sources: null);
    expect(cleared.sources, isNull);
  });

  test('copyWith изменяет text и НЕ трогает остальные поля', () {
    final msg = buildMessage();
    final updated = msg.copyWith(text: 'Пока');

    expect(updated.text, 'Пока');
    expect(updated.id, '1');
    expect(updated.agentId, 'epoz');
    expect(updated.isFromUser, false);
  });

  // --- ГРАНИЧНЫЕ СЛУЧАИ ---
  test('copyWith с пустой строкой работает как с обычным значением', () {
    final msg = buildMessage();
    final updated = msg.copyWith(text: '');

    expect(updated.text, ''); // пустая строка ≠ null
  });

  // ============================================================
  // ATTACHMENTS
  // ============================================================

  // Хелпер для тестового вложения — свой, чтобы не зависеть от других файлов.
  Attachment buildAttachment({
    String localId = 'local-1',
    String fileName = 'накладная.pdf',
    AttachmentKind kind = AttachmentKind.pdf,
  }) {
    return Attachment(
      localId: localId,
      fileName: fileName,
      mimeType: 'application/pdf',
      sizeBytes: 1024,
      localPath: '/tmp/$fileName',
      kind: kind,
    );
  }

  test('fromUser без attachments → пустой список', () {
    final msg = Message.fromUser(text: 'привет');

    expect(msg.attachments, isEmpty);
    expect(msg.isFromUser, isTrue);
  });

  test('fromUser сохраняет переданные attachments', () {
    final att = buildAttachment();
    final msg = Message.fromUser(text: 'вот файл', attachments: [att]);

    expect(msg.attachments, hasLength(1));
    expect(msg.attachments.first, same(att));
    expect(msg.isFromUser, isTrue);
  });

  test('copyWith заменяет attachments и не трогает оригинал', () {
    final msg = Message.fromUser(text: 'привет'); // пустой список
    final att = buildAttachment();

    final updated = msg.copyWith(attachments: [att]);

    expect(updated.attachments, hasLength(1));
    expect(updated.attachments.first, same(att));
    // Оригинал не изменился — immutability.
    expect(msg.attachments, isEmpty);
  });
}
