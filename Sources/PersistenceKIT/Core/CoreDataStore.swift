@preconcurrency import CoreData
import Foundation

public final class CoreDataStore: PersistenceStore, @unchecked Sendable {
    private let configuration: StoreConfiguration
    private var container: NSPersistentContainer
    private let stateLock = NSLock()
    private var preparationTask: Task<Void, Error>?
    
    public init(configuration: StoreConfiguration, bundle: Bundle = .main) throws {
        self.configuration = configuration
      
        let objectModel = try Self.objectModel(bundle: bundle, configuration: configuration)
        container = NSPersistentContainer(name: configuration.modelName, managedObjectModel: objectModel)
        
        setupStoreDescription(configuration: configuration, container: container)
    }
    
    //MARK: Prepare
    public func prepare() async throws {
        let task: Task<Void, Error> = stateLock.withLock {
            if let preparationTask { return preparationTask }
            let task = Task { [weak self] in
                guard let self else { return }
                try await self.loadPersistentStores()
            }
            preparationTask = task
            return task
        }
        
        do {
            try await task.value
        } catch {
            stateLock.withLock { preparationTask = nil }
            throw error
        }
    }
    
    //MARK: Read && Write
    public func read<Result>(_ operation: @escaping @Sendable (ReadTransaction) throws -> Result) async throws -> Result where Result : Sendable {
        try await prepare()
        
        let context = container.newBackgroundContext()
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        context.undoManager = nil
        
        return try await context.perform {
            let transaction = ReadTransaction(context: context)
            defer { transaction.finish() }
            return try operation(transaction)
        }
    }
    
    public func write<Result>(_ operation: @escaping @Sendable (WriteTransaction) throws -> Result) async throws -> Result where Result : Sendable {
        try await prepare()
        let context = container.newBackgroundContext()
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        context.undoManager = nil
        
        return try await context.perform {
            let transaction = WriteTransaction(context: context)
            defer { transaction.finish() }
            
            do {
                let result = try operation(transaction)
                if context.hasChanges {
                    try context.save()
                }
                return result
            } catch {
                context.rollback()
                throw error
            }
        }
    }
    
    
    //MARK: Private func
    private static func objectModel(bundle: Bundle, configuration: StoreConfiguration) throws -> NSManagedObjectModel{
        let modelURL = bundle.url(forResource: configuration.modelName, withExtension: "momd")
        ?? bundle.url(forResource: configuration.modelName, withExtension: "mom")
        
        guard let modelURL, let model = NSManagedObjectModel(contentsOf: modelURL) else {
            throw PersistenceError.modelNotFound(configuration.modelName)
        }
        
        return model
    }
    
    private func setupStoreDescription(configuration: StoreConfiguration, container: NSPersistentContainer) {
        let description = container.persistentStoreDescriptions.first ?? NSPersistentStoreDescription()
        description.shouldMigrateStoreAutomatically = configuration.shouldMigrateStoreAutomatically
        description.shouldInferMappingModelAutomatically = configuration.shouldInferMappingModelAutomaticaly
        
        switch configuration.kind {
        case .sqlite:
            description.type = NSSQLiteStoreType
            if let storeURL = configuration.storeURL {
                description.url = storeURL
            }
            
        case .inMemory:
            description.type = NSInMemoryStoreType
            description.url = nil
        }
        
        container.persistentStoreDescriptions = [description]
    }
    
    private func loadPersistentStores() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            container.loadPersistentStores { _, error in
                if let error {
                    continuation.resume(throwing: PersistenceError.storeLoadFailed(error.localizedDescription))
                } else {
                    continuation.resume()
                }
            }
        }
    }
}
