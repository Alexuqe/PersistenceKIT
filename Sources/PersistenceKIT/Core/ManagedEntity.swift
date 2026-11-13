@preconcurrency import CoreData

public protocol ManagedEntity where Self: NSManagedObject {
    static var entityName: String { get }
}

public extension ManagedEntity {
    static var entityName: String {
        String(describing: Self.self)
    }
    
    static func makeFetchRequest() -> NSFetchRequest<Self> {
        NSFetchRequest<Self>(entityName: entityName)
    }
}
