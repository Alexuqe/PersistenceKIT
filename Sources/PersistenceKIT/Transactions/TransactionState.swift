final class TransactionState {
    private(set) var isActive: Bool = true
    
    func validate() throws {
        guard isActive else { throw PersistenceError.inactiveTransaction }
    }
    
    func finish() {
        isActive = false
    }
}
