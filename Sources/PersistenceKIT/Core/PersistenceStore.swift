import Foundation

public protocol PersistenceStore: Sendable {
    func prepare() async throws
    func read<Result: Sendable>(_ operation: @escaping @Sendable (ReadTransaction) throws -> Result) async throws -> Result
    func write<Result: Sendable>(_ operation: @escaping @Sendable (WriteTransaction) throws -> Result) async throws -> Result
}
