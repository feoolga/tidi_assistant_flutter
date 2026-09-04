// lib/widgets/message_bubble.dart
import 'package:flutter/material.dart';
import '../domain/models/message.dart';
import '../theme/app_theme.dart';
import 'typing_indicator.dart';

class MessageBubble extends StatelessWidget {
  final Message message;
  final bool isStreaming;

  const MessageBubble({
    super.key,
    required this.message,
    this.isStreaming = false,
  });

  @override
  Widget build(BuildContext context) {
    final isFromUser = message.isFromUser;

    final bool showTypingIndicator =
        !isFromUser && message.text.isEmpty && isStreaming;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0, horizontal: 16.0),
      child: Row(
        mainAxisAlignment: isFromUser
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        children: [
          // Контейнер сообщения
          Container(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.75,
            ),
            padding: const EdgeInsets.symmetric(
              horizontal: 16.0,
              vertical: 12.0,
            ),
            decoration: BoxDecoration(
              // Цвет как в web-версии
              color: isFromUser
                  ? AppTheme
                        .primaryLight // #F2FBFA - фон пользователя
                  : Colors.white, // Белый - фон AI
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(16.0),
                topRight: const Radius.circular(16.0),
                bottomLeft: isFromUser
                    ? const Radius.circular(16.0)
                    : const Radius.circular(4.0),
                bottomRight: isFromUser
                    ? const Radius.circular(4.0)
                    : const Radius.circular(16.0),
              ),
              // Тень как в web
              boxShadow: isFromUser
                  ? [] // У пользователя нет тени
                  : [
                      BoxShadow(
                        color: Colors.grey.withValues(alpha: 0.1),
                        spreadRadius: 1,
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
              // Бордер как в web
              border: isFromUser
                  ? Border.all(
                      color: AppTheme.primary.withValues(alpha: 0.3),
                      width: 1.0,
                    )
                  : null,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // УСЛОВНЫЙ РЕНДЕРИНГ:
                // Если showTypingIndicator — показываем точки
                // Иначе — показываем текст
                if (showTypingIndicator)
                  const TypingIndicator() // ← ИСПОЛЬЗУЕМ НОВЫЙ ВИДЖЕТ
                else
                  Text(
                    message.text,
                    style: TextStyle(
                      color: isFromUser
                          ? AppTheme.textPrimary
                          : AppTheme.textPrimary,
                      fontSize: 16,
                      height: 1.4,
                    ),
                  ),
                const SizedBox(height: 4),
                // Время показываем только если есть текст
                if (!showTypingIndicator)
                  Text(
                    _formatTime(message.timestamp),
                    style: TextStyle(
                      color: isFromUser
                          ? AppTheme.textSecondary.withValues(alpha: 0.7)
                          : AppTheme.textSecondary.withValues(alpha: 0.5),
                      fontSize: 10,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }
}
