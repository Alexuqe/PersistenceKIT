@preconcurrency import CoreData
import Foundation

public final class WriteTransaction {
    private let context: NSManagedObjectContext
    private let state = TransactionState()
    
    init(context: NSManagedObjectContext) {
        self.context = context
    }
    
    //MARK: Insert
    public func insert<Entity>(_ type: Entity.Type = Entity.self) throws -> Entity where Entity: NSManagedObject & ManagedEntity {
        try state.validate()
        
        guard let entity = NSEntityDescription
        .insertNewObject(
        forEntityName: Entity.entityName,
        into: context) as? Entity
        else {
            throw PersistenceError.invalidEntry(Entity.entityName)
        }
        
        return entity
    }
    
    public func insert(entityName: String) throws -> NSManagedObject {
        try state.validate()
        
        guard NSEntityDescription.entity(forEntityName: entityName, in: context) != nil else {
            throw PersistenceError.invalidEntry(entityName)
        }
        
        return NSEntityDescription.insertNewObject(forEntityName: entityName, into: context)
    }
    
    
    //MARK: Fetch
    public func fetch<Entity: NSManagedObject>(_ request: NSFetchRequest<Entity>) throws -> [Entity] {
        try state.validate()
        return try context.fetch(request)
    }
    
    public func fetchFirst<Entity: NSManagedObject>(_ request: NSFetchRequest<Entity>) throws -> Entity? {
        try state.validate()
        request.fetchLimit = 1
        return try context.fetch(request).first
    }
    
    //MARK: Delete
    public func delete(_ object: NSManagedObject) throws {
        try state.validate()
        context.delete(object)
    }
    
    public func delete<Entity: NSManagedObject>(_ request: NSFetchRequest<Entity>) throws {
        try state.validate()
        try context.fetch(request).forEach(context.delete)
    }
    
    //MARK: Finish
    public func finish() {
        state.finish()
    }
}
