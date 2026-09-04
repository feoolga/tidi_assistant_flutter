// lib/widgets/typing_indicator.dart

import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Анимированный индикатор печатания — три пульсирующие точки.
///
/// Используется, когда AI генерирует ответ.
class TypingIndicator extends StatefulWidget {
  /// Цвет точек. По умолчанию — основной цвет темы (Тиффани)
  final Color color;

  /// Размер точек. По умолчанию — 8
  final double size;

  /// Задержка между появлением точек. По умолчанию — 300 мс
  final Duration delay;

  const TypingIndicator({
    super.key,
    this.color = AppTheme.primary,
    this.size = 8,
    this.delay = const Duration(milliseconds: 300),
  });

  @override
  State<TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<TypingIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late List<Animation<double>> _animations;

  @override
  void initState() {
    super.initState();

    // Создаём анимацию с бесконечным циклом
    _controller = AnimationController(
      duration: const Duration(milliseconds: 900),
      vsync: this,
    )..repeat();

    // Для каждой точки — своя анимация с задержкой
    _animations = List.generate(3, (index) {
      return CurvedAnimation(
        parent: _controller,
        curve: Interval(
          index * 0.3, // начало: 0.0, 0.3, 0.6
          index * 0.3 + 0.3, // конец: 0.3, 0.6, 0.9
          curve: Curves.easeInOut,
        ),
      );
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(3, (index) {
        return AnimatedBuilder(
          animation: _animations[index],
          builder: (context, child) {
            // Точка пульсирует от 0.3 до 1.0
            final scale = 0.3 + 0.7 * _animations[index].value;
            return Transform.scale(
              scale: scale,
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 2),
                width: widget.size,
                height: widget.size,
                decoration: BoxDecoration(
                  color: widget.color,
                  shape: BoxShape.circle,
                ),
              ),
            );
          },
        );
      }),
    );
  }
}
