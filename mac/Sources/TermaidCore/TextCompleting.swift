/// A model that answers a system + user prompt with its raw reply.
public protocol TextCompleting: Sendable {
    func complete(system: String, user: String) async throws -> String
}
