import Foundation

typealias Errorable = Error & LocalizedError & Sendable & Equatable

public enum PersistenceError: Errorable {
    case modelNotFound(String)
    case storeLoadFailed(String)
    case invalidEntry(String)
    case inactiveTransaction
    
    public var errorDescription: String? {
        switch self {
        case .modelNotFound(let name):      return "Core Data model '\(name)' was not found."
        case .storeLoadFailed(let message): return "Persistent store could not be loaded: \(message)"
        case .invalidEntry(let name):       return "Core Data entity '\(name)' is not available in the model."
        case .inactiveTransaction:          return "The persistence transaction has already finished."
        }
    }
}
