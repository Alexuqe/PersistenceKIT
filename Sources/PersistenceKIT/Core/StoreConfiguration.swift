import Foundation

public enum PersistentStoreKind: Sendable, Equatable {
    case sqlite
    case inMemory
}

public struct StoreConfiguration: Sendable, Equatable {
    public let modelName: String
    public let kind: PersistentStoreKind
    public let storeURL: URL?
    public let shouldMigrateStoreAutomatically: Bool
    public let shouldInferMappingModelAutomaticaly: Bool
    
    public init(
        modelName: String,
        kind: PersistentStoreKind = .sqlite,
        storeURL: URL? = nil,
        shouldMigrateStoreAutomatically: Bool = true,
        shouldInferMappingModelAutomaticaly: Bool = false
    ) {
        self.modelName = modelName
        self.kind = kind
        self.storeURL = storeURL
        self.shouldMigrateStoreAutomatically = shouldMigrateStoreAutomatically
        self.shouldInferMappingModelAutomaticaly = shouldInferMappingModelAutomaticaly
    }
    
    public static func inMemmory(modelName: String) -> Self {
        StoreConfiguration(modelName: modelName, kind: .inMemory)
    }
}
