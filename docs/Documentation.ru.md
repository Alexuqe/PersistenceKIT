# PersistenceKIT — Документация

[🇬🇧 English](Documentation.md) · 🇷🇺 Русский · [← README](../README.ru.md)

## Содержание

1. [Архитектура](#архитектура)
2. [StoreConfiguration](#storeconfiguration)
3. [CoreDataStore и PersistenceStore](#coredatastore-и-persistencestore)
4. [Транзакции](#транзакции)
5. [ManagedEntity](#managedentity)
6. [Ошибки](#ошибки)
7. [Потоки и Sendable](#потоки-и-sendable)
8. [Миграции](#миграции)
9. [Тестирование](#тестирование)
10. [Подводные камни](#подводные-камни)

## Архитектура

```
PersistenceStore (протокол, Sendable)
        ▲
        │
CoreDataStore ── владеет NSPersistentContainer
        │
        ├── read  { ReadTransaction  }  ── фоновый контекст, без сохранения
        └── write { WriteTransaction }  ── фоновый контекст, save / rollback
```

| Файл | Назначение |
|---|---|
| `Core/PersistenceStore.swift` | Публичный протокол: `prepare`, `read`, `write` |
| `Core/CoreDataStore.swift` | Реализация на Core Data |
| `Core/StoreConfiguration.swift` | Настройки хранилища и `PersistentStoreKind` |
| `Core/ManagedEntity.swift` | Протокол для типизированных сущностей |
| `Core/PersistenceError.swift` | Тип ошибок |
| `Transactions/ReadTransaction.swift` | Операции только для чтения |
| `Transactions/WriteTransaction.swift` | Вставка, выборка, удаление |
| `Transactions/TransactionState.swift` | Внутренний флаг «транзакция ещё активна» |

## StoreConfiguration

```swift
public struct StoreConfiguration: Sendable, Equatable {
    public init(
        modelName: String,
        kind: PersistentStoreKind = .sqlite,
        storeURL: URL? = nil,
        shouldMigrateStoreAutomatically: Bool = true,
        shouldInferMappingModelAutomaticaly: Bool = false
    )

    public static func inMemmory(modelName: String) -> Self
}
```

| Параметр | По умолчанию | Значение |
|---|---|---|
| `modelName` | — | Имя `.xcdatamodeld`; также имя контейнера |
| `kind` | `.sqlite` | `.sqlite` (постоянное) или `.inMemory` (удаляется при выходе) |
| `storeURL` | `nil` | Свой SQLite-файл. Если `nil`, `NSPersistentContainer` использует расположение по умолчанию. Для `.inMemory` игнорируется |
| `shouldMigrateStoreAutomatically` | `true` | Передаётся в `NSPersistentStoreDescription` |
| `shouldInferMappingModelAutomaticaly` | `false` | Передаётся в `NSPersistentStoreDescription` (включает вывод mapping model для lightweight-миграции) |

> **Написание.** Идентификаторы `inMemmory(modelName:)` и `shouldInferMappingModelAutomaticaly` в текущем коде написаны именно так (опечатки). Используйте их как есть. Переименование — это изменение публичного API.

```swift
// SQLite в своём расположении
let config = StoreConfiguration(
    modelName: "AppModel",
    storeURL: URL.applicationSupportDirectory.appending(path: "app.sqlite")
)

// In-memory (тесты, превью)
let testConfig = StoreConfiguration.inMemmory(modelName: "AppModel")
```

## CoreDataStore и PersistenceStore

```swift
public protocol PersistenceStore: Sendable {
    func prepare() async throws
    func read<Result: Sendable>(_ operation: @escaping @Sendable (ReadTransaction) throws -> Result) async throws -> Result
    func write<Result: Sendable>(_ operation: @escaping @Sendable (WriteTransaction) throws -> Result) async throws -> Result
}
```

### `init(configuration:bundle:)`

```swift
public init(configuration: StoreConfiguration, bundle: Bundle = .main) throws
```

- Ищет в `bundle` сначала `<modelName>.momd`, затем `<modelName>.mom`.
- Бросает `PersistenceError.modelNotFound(name)`, если ни один не загрузился.
- Постоянное хранилище здесь **не** загружается — это делает `prepare()`.
- Если модель лежит в Swift-пакете (например, в тестах), передайте `bundle: .module`, либо бандл фреймворка, где она находится.

### `prepare()`

Загружает постоянное хранилище.

- Можно вызывать много раз и из многих задач одновременно: все ждут одну и ту же задачу загрузки.
- Если загрузка упала, закэшированная задача сбрасывается, и следующий вызов **повторит попытку**.
- Бросает `PersistenceError.storeLoadFailed(message)`.
- Вызывать не обязательно: `read` и `write` вызывают его первым делом.

### `read(_:)`

```swift
let titles: [String] = try await store.read { tx in
    try tx.fetch(ItemEntity.makeFetchRequest()) { $0.name }
}
```

Создаёт новый фоновый контекст (`mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy`, без undo manager), выполняет замыкание на его очереди и деактивирует транзакцию. Ничего не сохраняется.

### `write(_:)`

```swift
try await store.write { tx in
    let item = try tx.insert(ItemEntity.self)
    item.name = "new"
}
```

Контекст настраивается так же, как в `read`. После выхода из замыкания контекст сохраняется **только если есть изменения**. Если замыкание или сохранение бросает ошибку, вызывается `context.rollback()` и ошибка пробрасывается дальше. Замыкание может вернуть значение.

## Транзакции

Транзакции создаёт хранилище; вы получаете их только внутри замыканий `read` / `write`. После завершения замыкания любой метод бросает `PersistenceError.inactiveTransaction`.

### ReadTransaction

| Метод | Описание |
|---|---|
| `fetch(_:map:) -> [Value]` | Выполняет запрос и превращает каждую сущность в `Sendable`-значение |
| `fetchFirst(_:map:) -> Value?` | То же для первого совпадения. **Устанавливает `fetchLimit = 1` у переданного запроса** |
| `count(_:) -> Int` | Количество совпадений |
| `exists(_:) -> Bool` | `count > 0` |

### WriteTransaction

| Метод | Описание |
|---|---|
| `insert(_ type:) -> Entity` | Вставляет типизированный `ManagedEntity`; бросает `invalidEntry`, если сущность нельзя создать или привести к типу |
| `insert(entityName:) -> NSManagedObject` | Вставка по имени; бросает `invalidEntry`, если такой сущности нет в модели |
| `fetch(_:) -> [Entity]` | Возвращает managed-объекты (валидны только внутри замыкания) |
| `fetchFirst(_:) -> Entity?` | Первое совпадение. **Устанавливает `fetchLimit = 1` у переданного запроса** |
| `delete(_ object:)` | Удаляет один объект |
| `delete(_ request:)` | Загружает все совпадения и удаляет их по одному |

> `WriteTransaction.finish()` объявлен `public`, но его вызывает хранилище. Сами его не вызывайте.

## ManagedEntity

```swift
public protocol ManagedEntity where Self: NSManagedObject {
    static var entityName: String { get }
}
```

`entityName` по умолчанию — `String(describing: Self.self)`. Готовый помощник: `makeFetchRequest() -> NSFetchRequest<Self>`.

```swift
final class ItemEntity: NSManagedObject, ManagedEntity {
    @NSManaged var name: String
    static var entityName: String { "Item" } // если сущность в модели названа иначе
}
```

## Ошибки

`PersistenceError` реализует `LocalizedError`, `Sendable`, `Equatable`.

| Case | Когда | `errorDescription` |
|---|---|---|
| `modelNotFound(String)` | Файл модели не найден или не читается в бандле | `Core Data model '<name>' was not found.` |
| `storeLoadFailed(String)` | `loadPersistentStores` вернул ошибку | `Persistent store could not be loaded: <message>` |
| `invalidEntry(String)` | Имени сущности нет в модели, или неверный класс | `Core Data entity '<name>' is not available in the model.` |
| `inactiveTransaction` | Транзакцию использовали после завершения замыкания | `The persistence transaction has already finished.` |

Ошибки Core Data из `fetch` / `save` **не оборачиваются** и пробрасываются как есть. Тексты `errorDescription` в коде на английском.

## Потоки и Sendable

- Каждая транзакция получает свой `newBackgroundContext()`; замыкание выполняется на очереди этого контекста (`context.perform`).
- `CoreDataStore` помечен `@unchecked Sendable`. Его единственное изменяемое состояние (`preparationTask`) защищено `NSLock`.
- Замыкания операций — `@Sendable`; возвращаемый тип должен быть `Sendable`.
- `NSManagedObject` не `Sendable`. Преобразуйте в value-типы внутри замыкания.
- В пакете включена upcoming-фича `ApproachableConcurrency`.

## Миграции

По умолчанию lightweight-миграция **не** выводится автоматически (`shouldInferMappingModelAutomaticaly = false`), при этом автоматическая миграция включена. Если вы добавили версию модели и рассчитываете на lightweight-миграцию, передайте `shouldInferMappingModelAutomaticaly: true`, иначе предоставьте явную mapping model.

## Тестирование

```swift
import Testing
@testable import PersistenceKIT

let store = try CoreDataStore(
    configuration: .inMemmory(modelName: "TestModel"),
    bundle: .module
)
```

Запуск: `swift test`. Покрыто: отсутствующая модель, запись→чтение, неверная сущность, откат при ошибке. Так как API спрятан за `PersistenceStore`, ваш код может зависеть от протокола и использовать заглушку в юнит-тестах.

## Подводные камни

| Проблема | Почему | Что делать |
|---|---|---|
| `NSManagedObject` возвращён из замыкания | Не `Sendable`; привязан к уже неактуальному контексту | Преобразуйте в struct внутри замыкания |
| Повторное использование транзакции | Она деактивирована | Откройте новый `read`/`write` |
| Модель не найдена в приложении/тесте | `bundle` по умолчанию — `.main` | Передайте нужный бандл (`.module` в тестах пакета) |
| Lightweight-миграция падает | Вывод mapping model выключен по умолчанию | Включите `shouldInferMappingModelAutomaticaly` |
| Запрос для `fetchFirst` переиспользован | Он меняет `fetchLimit` | Каждый раз создавайте новый запрос |
| Большие удаления медленные | Объекты загружаются и удаляются по одному | Библиотека пока не поддерживает batch-удаление |
