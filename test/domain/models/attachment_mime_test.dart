// test/domain/models/attachment_mime_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:tidi_assistant_flutter/domain/models/attachment.dart';

void main() {
  // ============================================================
  // PDF
  // ============================================================

  group('PDF', () {
    test('.pdf → application/pdf', () {
      expect(mimeTypeFromFilename('накладная.pdf'), 'application/pdf');
    });

    test('.PDF (верхний регистр) → application/pdf', () {
      expect(mimeTypeFromFilename('ДОГОВОР.PDF'), 'application/pdf');
    });

    test('.Pdf (смешанный) → application/pdf', () {
      expect(mimeTypeFromFilename('Договор.Pdf'), 'application/pdf');
    });
  });

  // ============================================================
  // WORD
  // ============================================================

  group('Word', () {
    test('.docx → wordprocessingml.document', () {
      expect(
        mimeTypeFromFilename('приказ.docx'),
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      );
    });

    test('.doc → application/msword', () {
      expect(mimeTypeFromFilename('старый.doc'), 'application/msword');
    });

    test('.DOCX (верхний регистр) → wordprocessingml.document', () {
      expect(
        mimeTypeFromFilename('ПРИКАЗ.DOCX'),
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      );
    });

    test('.DOC (верхний регистр) → application/msword', () {
      expect(mimeTypeFromFilename('СТАРЫЙ.DOC'), 'application/msword');
    });
  });

  // ============================================================
  // ТЕКСТОВЫЕ
  // ============================================================

  group('текстовые', () {
    test('.txt → text/plain', () {
      expect(mimeTypeFromFilename('заметка.txt'), 'text/plain');
    });

    test('.md → text/markdown', () {
      expect(mimeTypeFromFilename('README.md'), 'text/markdown');
    });

    test('.TXT (верхний регистр) → text/plain', () {
      expect(mimeTypeFromFilename('ЗАМЕТКА.TXT'), 'text/plain');
    });

    test('.MD (верхний регистр) → text/markdown', () {
      expect(mimeTypeFromFilename('README.MD'), 'text/markdown');
    });
  });

  // ============================================================
  // КАРТИНКИ
  // ============================================================

  group('картинки', () {
    test('.jpg → image/jpeg', () {
      expect(mimeTypeFromFilename('photo.jpg'), 'image/jpeg');
    });

    test('.jpeg → image/jpeg', () {
      expect(mimeTypeFromFilename('photo.jpeg'), 'image/jpeg');
    });

    test('.png → image/png', () {
      expect(mimeTypeFromFilename('screen.png'), 'image/png');
    });

    test('.JPG (верхний регистр) → image/jpeg', () {
      expect(mimeTypeFromFilename('PHOTO.JPG'), 'image/jpeg');
    });

    test('.Png (смешанный) → image/png', () {
      expect(mimeTypeFromFilename('Screen.Png'), 'image/png');
    });
  });

  // ============================================================
  // НЕИЗВЕСТНЫЕ / НЕ РАЗРЕШЁННЫЕ
  // ============================================================

  group('неизвестные форматы', () {
    test('.webp → application/octet-stream', () {
      // В нашем списке MIME webp нет — это для иконок.
      expect(mimeTypeFromFilename('image.webp'), 'application/octet-stream');
    });

    test('.svg → application/octet-stream', () {
      expect(mimeTypeFromFilename('icon.svg'), 'application/octet-stream');
    });

    test('.zip → application/octet-stream', () {
      expect(mimeTypeFromFilename('archive.zip'), 'application/octet-stream');
    });

    test('без расширения → application/octet-stream', () {
      expect(mimeTypeFromFilename('README'), 'application/octet-stream');
    });

    test('пустая строка → application/octet-stream', () {
      expect(mimeTypeFromFilename(''), 'application/octet-stream');
    });
  });

  // ============================================================
  // ХИТРЫЕ СЛУЧАИ
  // ============================================================

  group('хитрые случаи', () {
    test('точка в имени, но расширение не наше → octet-stream', () {
      // `.gz` — не наше расширение, хотя имя длинное.
      expect(
        mimeTypeFromFilename('archive.tar.gz'),
        'application/octet-stream',
      );
    });

    test('несколько точек, последняя — наша → правильный MIME', () {
      // Смотрим только на **последнее** расширение.
      expect(mimeTypeFromFilename('договор.2026.pdf'), 'application/pdf');
    });

    test('пробелы в имени не мешают', () {
      expect(mimeTypeFromFilename('мой договор.pdf'), 'application/pdf');
    });

    test('кириллица в имени не мешает', () {
      expect(mimeTypeFromFilename('накладная №1.pdf'), 'application/pdf');
    });

    test('путь в имени — берём только расширение', () {
      expect(mimeTypeFromFilename('/tmp/photo.jpg'), 'image/jpeg');
    });

    test('Windows-путь в имени — берём только расширение', () {
      expect(
        mimeTypeFromFilename(r'C:\Users\test\file.docx'),
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      );
    });
  });
}
