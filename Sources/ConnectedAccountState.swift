import Foundation

struct ConnectedAccountReading {
    var balance: DeepSeekBalance?
    var lastSuccess: Date?
    var failure: Error?
    private var errorText: String?
    var error: String? {
        get { failure?.localizedDescription ?? errorText.map { L($0) } }
        set { failure = nil; errorText = newValue }
    }
    var refreshing = false
    var successes = 0
    private(set) var generation = 0
    mutating func begin() -> Int? {
        guard !refreshing else { return nil }
        generation += 1; refreshing = true; return generation
    }
    mutating func sourceChanged() { balance = nil; lastSuccess = nil; error = nil }
    mutating func invalidate() { generation += 1; refreshing = false; sourceChanged() }
    mutating func reconcile(with connection: CCSwitchConnection?) {
        if connection?.supportsBalance != true { invalidate() }
    }
    mutating func discoveryFailed(_ failure: Error) {
        if (failure as? ConnectedAccountError)?.isTransient != true { invalidate() }
        self.failure = failure
    }
    mutating func complete(_ result: Result<DeepSeekBalance,Error>, generation: Int) -> Bool {
        guard generation == self.generation else { return false }
        refreshing = false
        switch result {
        case .success(let value): balance = value; lastSuccess = Date(); error = nil; successes += 1
        case .failure(let failure):
            if (failure as? DeepSeekQueryError)?.sourceChanged == true { sourceChanged() }
            self.failure = failure
        }
        return true
    }
}
