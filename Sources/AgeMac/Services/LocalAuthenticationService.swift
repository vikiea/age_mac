import Foundation
import LocalAuthentication

enum LocalAuthenticationService {
    static func authenticate(reason: String) async throws -> Bool {
        let context = LAContext()
        var error: NSError?
        let policy: LAPolicy = .deviceOwnerAuthentication
        guard context.canEvaluatePolicy(policy, error: &error) else {
            if let error {
                throw error
            }
            return false
        }
        return try await context.evaluatePolicy(policy, localizedReason: reason)
    }
}
