// test/data/models/documents_counts_dto_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:tidi_assistant_flutter/data/models/documents_counts_dto.dart';

void main() {
  group('DocumentsCountsDto.fromJson', () {
    test('парсит полный объект', () {
      final json = <String, dynamic>{
        'total': 5,
        'ready': 3,
        'failed': 1,
        'pending': 1,
      };

      final dto = DocumentsCountsDto.fromJson(json);

      expect(dto.total, 5);
      expect(dto.ready, 3);
      expect(dto.failed, 1);
      expect(dto.pending, 1);
    });

    test('пустой объект — все 0', () {
      final json = <String, dynamic>{};

      final dto = DocumentsCountsDto.fromJson(json);

      expect(dto.total, 0);
      expect(dto.ready, 0);
      expect(dto.failed, 0);
      expect(dto.pending, 0);
    });

    test('частичный объект — отсутствующие поля = 0', () {
      final json = <String, dynamic>{
        'total': 5,
        'ready': 3,
        // failed и pending отсутствуют
      };

      final dto = DocumentsCountsDto.fromJson(json);

      expect(dto.total, 5);
      expect(dto.ready, 3);
      expect(dto.failed, 0);
      expect(dto.pending, 0);
    });

    test('явный 0 парсится как 0, не как отсутствие', () {
      final json = <String, dynamic>{
        'total': 0,
        'ready': 0,
        'failed': 0,
        'pending': 0,
      };

      final dto = DocumentsCountsDto.fromJson(json);

      expect(dto.total, 0);
      expect(dto.ready, 0);
      expect(dto.failed, 0);
      expect(dto.pending, 0);
    });
  });
}
