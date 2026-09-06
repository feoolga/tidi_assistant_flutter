//lib/core/errors/app_exception.dart

/// Базовый класс для всех ошибок приложения.
///
/// В отличие от обычного Exception, содержит:
/// - [code] — код ошибки (для логирования и аналитики)
/// - [userMessage] — сообщение для пользователя (локализованное)
/// - [technicalDetails] — технические детали (для разработчика)
/// - [originalError] — оригинальная ошибка (если это обертка)
abstract class AppException implements Exception {
  final String code;
  final String userMessage;
  final String? technicalDetails;
  final Object? originalError;

  const AppException({
    required this.code,
    required this.userMessage,
    this.technicalDetails,
    this.originalError,
  });

  @override
  String toString() {
    return 'AppException(code: $code, message: $userMessage, details: $technicalDetails)';
  }
}
