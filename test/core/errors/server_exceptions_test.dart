// test/core/errors/server_exceptions_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:tidi_assistant_flutter/core/errors/server_exceptions.dart';

void main() {
  group('ServerException.clientError', () {
    test('400 → сообщение о некорректном запросе', () {
      final e = ServerException.clientError(statusCode: 400);
      expect(e.userMessage, contains('Некорректный'));
      expect(e.code, 'HTTP_400');
      expect(e.statusCode, 400);
    });

    test('401 → сообщение о необходимости войти', () {
      final e = ServerException.clientError(statusCode: 401);
      expect(e.userMessage, contains('авторизован'));
    });

    test('403 → сообщение о запрете доступа', () {
      final e = ServerException.clientError(statusCode: 403);
      expect(e.userMessage, contains('Доступ запрещен'));
    });

    test('404 → сообщение о ненайденном ресурсе', () {
      final e = ServerException.clientError(statusCode: 404);
      expect(e.userMessage, contains('не найден'));
    });

    test('409 → сообщение о конфликте', () {
      final e = ServerException.clientError(statusCode: 409);
      expect(e.userMessage, contains('Конфликт'));
    });

    test('422 → сообщение о невозможности обработки', () {
      final e = ServerException.clientError(statusCode: 422);
      expect(e.userMessage, contains('обработать запрос'));
    });

    test('429 → сообщение о лимите запросов', () {
      final e = ServerException.clientError(statusCode: 429);
      expect(e.userMessage, contains('Слишком много запросов'));
    });

    test('незнакомый код → дефолтное сообщение', () {
      final e = ServerException.clientError(statusCode: 418); // I'm a teapot :)
      expect(e.userMessage, 'Ошибка запроса.');
      expect(e.code, 'HTTP_418');
    });

    test('body сохраняется в responseBody', () {
      final body = {
        'error': {'message': 'test'},
      };
      final e = ServerException.clientError(statusCode: 400, body: body);
      expect(e.responseBody, same(body));
    });
  });
}
