# PersistenceKIT

🇬🇧 English · [🇷🇺 Русский](README.ru.md)

A small Swift package that wraps Core Data behind a transaction-based, `async/await` API.
You never touch `NSManagedObjectContext` directly: you open a **read** or **write** transaction, do your work inside a closure, and the library takes care of the context, saving and rollback.

- Swift Concurrency friendly (`async/await`, `Sendable`)
- Background context per transaction
- Automatic save on success, automatic rollback on error
- Idempotent, concurrency-safe store loading (`prepare()`)
- SQLite and in-memory stores
- `PersistenceStore` protocol for DI and test doubles

## Requirements

- Swift tools version **6.4** (see `Package.swift`)
- Apple platform with Core Data. `Package.swift` does not declare `platforms`, so SwiftPM's default deployment targets apply.
- A compiled Core Data model (`.xcdatamodeld`) in a bundle

## Installation

Swift Package Manager:

```swift
dependencies: [
    .package(path: "../PersistenceKIT") // or your repository URL
],
targets: [
    .target(name: "MyApp", dependencies: ["PersistenceKIT"])
]
```

## Quick start

```swift
import CoreData
import PersistenceKIT

// 1. Configure
let configuration = StoreConfiguration(modelName: "AppModel")
let store: PersistenceStore = try CoreDataStore(configuration: configuration)

// 2. (Optional) load the store eagerly. read/write call it automatically.
try await store.prepare()

// 3. Write
try await store.write { tx in
    let item = try tx.insert(entityName: "Item")
    item.setValue("hello", forKey: "name")
}

// 4. Read — map managed objects to Sendable values inside the closure
let names: [String] = try await store.read { tx in
    try tx.fetch(NSFetchRequest<NSManagedObject>(entityName: "Item")) {
        $0.value(forKey: "name") as? String ?? ""
    }
}
```

### Typed entities

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

`ManagedEntity.entityName` defaults to the Swift type name; override it if your entity name differs.

## Important rules

1. **Never let an `NSManagedObject` leave a transaction closure.** Map it to a value type and return that. Objects are bound to the transaction's context.
2. **Never keep a transaction** (`ReadTransaction` / `WriteTransaction`) after the closure ends. Using it afterwards throws `PersistenceError.inactiveTransaction`.
3. A throwing write closure **rolls back** every change made in it.

## Documentation

Full API reference, configuration, threading and error model:

- [Documentation (English)](docs/Documentation.md)
- [Документация (Русский)](docs/Documentation.ru.md)

## Testing

```bash
swift test
```

Tests use an in-memory store and the bundled `TestModel` (`Bundle.module`).

## Known limitations

- No `viewContext` is exposed and there is no change observation; the library is a transactional read/write layer only.
- No batch operations: deleting by request fetches the objects first.
- `WriteTransaction.finish()` is `public` but is meant for internal use only — do not call it.
