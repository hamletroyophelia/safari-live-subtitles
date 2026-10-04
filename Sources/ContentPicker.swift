import AppKit
import ScreenCaptureKit

/// System-issued, per-session capture consent also works without a persistent TCC grant.
@MainActor
final class ContentPicker: NSObject, SCContentSharingPickerObserver {
    private var pending: CheckedContinuation<SCContentFilter, Error>?
    private var observing = false

    func select(source: CaptureSource) async throws -> SCContentFilter {
        let picker = SCContentSharingPicker.shared
        var config = SCContentSharingPickerConfiguration()
        config.allowedPickerModes = source == .safari ? [.singleApplication] : [.singleDisplay]
        if source == .safari {
            config.excludedBundleIDs = Array(Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier)))
                .filter { $0 != "com.apple.Safari" }
        } else {
            config.excludedBundleIDs = [Bundle.main.bundleIdentifier ?? "local.livelingo.safari-live-subtitles"]
        }
        config.allowsChangingSelectedContent = false
        picker.defaultConfiguration = config
        picker.maximumStreamCount = 1
        if !observing { picker.add(self); observing = true }
        picker.isActive = true
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                pending = continuation
                picker.present(using: source == .safari ? .application : .display)
            }
        } onCancel: { Task { @MainActor in self.close() } }
    }

    func close() {
        pending?.resume(throwing: CancellationError())
        pending = nil
        let picker = SCContentSharingPicker.shared
        picker.isActive = false
        if observing { picker.remove(self); observing = false }
    }

    nonisolated func contentSharingPicker(_ picker: SCContentSharingPicker, didCancelFor stream: SCStream?) {
        Task { @MainActor in
            self.pending?.resume(throwing: LiveError.message("已取消声音来源选择。可以再次点击开始字幕。"))
            self.pending = nil
        }
    }
    nonisolated func contentSharingPicker(_ picker: SCContentSharingPicker, didUpdateWith filter: SCContentFilter, for stream: SCStream?) {
        Task { @MainActor in self.pending?.resume(returning: filter); self.pending = nil }
    }
    nonisolated func contentSharingPickerStartDidFailWithError(_ error: Error) {
        Task { @MainActor in self.pending?.resume(throwing: error); self.pending = nil }
    }
}
