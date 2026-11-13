import Testing
import Foundation
@preconcurrency import CoreData
@testable import PersistenceKIT

struct CoreDataStoreTests {
    private func makeStore() throws -> CoreDataStore {
        try CoreDataStore(configuration: .inMemmory(modelName: "TestModel"), bundle: .module)
    }

    @Test func missingModelThrows() {
        #expect(throws: PersistenceError.modelNotFound("Nope")) {
            try CoreDataStore(configuration: .inMemmory(modelName: "Nope"), bundle: .module)
        }
    }

    @Test func writeThenRead() async throws {
        let store = try makeStore()
        try await store.write { tx in
            let item = try tx.insert(entityName: "Item")
            item.setValue("hello", forKey: "name")
        }
        let names: [String] = try await store.read { tx in
            try tx.fetch(NSFetchRequest<NSManagedObject>(entityName: "Item")) {
                $0.value(forKey: "name") as? String ?? ""
            }
        }
        #expect(names == ["hello"])
    }

    @Test func invalidEntryThrows() async throws {
        let store = try makeStore()
        await #expect(throws: PersistenceError.invalidEntry("Missing")) {
            try await store.write { tx in _ = try tx.insert(entityName: "Missing") }
        }
    }

    @Test func failedWriteRollsBack() async throws {
        let store = try makeStore()
        struct Failure: Error {}
        _ = try? await store.write { tx in
            try tx.insert(entityName: "Item").setValue("x", forKey: "name")
            throw Failure()
        }
        let count = try await store.read { try $0.count(NSFetchRequest<NSManagedObject>(entityName: "Item")) }
        #expect(count == 0)
    }
}
