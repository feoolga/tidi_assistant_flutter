// test/domain/utils/rag_file_utils_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:tidi_assistant_flutter/domain/utils/rag_file_utils.dart';

void main() {
  group('ragMimeTypeFromFilename', () {
    // ============================================================
    // PDF
    // ============================================================

    test('pdf в нижнем регистре → application/pdf', () {
      expect(ragMimeTypeFromFilename('договор.pdf'), 'application/pdf');
    });

    test('PDF в верхнем регистре → application/pdf', () {
      expect(ragMimeTypeFromFilename('ДОГОВОР.PDF'), 'application/pdf');
    });

    // ============================================================
    // WORD
    // ============================================================

    test('docx → wordprocessingml.document', () {
      expect(
        ragMimeTypeFromFilename('приказ.docx'),
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      );
    });

    test('doc → application/msword', () {
      expect(ragMimeTypeFromFilename('старый.doc'), 'application/msword');
    });

    // ============================================================
    // ТЕКСТОВЫЕ
    // ============================================================

    test('txt → text/plain', () {
      expect(ragMimeTypeFromFilename('заметка.txt'), 'text/plain');
    });

    test('md → text/markdown', () {
      expect(ragMimeTypeFromFilename('README.md'), 'text/markdown');
    });

    // ============================================================
    // КАРТИНКИ
    // ============================================================

    test('jpg → image/jpeg', () {
      expect(ragMimeTypeFromFilename('фото.jpg'), 'image/jpeg');
    });

    test('jpeg → image/jpeg', () {
      expect(ragMimeTypeFromFilename('фото.jpeg'), 'image/jpeg');
    });

    test('png → image/png', () {
      expect(ragMimeTypeFromFilename('скан.png'), 'image/png');
    });

    // ============================================================
    // НЕИЗВЕСТНЫЕ
    // ============================================================

    test('неизвестное расширение → octet-stream', () {
      expect(ragMimeTypeFromFilename('файл.xyz'), 'application/octet-stream');
    });

    test('без расширения → octet-stream', () {
      expect(ragMimeTypeFromFilename('файл'), 'application/octet-stream');
    });

    test('пустое имя → octet-stream', () {
      expect(ragMimeTypeFromFilename(''), 'application/octet-stream');
    });

    test('регистр расширения не важен', () {
      expect(ragMimeTypeFromFilename('ФАЙЛ.PdF'), 'application/pdf');
      expect(
        ragMimeTypeFromFilename('ФАЙЛ.DoCx'),
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      );
    });
  });

  group('isRagAllowedMimeType', () {
    // ============================================================
    // РАЗРЕШЁННЫЕ
    // ============================================================

    test('application/pdf → true', () {
      expect(isRagAllowedMimeType('application/pdf'), isTrue);
    });

    test('image/jpeg → true', () {
      expect(isRagAllowedMimeType('image/jpeg'), isTrue);
    });

    test('image/png → true', () {
      expect(isRagAllowedMimeType('image/png'), isTrue);
    });

    test('text/plain → true', () {
      expect(isRagAllowedMimeType('text/plain'), isTrue);
    });

    test('text/markdown → true', () {
      expect(isRagAllowedMimeType('text/markdown'), isTrue);
    });

    test('doc → true', () {
      expect(isRagAllowedMimeType('application/msword'), isTrue);
    });

    test('docx → true', () {
      expect(
        isRagAllowedMimeType(
          'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
        ),
        isTrue,
      );
    });

    // ============================================================
    // НЕ РАЗРЕШЁННЫЕ
    // ============================================================

    test('octet-stream → false', () {
      expect(isRagAllowedMimeType('application/octet-stream'), isFalse);
    });

    test('image/heic → false', () {
      expect(isRagAllowedMimeType('image/heic'), isFalse);
    });

    test('application/zip → false', () {
      expect(isRagAllowedMimeType('application/zip'), isFalse);
    });

    test('пустая строка → false', () {
      expect(isRagAllowedMimeType(''), isFalse);
    });
  });
}
