
public enum LoadState<Value: Sendable>: Sendable {
    case idle
    case loading
    case loaded(Value)
    case failed(TAError)

    public var value: Value? {
        if case .loaded(let value) = self { return value }
        return nil
    }

    public var error: TAError? {
        if case .failed(let error) = self { return error }
        return nil
    }
}
