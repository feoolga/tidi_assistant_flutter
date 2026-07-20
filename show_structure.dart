//Файл, который выводит на экран структур папкиlib
//Для запуска файла команда: dart show_structure.dart

import 'dart:io';

void main() {
  final projectRoot = Directory.current.path;
  final libPath = '$projectRoot/lib';

  print('\n📁 Структура папки lib:\n');
  print('lib/');

  if (Directory(libPath).existsSync()) {
    _printDirectory(libPath, '  ');
  } else {
    print('  ⚠️ Папка lib не найдена!');
  }

  print('\n📄 Также есть файлы в корне:');
  _printRootFiles(projectRoot);
}

void _printDirectory(String path, String prefix) {
  final dir = Directory(path);
  final items = dir.listSync();

  // Сортируем: сначала папки, потом файлы
  final folders = <FileSystemEntity>[];
  final files = <FileSystemEntity>[];

  for (var item in items) {
    if (item is Directory) {
      folders.add(item);
    } else if (item is File && item.path.endsWith('.dart')) {
      files.add(item);
    }
  }

  folders.sort((a, b) => a.path.compareTo(b.path));
  files.sort((a, b) => a.path.compareTo(b.path));

  // Показываем папки
  for (var i = 0; i < folders.length; i++) {
    final folder = folders[i];
    final isLast = i == folders.length - 1 && files.isEmpty;
    final folderName = folder.path.split('/').last;

    print('$prefix${isLast ? '└── ' : '├── '}$folderName/');
    _printDirectory(folder.path, '$prefix${isLast ? '    ' : '│   '}');
  }

  // Показываем файлы
  for (var i = 0; i < files.length; i++) {
    final file = files[i];
    final isLast = i == files.length - 1;
    final fileName = file.path.split('/').last;

    print('$prefix${isLast ? '└── ' : '├── '}$fileName');
  }
}

void _printRootFiles(String path) {
  final dir = Directory(path);
  final items = dir.listSync();

  final importantFiles = ['pubspec.yaml', 'README.md', 'analysis_options.yaml'];

  for (var item in items) {
    if (item is File) {
      final name = item.path.split('/').last;
      if (importantFiles.contains(name)) {
        print('  📄 $name');
      }
    }
  }
}
