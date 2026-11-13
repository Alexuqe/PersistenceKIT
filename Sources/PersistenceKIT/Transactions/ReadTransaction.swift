@preconcurrency import CoreData
import Foundation

public final class ReadTransaction {
    private let context: NSManagedObjectContext
    private let state = TransactionState()
    
    init(context: NSManagedObjectContext) {
        self.context = context
    }
    
    //MARK: Fetch
    public func fetch<Entity: NSManagedObject, Value: Sendable>(
        _ request: NSFetchRequest<Entity>,
        map: (Entity) throws -> Value
    ) throws -> [Value] {
        try state.validate()
        return try context.fetch(request).map(map)
    }
    
    public func fetchFirst<Entity: NSManagedObject, Value: Sendable>(
        _ request: NSFetchRequest<Entity>,
        map: (Entity) throws -> Value
    ) throws -> Value? {
        try state.validate()
        request.fetchLimit = 1
        return try context.fetch(request).first.map(map)
    }
    
    //MARK: Count
    public func count<Entity: NSManagedObject>(_ request: NSFetchRequest<Entity>) throws -> Int {
        try state.validate()
        return try context.count(for: request)
    }
    
    public func exists<Entity: NSManagedObject>(_ request: NSFetchRequest<Entity>) throws -> Bool {
        try count(request) > 0
    }
    
    func finish() {
        state.finish()
    }
}
