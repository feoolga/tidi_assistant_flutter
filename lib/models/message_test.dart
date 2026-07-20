// Импортируем наш класс Message из той же папки
import 'message.dart';

void main() {
  // ============ ЧАСТЬ 1: Работа с Map ============
  print('=== Работа с Map ===');

  // Создаем Map с данными пользователя
  Map<String, dynamic> user = {
    'name': 'Анна',
    'age': 25,
    'isActive': true,
    'hobbies': ['чтение', 'программирование', 'путешествия'],
  };

  print('Имя: ${user['name']}');
  print('Возраст: ${user['age']}');
  print('Активен: ${user['isActive']}');
  print('Хобби: ${user['hobbies']}');

  // Изменяем данные
  user['age'] = 26;
  print('Новый возраст: ${user['age']}');

  // Добавляем новый ключ
  user['city'] = 'Москва';
  print('Город: ${user['city']}');

  // Проверяем наличие ключа
  if (user.containsKey('email')) {
    print('Email есть: ${user['email']}');
  } else {
    print('Email отсутствует');
  }

  // Все ключи
  print('Все ключи: ${user.keys.toList()}');

  // ============ ЧАСТЬ 2: Map для JSON ============
  print('\n=== Map для JSON ===');

  // Представь, что это данные с сервера
  Map<String, dynamic> messageJson = {
    'id': '123',
    'text': 'Привет, мир!',
    'isFromUser': false,
    'timestamp': '2024-01-15T10:30:00.000Z',
  };

  // Преобразуем JSON в Message
  final message = Message.fromJson(messageJson);
  print('Сообщение: ${message.text}');
  print('От пользователя: ${message.isFromUser}');

  // Преобразуем Message обратно в JSON
  final jsonBack = message.toJson();
  print('JSON обратно: $jsonBack');

  // ============ ПРАКТИКА С FACTORY ============
  print('=== Factory и Map вместе ===\n');

  // 1. Создаем "сырой" JSON с сервера
  Map<String, dynamic> jsonFromServer = {
    'id': '123',
    'text': 'Привет из Factory!',
    'isFromUser': true,
    'timestamp': DateTime.now().toIso8601String(),
  };

  print('1. JSON с сервера:');
  print('   $jsonFromServer\n');

  // 2. Превращаем JSON → Message (десериализация)
  Message myMessage = Message.fromJson(jsonFromServer);

  print('2. Превратили в Message:');
  print('   Текст: ${myMessage.text}');
  print('   От пользователя: ${myMessage.isFromUser}');
  print('   Время: ${myMessage.timestamp}\n');

  // 3. Меняем текст
  // (Создаем новое сообщение, не меняя старое)
  Message editedMessage = Message(
    id: myMessage.id,
    text: 'Измененный текст!',
    isFromUser: myMessage.isFromUser,
    timestamp: DateTime.now(),
  );

  print('3. Создали новое сообщение:');
  print('   Старый текст: ${myMessage.text}');
  print('   Новый текст: ${editedMessage.text}\n');

  // 4. Отправляем обратно (сериализация)
  Map<String, dynamic> jsonToServer = editedMessage.toJson();

  print('4. Отправляем на сервер:');
  print('   $jsonToServer');

  print('=== Timestamp практика ===\n');

  print('1. Создали сообщение:');
  print('   Время: ${message.timestamp}');
  print('   Локальное время: ${message.timestamp.toLocal()}');
  print('   UTC: ${message.timestamp.toUtc()}');

  // 2. Превращаем в JSON
  final json = message.toJson();
  print('\n2. В JSON:');
  print('   ${json['timestamp']}'); // строка в ISO формате

  // 3. Восстанавливаем из JSON
  final restored = Message.fromJson(json);
  print('\n3. Восстановили:');
  print('   Время: ${restored.timestamp}');

  // 4. Форматируем для показа
  print('\n4. Форматы для отображения:');
  print('   Время: ${restored.timestamp.hour}:${restored.timestamp.minute}');
  print(
    '   Дата: ${restored.timestamp.day}.${restored.timestamp.month}.${restored.timestamp.year}',
  );

  // 5. Разница во времени
  final now = DateTime.now();
  final diff = now.difference(restored.timestamp);
  print('\n5. Прошло времени:');
  print('   ${diff.inSeconds} секунд');
  print('   ${diff.inMinutes} минут');
  print('   ${diff.inHours} часов');
}
