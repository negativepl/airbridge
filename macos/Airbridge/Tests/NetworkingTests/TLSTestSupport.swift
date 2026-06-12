import Foundation
@preconcurrency import Security
@testable import AirbridgeSecurity

/// Shared TLS plumbing for tests that talk to the (always-TLS) servers.
///
/// NOTE: an identical copy lives in Tests/IntegrationTests — SwiftPM test
/// targets cannot share source files without a dedicated helper target.
enum TLSTestSupport {
    /// One throwaway identity per test process. `nonisolated(unsafe)` is fine:
    /// SecIdentity is an immutable, thread-safe CF object.
    nonisolated(unsafe) static let identity: SecIdentity = {
        let storage = InMemoryStorage()
        return try! TLSIdentityManager(storage: storage).identity()
    }()
}

/// URLSession delegate that accepts any server certificate (test-only).
final class TrustAllDelegate: NSObject, URLSessionDelegate {
    func urlSession(_ session: URLSession,
                    didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        if let trust = challenge.protectionSpace.serverTrust {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }
}
