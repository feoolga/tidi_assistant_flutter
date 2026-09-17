// lib/widgets/attachment_preview.dart

import 'dart:io';
import 'package:flutter/material.dart';
import '../domain/models/attachment.dart';
import '../theme/app_theme.dart';

/// Превью одного вложения.
///
/// Используется в двух местах:
/// - в `MessageInput` — над полем ввода, когда пользователь прикрепил
///   файлы, но ещё не отправил сообщение. Здесь передаётся `onRemove`,
///   чтобы можно было убрать файл до отправки.
/// - в `MessageBubble` — внутри сообщения пользователя, когда файлы
///   уже отправлены. Здесь `onRemove = null` — убрать нельзя.
///
/// Внешний вид зависит от [Attachment.kind]:
/// - `image` — миниатюра картинки;
/// - `pdf`/`other` — иконка + имя файла.
///
/// Поверх контента рисуется индикатор статуса:
/// - `pending`/`uploading`/`processing` — спиннер;
/// - `done` — ничего;
/// - `failed` — красная рамка и иконка ошибки.
class AttachmentPreview extends StatelessWidget {
  final Attachment attachment;

  /// Если передан — рисуем кнопку удаления в углу превью.
  /// Для вложений в отправленном сообщении оставляем `null`.
  final VoidCallback? onRemove;

  /// Компактный режим — для превью внутри сообщения.
  /// Обычный режим — для списка «на отправку» над полем ввода.
  final bool compact;

  const AttachmentPreview({
    super.key,
    required this.attachment,
    this.onRemove,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final size = compact ? 60.0 : 80.0;

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Основной контент: либо рамка вокруг картинки, либо карточка PDF.
          _buildContent(size),

          // Статус: спиннер во время загрузки, иконка ошибки при failed.
          if (attachment.isInProgress)
            _buildProgressOverlay(size)
          else if (attachment.isFailed)
            _buildFailedOverlay(size),

          // Кнопка удаления — только если передан колбэк.
          if (onRemove != null) _buildRemoveButton(size),
        ],
      ),
    );
  }

  // ============================================================
  // КОНТЕНТ
  // ============================================================

  Widget _buildContent(double size) {
    if (attachment.isImage) {
      return _buildImageContent(size);
    }
    return _buildFileContent(size);
  }

  Widget _buildImageContent(double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppTheme.primaryLight,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: AppTheme.primary.withValues(alpha: 0.4),
          width: 1,
        ),
        image: DecorationImage(
          image: FileImage(File(attachment.localPath)),
          fit: BoxFit.cover,
          // Если файл удалён или недоступен — молча покажем фон.
          onError: (_, __) {},
        ),
      ),
    );
  }

  Widget _buildFileContent(double size) {
    final iconSize = compact ? 20.0 : 28.0;
    final fontSize = compact ? 9.0 : 11.0;

    return Container(
      width: size,
      height: size,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppTheme.primaryLight,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: AppTheme.primary.withValues(alpha: 0.4),
          width: 1,
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            _iconForKind(attachment.kind),
            size: iconSize,
            color: AppTheme.primary,
          ),
          const SizedBox(height: 2),
          Text(
            attachment.fileName,
            style: TextStyle(fontSize: fontSize, color: AppTheme.textPrimary),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  IconData _iconForKind(AttachmentKind kind) {
    switch (kind) {
      case AttachmentKind.image:
        return Icons.image_outlined;
      case AttachmentKind.pdf:
        return Icons.picture_as_pdf_outlined;
      case AttachmentKind.other:
        return Icons.insert_drive_file_outlined;
    }
  }

  // ============================================================
  // ОВЕРЛЕИ (СПИННЕР, ОШИБКА)
  // ============================================================

  Widget _buildProgressOverlay(double size) {
    return Positioned.fill(
      child: Container(
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFailedOverlay(double size) {
    return Positioned.fill(
      child: Container(
        decoration: BoxDecoration(
          color: Colors.red.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.red, width: 1.5),
        ),
        child: const Center(
          child: Icon(Icons.error_outline, color: Colors.red, size: 24),
        ),
      ),
    );
  }

  // ============================================================
  // КНОПКА УДАЛЕНИЯ
  // ============================================================

  Widget _buildRemoveButton(double size) {
    // Кнопка чуть выходит за границы квадрата (clipBehavior: none у Stack).
    return Positioned(
      top: -6,
      right: -6,
      child: GestureDetector(
        onTap: onRemove,
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.grey.shade300),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.1),
                blurRadius: 2,
              ),
            ],
          ),
          child: const Icon(Icons.close, size: 14, color: Colors.black54),
        ),
      ),
    );
  }
}
