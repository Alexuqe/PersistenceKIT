# PersistenceKIT — Documentation

🇬🇧 English · [🇷🇺 Русский](Documentation.ru.md) · [← README](../README.md)

## Contents

1. [Architecture](#architecture)
2. [StoreConfiguration](#storeconfiguration)
3. [CoreDataStore and PersistenceStore](#coredatastore-and-persistencestore)
4. [Transactions](#transactions)
5. [ManagedEntity](#managedentity)
6. [Errors](#errors)
7. [Threading and Sendable](#threading-and-sendable)
8. [Migrations](#migrations)
9. [Testing](#testing)
10. [Pitfalls](#pitfalls)

## Architecture

```
PersistenceStore (protocol, Sendable)
        ▲
        │
CoreDataStore ── owns NSPersistentContainer
        │
        ├── read  { ReadTransaction  }  ── background context, no save
        └── write { WriteTransaction }  ── background context, save / rollback
```

| File | Purpose |
|---|---|
| `Core/PersistenceStore.swift` | Public protocol: `prepare`, `read`, `write` |
| `Core/CoreDataStore.swift` | Core Data implementation |
| `Core/StoreConfiguration.swift` | Store settings and `PersistentStoreKind` |
| `Core/ManagedEntity.swift` | Protocol for typed entities |
| `Core/PersistenceError.swift` | Error type |
| `Transactions/ReadTransaction.swift` | Read-only operations |
| `Transactions/WriteTransaction.swift` | Insert, fetch, delete |
| `Transactions/TransactionState.swift` | Internal "is transaction still active" flag |

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

| Parameter | Default | Meaning |
|---|---|---|
| `modelName` | — | Name of the `.xcdatamodeld`; also used as the container name |
| `kind` | `.sqlite` | `.sqlite` (persistent) or `.inMemory` (discarded on exit) |
| `storeURL` | `nil` | Custom SQLite file. If `nil`, `NSPersistentContainer` uses its default location. Ignored for `.inMemory` |
| `shouldMigrateStoreAutomatically` | `true` | Passed to `NSPersistentStoreDescription` |
| `shouldInferMappingModelAutomaticaly` | `false` | Passed to `NSPersistentStoreDescription` (enables lightweight migration inference) |

> **Spelling.** The identifiers `inMemmory(modelName:)` and `shouldInferMappingModelAutomaticaly` are spelled exactly like this in the current source (typos). Use them as written. Renaming is a public API change.

```swift
// Persistent store at a custom location
let config = StoreConfiguration(
    modelName: "AppModel",
    storeURL: URL.applicationSupportDirectory.appending(path: "app.sqlite")
)

// In-memory store (tests, previews)
let testConfig = StoreConfiguration.inMemmory(modelName: "AppModel")
```

## CoreDataStore and PersistenceStore

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

- Looks for `<modelName>.momd`, then `<modelName>.mom` in `bundle`.
- Throws `PersistenceError.modelNotFound(name)` if neither loads.
- Does **not** load the persistent store yet — that happens in `prepare()`.
- Pass `bundle: .module` when the model lives in a Swift package (for example in tests), or the framework bundle that contains it.

### `prepare()`

Loads the persistent store.

- Safe to call many times and from many tasks at once: everyone awaits the same loading task.
- If loading fails, the cached task is reset, so the next call **retries**.
- Throws `PersistenceError.storeLoadFailed(message)`.
- You don't have to call it: `read` and `write` call it first.

### `read(_:)`

```swift
let titles: [String] = try await store.read { tx in
    try tx.fetch(ItemEntity.makeFetchRequest()) { $0.name }
}
```

Creates a new background context (`mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy`, no undo manager), runs the closure on its queue, then deactivates the transaction. Nothing is saved.

### `write(_:)`

```swift
try await store.write { tx in
    let item = try tx.insert(ItemEntity.self)
    item.name = "new"
}
```

Same context setup as `read`. After the closure returns, the context is saved **only if it has changes**. If the closure or the save throws, `context.rollback()` is called and the error is rethrown. The closure may also return a value.

## Transactions

Transactions are created by the store; you only receive them inside `read` / `write` closures. After the closure ends every method throws `PersistenceError.inactiveTransaction`.

### ReadTransaction

| Method | Description |
|---|---|
| `fetch(_:map:) -> [Value]` | Executes the request and maps every entity to a `Sendable` value |
| `fetchFirst(_:map:) -> Value?` | Same, for the first match. **Sets `fetchLimit = 1` on the passed request** |
| `count(_:) -> Int` | Number of matches |
| `exists(_:) -> Bool` | `count > 0` |

### WriteTransaction

| Method | Description |
|---|---|
| `insert(_ type:) -> Entity` | Inserts a typed `ManagedEntity`; throws `invalidEntry` if the entity can't be created or cast |
| `insert(entityName:) -> NSManagedObject` | Inserts by name; throws `invalidEntry` if the model has no such entity |
| `fetch(_:) -> [Entity]` | Returns managed objects (valid only inside the closure) |
| `fetchFirst(_:) -> Entity?` | First match. **Sets `fetchLimit = 1` on the passed request** |
| `delete(_ object:)` | Deletes one object |
| `delete(_ request:)` | Fetches all matches and deletes them one by one |

> `WriteTransaction.finish()` is `public` but is called by the store. Don't call it yourself.

## ManagedEntity

```swift
public protocol ManagedEntity where Self: NSManagedObject {
    static var entityName: String { get }
}
```

Default `entityName` is `String(describing: Self.self)`. Default helper: `makeFetchRequest() -> NSFetchRequest<Self>`.

```swift
final class ItemEntity: NSManagedObject, ManagedEntity {
    @NSManaged var name: String
    static var entityName: String { "Item" } // when the model entity has a different name
}
```

## Errors

`PersistenceError` conforms to `LocalizedError`, `Sendable`, `Equatable`.

| Case | When | `errorDescription` |
|---|---|---|
| `modelNotFound(String)` | Model file not found or unreadable in the bundle | `Core Data model '<name>' was not found.` |
| `storeLoadFailed(String)` | `loadPersistentStores` returned an error | `Persistent store could not be loaded: <message>` |
| `invalidEntry(String)` | Entity name not in the model, or wrong class | `Core Data entity '<name>' is not available in the model.` |
| `inactiveTransaction` | A transaction was used after its closure ended | `The persistence transaction has already finished.` |

Core Data errors thrown by `fetch` / `save` are **not wrapped** and propagate as-is.

## Threading and Sendable

- Every transaction gets its own `newBackgroundContext()`; the closure runs on that context's queue (`context.perform`).
- `CoreDataStore` is `@unchecked Sendable`. Its only mutable state (`preparationTask`) is guarded by an `NSLock`.
- Operation closures are `@Sendable`; their return type must be `Sendable`.
- `NSManagedObject` is not `Sendable`. Convert to value types inside the closure.
- The package enables the `ApproachableConcurrency` upcoming feature.

## Migrations

By default lightweight migration is **not** inferred (`shouldInferMappingModelAutomaticaly = false`) while automatic migration is on. If you add a model version and rely on lightweight migration, set `shouldInferMappingModelAutomaticaly: true`; otherwise provide an explicit mapping model.

## Testing

```swift
import Testing
@testable import PersistenceKIT

let store = try CoreDataStore(
    configuration: .inMemmory(modelName: "TestModel"),
    bundle: .module
)
```

Run: `swift test`. Covered: missing model, write→read, invalid entity, rollback on error. Because the API is behind `PersistenceStore`, your own code can depend on the protocol and use a fake in unit tests.

## Pitfalls

| Problem | Why | What to do |
|---|---|---|
| `NSManagedObject` returned from a closure | Not `Sendable`; bound to a dead context | Map to a struct inside the closure |
| Reusing a transaction later | It is deactivated | Open a new `read`/`write` |
| Model not found in an app/test | Default `bundle` is `.main` | Pass the right bundle (`.module` in package tests) |
| Lightweight migration fails | Mapping inference is off by default | Enable `shouldInferMappingModelAutomaticaly` |
| `fetchFirst` request reused | It mutates `fetchLimit` | Create a fresh request each time |
| Large deletes are slow | Objects are fetched, then deleted individually | Not supported by the library yet (no batch delete) |
