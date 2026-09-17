// lib/widgets/attachment_picker_helper.dart

import 'dart:io';
import 'package:file_picker/file_picker.dart';
import '../core/config/app_config.dart';
import '../core/errors/file_exceptions.dart';
import '../core/logger/app_logger.dart';

/// Хелпер для выбора файлов через системный диалог.
///
/// Обёртка над `file_picker` — знает, какие форматы разрешены
/// (см. `AppConfig.allowedFileExtensions`), как открыть диалог,
/// и как обработать результат.
///
/// Отдельный класс, а не функция внутри виджета, — чтобы UI не знал
/// про `file_picker` напрямую. Если завтра заменим пакет или
/// добавим логику (например, проверку размера до возврата), это
/// затронет только этот файл.
class AttachmentPickerHelper {
  /// Открыть диалог выбора файла и вернуть список выбранных файлов.
  ///
  /// Возвращает пустой список, если пользователь отменил выбор.
  ///
  /// Бросает [FileException.pickFailed], если диалог не удалось открыть
  /// (ошибка платформы, нет разрешений и т.п.). Пустой список и ошибка —
  /// разные сценарии: UI показывает ошибку только во втором случае.
  static Future<List<File>> pickFiles() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        // Разрешаем выбирать по одному файлу. Если понадобится мультивыбор —
        // меняем здесь на true, остальной код не затрагивается.
        allowMultiple: false,

        // Ограничиваем диалог нашими расширениями. Если платформа
        // не поддерживает фильтр — пользователь всё равно увидит
        // все файлы, а валидация MIME/размера произойдёт в addAttachment.
        type: FileType.custom,
        allowedExtensions: AppConfig.allowedFileExtensions,

        // Не даём выбирать папки — только файлы.
        // (file_picker всё равно вернёт только файлы, но так явнее.)
      );

      // Отмена пользователем — не ошибка, тихо возвращаем пустой список.
      if (result == null || result.files.isEmpty) {
        AppLogger.debug('Выбор файла отменён пользователем');
        return const [];
      }

      // Собираем File из path. На мобильных платформах path всегда не null,
      // но проверяем на всякий случай (на web он может быть null — мы туда
      // не собираемся, но защита не помешает).
      final files = <File>[];
      for (final platformFile in result.files) {
        final path = platformFile.path;
        if (path == null || path.isEmpty) {
          AppLogger.warning(
            'file_picker вернул файл без path: ${platformFile.name}',
          );
          continue;
        }
        files.add(File(path));
      }

      AppLogger.info('Выбрано файлов: ${files.length}');
      return files;
    } catch (e, stackTrace) {
      AppLogger.logException(
        'Не удалось открыть диалог выбора файла',
        e,
        stackTrace,
      );
      throw FileException.pickFailed(e);
    }
  }
}
