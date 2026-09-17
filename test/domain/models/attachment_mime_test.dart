// test/domain/models/attachment_mime_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:tidi_assistant_flutter/domain/models/attachment.dart';

void main() {
  // ============================================================
  // РАЗРЕШЁННЫЕ ФОРМАТЫ
  // ============================================================

  group('разрешённые форматы', () {
    test('.pdf → application/pdf', () {
      expect(
        attachmentMimeTypeFromFilename('накладная.pdf'),
        'application/pdf',
      );
    });

    test('.jpg → image/jpeg', () {
      expect(attachmentMimeTypeFromFilename('photo.jpg'), 'image/jpeg');
    });

    test('.jpeg → image/jpeg', () {
      expect(attachmentMimeTypeFromFilename('photo.jpeg'), 'image/jpeg');
    });

    test('.png → image/png', () {
      expect(attachmentMimeTypeFromFilename('screen.png'), 'image/png');
    });
  });

  // ============================================================
  // РЕГИСТР
  // ============================================================

  group('регистр не важен', () {
    test('.PDF → application/pdf', () {
      expect(attachmentMimeTypeFromFilename('ДОГОВОР.PDF'), 'application/pdf');
    });

    test('.JPG → image/jpeg', () {
      expect(attachmentMimeTypeFromFilename('PHOTO.JPG'), 'image/jpeg');
    });

    test('.Png (смешанный) → image/png', () {
      expect(attachmentMimeTypeFromFilename('Screen.Png'), 'image/png');
    });
  });

  // ============================================================
  // НЕИЗВЕСТНЫЕ ФОРМАТЫ
  // ============================================================

  group('неизвестные форматы', () {
    test('.docx → application/octet-stream', () {
      expect(
        attachmentMimeTypeFromFilename('document.docx'),
        'application/octet-stream',
      );
    });

    test('.txt → application/octet-stream', () {
      expect(
        attachmentMimeTypeFromFilename('notes.txt'),
        'application/octet-stream',
      );
    });

    test('.webp (пока не разрешён) → application/octet-stream', () {
      expect(
        attachmentMimeTypeFromFilename('image.webp'),
        'application/octet-stream',
      );
    });

    test('без расширения → application/octet-stream', () {
      expect(
        attachmentMimeTypeFromFilename('README'),
        'application/octet-stream',
      );
    });

    test('пустая строка → application/octet-stream', () {
      expect(attachmentMimeTypeFromFilename(''), 'application/octet-stream');
    });
  });

  // ============================================================
  // ХИТРЫЕ СЛУЧАИ
  // ============================================================

  group('хитрые случаи', () {
    test('точка в имени, но расширение не наше → octet-stream', () {
      // .gz — не наше расширение, хотя имя длинное
      expect(
        attachmentMimeTypeFromFilename('archive.tar.gz'),
        'application/octet-stream',
      );
    });

    test('несколько точек, последняя — наша → правильный MIME', () {
      // Смотрим только на последнее расширение
      expect(
        attachmentMimeTypeFromFilename('договор.2026.pdf'),
        'application/pdf',
      );
    });

    test('пробелы в имени не мешают', () {
      expect(
        attachmentMimeTypeFromFilename('мой договор.pdf'),
        'application/pdf',
      );
    });

    test('кириллица в имени не мешает', () {
      expect(
        attachmentMimeTypeFromFilename('накладная №1.pdf'),
        'application/pdf',
      );
    });

    test('путь в имени — берём только расширение', () {
      expect(attachmentMimeTypeFromFilename('/tmp/photo.jpg'), 'image/jpeg');
    });
  });
}
