import Foundation

/// Abstraction over a macOS notification suppression mechanism.
@MainActor
protocol NotificationSuppressor: AnyObject {
    var isActive: Bool { get }
    var statusDetail: String? { get }

    func suppress() async throws
    func resume() async
    func emergencyResumeSync()
}
