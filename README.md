# ТИДИ - AI Ассистент 🤖

Мобильное приложение для общения с AI-агентами. Работает на Android и Aurora OS.

## 🚀 Особенности

- 💬 Чат с AI-ассистентом
- 🎨 Стильный дизайн в стиле Тиффани
- 🔄 Поддержка нескольких AI-агентов (в разработке)
- 📱 Кроссплатформенность (Android + Aurora)

## 🛠 Технологии

- Flutter 3.32.7
- Dart
- Material 3 Design
- Provider/Riverpod (в планах)

## 📦 Установка

```bash
# 1. Клонировать репозиторий
git clone https://github.com/ваш-логин/tidi_assistant_flutter.git

# 2. Перейти в папку проекта
cd tidi_assistant_flutter

# 3. Установить зависимости
flutter pub get

# 4. Запустить приложение
flutter run
```

## 🐧 Запуск на эмуляторе Aurora OS

```bash
# Проверяем, что эмулятор жив
VBoxManage list runningvms

# Если эмулятор не запущен — стартуем (GUI режим)
VBoxManage startvm "AuroraOS-5.1.5.105-MB2" --type gui

# Для бесшумной работы в фоне
VBoxManage startvm "AuroraOS-5.1.5.105-MB2" --type headless

# Проверка SSH-соединения (опционально, для гиков)
ssh -p 2223 -i ~/AuroraOS/vmshare/ssh/private_keys/sdk defaultuser@localhost

# 3. Запуск приложения
cd ~/prog/TiDi/tidi_assistant_flutter
~/.local/opt/flutter/bin/flutter run
```
