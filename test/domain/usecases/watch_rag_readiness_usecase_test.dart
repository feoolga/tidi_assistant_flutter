// test/domain/usecases/watch_rag_readiness_usecase_test.dart

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tidi_assistant_flutter/data/repositories/rag_repository.dart';
import 'package:tidi_assistant_flutter/domain/models/rag_config.dart';
import 'package:tidi_assistant_flutter/domain/models/rag_set.dart';
import 'package:tidi_assistant_flutter/domain/models/rag_status.dart';
import 'package:tidi_assistant_flutter/domain/usecases/watch_rag_readiness_usecase.dart';

class MockRagRepository extends Mock implements RagRepository {}

void main() {
  late MockRagRepository repository;
  late WatchRagReadinessUseCase useCase;

  setUp(() {
    repository = MockRagRepository();
    useCase = WatchRagReadinessUseCase(repository: repository);
  });

  /// Хелпер: собрать RagSet с заданным hasPending.
  RagSet buildSet({required bool hasPending, required String id}) {
    return RagSet(
      id: id,
      name: 'Test',
      status: hasPending ? RagStatus.ingesting : RagStatus.ready,
      documentsCounts: const DocumentsCounts(),
      config: const RagConfig(),
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
      hasPending: hasPending,
    );
  }

  // ============================================================
  // 1. HAPPY PATH: hasPending true → false
  // ============================================================

  test('hasPending: true → false — стрим эмитит два RagSet и закрывается', () {
    fakeAsync((async) {
      // Первый poll: hasPending = true.
      // Второй poll: hasPending = false.
      var callCount = 0;
      when(() => repository.get('rag-1')).thenAnswer((_) async {
        callCount++;
        if (callCount == 1) {
          return buildSet(hasPending: true, id: 'rag-1');
        }
        return buildSet(hasPending: false, id: 'rag-1');
      });

      final emitted = <RagSet>[];
      var isDone = false;

      useCase
          .execute(ragId: 'rag-1')
          .listen(emitted.add, onDone: () => isDone = true);

      // Первый poll — сразу (scheduleMicrotask). Прокручиваем микротаски.
      async.flushMicrotasks();

      // К этому моменту: первый get завершился, эмитится hasPending=true.
      expect(emitted.length, 1);
      expect(emitted.first.hasPending, isTrue);

      // Ждём следующий poll (через ragPollInterval = 5 сек).
      async.elapse(const Duration(seconds: 5));
      async.flushMicrotasks();

      // Второй get завершился, эмитится hasPending=false, стрим закрыт.
      expect(emitted.length, 2);
      expect(emitted.last.hasPending, isFalse);
      expect(isDone, isTrue);

      // Проверяем: get вызван ровно 2 раза.
      verify(() => repository.get('rag-1')).called(2);
    });
  });

  // ============================================================
  // 2. RACE CONDITION: медленный get не должен запускать второй poll
  // ============================================================

  test('медленный get (6 сек) — второй poll НЕ запускается параллельно', () {
    fakeAsync((async) {
      // get «зависает» на 6 секунд.
      when(() => repository.get('rag-1')).thenAnswer((_) async {
        await Future.delayed(const Duration(seconds: 6));
        return buildSet(hasPending: false, id: 'rag-1');
      });

      final emitted = <RagSet>[];
      useCase.execute(ragId: 'rag-1').listen(emitted.add);

      // Прокручиваем 6 секунд. За это время:
      // - poll #1 стартовал (scheduleMicrotask), ушёл в get (6 сек).
      // - Timer сработал на 5 сек → poll #2 попытался стартовать,
      //   но увидел isPolling=true и вышел.
      async.elapse(const Duration(seconds: 6));
      async.flushMicrotasks();

      // get должен быть вызван РОВНО ОДИН раз, несмотря на то,
      // что за 6 секунд Timer успел сработать (на 5-й секунде).
      verify(() => repository.get('rag-1')).called(1);

      // Стрим закрылся (hasPending=false после первого get).
      expect(emitted.length, 1);
      expect(emitted.first.hasPending, isFalse);
    });
  });
}
