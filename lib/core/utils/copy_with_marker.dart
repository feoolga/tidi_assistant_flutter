// lib/core/utils/copy_with_marker.dart

/// Маркер для `copyWith`-методов.
///
/// **Проблема, которую он решает.**
///
/// В immutable-моделях часто есть nullable-поля, и нужно уметь отличать
/// две ситуации:
/// - «не передали параметр» — оставить поле как было;
/// - «передали `null` явно» — сбросить поле в `null`.
///
/// С обычным `T?` это невозможно: `null` означает и «не передали»,
/// и «передали null». Решение — использовать `Object?` в сигнатуре
/// и специальный маркер в качестве дефолта:
///
/// ```dart
/// ChatSessionState copyWith({
///   Object? agentId = copyWithUnset,
/// }) {
///   return ChatSessionState(
///     agentId: isCopyWithUnset(agentId)
///         ? this.agentId
///         : agentId as String?,
///   );
/// }
/// ```
///
/// Теперь:
/// - `copyWith()` — оставит `agentId` как было;
/// - `copyWith(agentId: null)` — сбросит в `null`;
/// - `copyWith(agentId: 'epoz')` — обновит.
///
/// **Почему `const`, а не `final`.**
///
/// `identical(value, copyWithUnset)` сравнивает **по ссылке**. Если бы
/// маркер был `final`, каждый вызов `Object()` создавал бы **новый**
/// объект, и `identical` никогда бы не сработал. `const` гарантирует
/// канонизацию: на всё приложение — ровно один экземпляр.
const copyWithUnset = Object();

/// Проверяет, что значение — это [copyWithUnset].
///
/// Обёртка над `identical` — чтобы в `copyWith`-методах не писать
/// `identical(field, copyWithUnset)` каждый раз.
bool isCopyWithUnset(Object? value) => identical(value, copyWithUnset);
