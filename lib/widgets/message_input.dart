// lib/widgets/message_input.dart
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class MessageInput extends StatefulWidget {
  final Function(String) onSend;
  final bool isLoading;

  const MessageInput({super.key, required this.onSend, this.isLoading = false});

  @override
  State<MessageInput> createState() => _MessageInputState();
}

class _MessageInputState extends State<MessageInput> {
  final TextEditingController _controller = TextEditingController();
  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    // 👇 Добавляем слушатель на изменение текста
    _controller.addListener(_updateHasText);
    // 👇 Проверяем начальное состояние (если текст уже есть)
    _updateHasText();
  }

  @override
  void dispose() {
    _controller.removeListener(_updateHasText);
    _controller.dispose();
    super.dispose();
  }

  // 👇 Выносим обновление состояния в отдельный метод
  void _updateHasText() {
    final hasText = _controller.text.trim().isNotEmpty;
    if (_hasText != hasText) {
      setState(() {
        _hasText = hasText;
      });
    }
  }

  void _sendMessage() {
    final text = _controller.text.trim();
    if (text.isEmpty || widget.isLoading) return;

    _controller.clear();
    setState(() => _hasText = false);
    widget.onSend(text);
  }

  @override
  Widget build(BuildContext context) {
    final bool canSend = _hasText && !widget.isLoading;

    return Container(
      padding: const EdgeInsets.all(12.0),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          top: BorderSide(
            color: AppTheme.primary.withValues(alpha: 0.2),
            width: 1.0,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: Row(
          children: [
            // 📎 Кнопка прикрепления файла
            IconButton(
              onPressed: widget.isLoading ? null : () {},
              icon: Icon(
                Icons.attach_file,
                color: widget.isLoading ? Colors.grey[400] : AppTheme.primary,
                size: 24,
              ),
              tooltip: 'Прикрепить файл',
              padding: const EdgeInsets.all(8),
              constraints: const BoxConstraints(),
            ),

            // 🎙️ Кнопка микрофона
            IconButton(
              onPressed: widget.isLoading ? null : () {},
              icon: Icon(
                Icons.mic,
                color: widget.isLoading ? Colors.grey[400] : AppTheme.primary,
                size: 24,
              ),
              tooltip: 'Голосовое сообщение',
              padding: const EdgeInsets.all(8),
              constraints: const BoxConstraints(),
            ),

            const SizedBox(width: 4),

            // 📝 Поле ввода
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: AppTheme.primaryLight,
                  borderRadius: BorderRadius.circular(20.0),
                  border: Border.all(
                    color: _hasText
                        ? AppTheme.primary
                        : AppTheme.primary.withValues(alpha: 0.3),
                    width: 1.5,
                  ),
                ),
                child: TextField(
                  controller: _controller,
                  enabled: !widget.isLoading,
                  decoration: InputDecoration(
                    hintText: widget.isLoading
                        ? 'Ожидание ответа...'
                        : 'Ваше сообщение...',
                    hintStyle: TextStyle(color: Colors.grey[400], fontSize: 15),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16.0,
                      vertical: 12.0,
                    ),
                    prefixIcon: null,
                    suffixIcon: null,
                  ),
                  style: const TextStyle(
                    fontSize: 16,
                    color: AppTheme.textPrimary,
                  ),
                  onSubmitted: (_) => _sendMessage(),
                  maxLines: null,
                  minLines: 1,
                ),
              ),
            ),

            const SizedBox(width: 8),

            // 🚀 Кнопка отправки
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: canSend ? AppTheme.primary : Colors.grey[300],
              ),
              child: IconButton(
                onPressed: canSend ? _sendMessage : null,
                icon: const Icon(
                  Icons.send_rounded,
                  color: Colors.white,
                  size: 20,
                ),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
