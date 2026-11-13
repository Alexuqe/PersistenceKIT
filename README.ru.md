# PersistenceKIT

[🇬🇧 English](README.md) · 🇷🇺 Русский

Небольшой Swift-пакет, который прячет Core Data за транзакционным API на `async/await`.
Вы не работаете с `NSManagedObjectContext` напрямую: открываете **read**- или **write**-транзакцию, выполняете работу в замыкании, а библиотека сама управляет контекстом, сохранением и откатом.

- Совместима со Swift Concurrency (`async/await`, `Sendable`)
- Отдельный фоновый контекст на каждую транзакцию
- Автосохранение при успехе, автооткат при ошибке
- Идемпотентная и потокобезопасная загрузка хранилища (`prepare()`)
- SQLite и in-memory хранилища
- Протокол `PersistenceStore` для DI и тестовых заглушек

## Требования

- Swift tools version **6.4** (см. `Package.swift`)
- Платформа Apple с Core Data. В `Package.swift` не указан `platforms`, поэтому действуют минимальные версии SwiftPM по умолчанию.
- Скомпилированная модель Core Data (`.xcdatamodeld`) в бандле

## Установка

Swift Package Manager:

```swift
dependencies: [
    .package(path: "../PersistenceKIT") // или URL вашего репозитория
],
targets: [
    .target(name: "MyApp", dependencies: ["PersistenceKIT"])
]
```

## Быстрый старт

```swift
import CoreData
import PersistenceKIT

// 1. Конфигурация
let configuration = StoreConfiguration(modelName: "AppModel")
let store: PersistenceStore = try CoreDataStore(configuration: configuration)

// 2. (Необязательно) загрузить хранилище заранее. read/write вызывают это сами.
try await store.prepare()

// 3. Запись
try await store.write { tx in
    let item = try tx.insert(entityName: "Item")
    item.setValue("hello", forKey: "name")
}

// 4. Чтение — внутри замыкания превращайте managed-объекты в Sendable-значения
let names: [String] = try await store.read { tx in
    try tx.fetch(NSFetchRequest<NSManagedObject>(entityName: "Item")) {
        $0.value(forKey: "name") as? String ?? ""
    }
}
```

### Типизированные сущности

```swift
final class ItemEntity: NSManagedObject, ManagedEntity {
    @NSManaged var name: String
}

try await store.write { tx in
    let item = try tx.insert(ItemEntity.self)
    item.name = "typed"
}

let count = try await store.read { tx in
    try tx.count(ItemEntity.makeFetchRequest())
}
```

`ManagedEntity.entityName` по умолчанию равен имени Swift-типа; переопределите его, если имя сущности в модели другое.

## Важные правила

1. **Не выпускайте `NSManagedObject` за пределы замыкания транзакции.** Преобразуйте его в value-тип и верните его. Объекты привязаны к контексту транзакции.
2. **Не храните транзакцию** (`ReadTransaction` / `WriteTransaction`) после завершения замыкания. Любое использование после этого бросает `PersistenceError.inactiveTransaction`.
3. Если замыкание записи бросает ошибку, **все изменения откатываются**.

## Документация

Полный справочник API, конфигурация, потоки и модель ошибок:

- [Documentation (English)](docs/Documentation.md)
- [Документация (Русский)](docs/Documentation.ru.md)

## Тесты

```bash
swift test
```

Тесты используют in-memory хранилище и встроенную модель `TestModel` (`Bundle.module`).

## Известные ограничения

- `viewContext` не отдаётся и наблюдения за изменениями нет; библиотека — это только транзакционный слой чтения/записи.
- Нет batch-операций: удаление по запросу сначала загружает объекты.
- `WriteTransaction.finish()` объявлен `public`, но предназначен только для внутреннего использования — не вызывайте его.
