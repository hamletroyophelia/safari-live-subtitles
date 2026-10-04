import AppKit
import Combine
import SwiftUI

final class SubtitlePanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class DraggableHostingView<Content: View>: NSHostingView<Content> {
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

@MainActor
final class ApplicationDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let model = AppModel()
    private var mainWindow: NSWindow!
    private var overlay: SubtitlePanel!
    private var statusItem: NSStatusItem!
    private var overlaySubscriptions = Set<AnyCancellable>()
    private var fittingOverlay = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let icon = NSImage(contentsOf: iconURL) {
            NSApplication.shared.applicationIconImage = icon
        }
        buildMenus()
        mainWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 860, height: 685),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        mainWindow.title = "双语直播字幕 · LiveLingo"
        mainWindow.titlebarAppearsTransparent = true
        mainWindow.appearance = NSAppearance(named: .darkAqua)
        mainWindow.backgroundColor = NSColor(calibratedRed: 0.075, green: 0.085, blue: 0.11, alpha: 1)
        mainWindow.contentView = NSHostingView(rootView: MainView(model: model))
        mainWindow.minSize = NSSize(width: 840, height: 690)
        mainWindow.isReleasedWhenClosed = false
        mainWindow.delegate = self
        mainWindow.center()

        overlay = SubtitlePanel(contentRect: NSRect(x: 0, y: 0, width: model.overlayWidth, height: model.overlayHeight),
                                styleMask: [.borderless, .nonactivatingPanel, .resizable],
                                backing: .buffered, defer: false)
        overlay.title = "双语悬浮字幕"
        overlay.level = .floating
        overlay.collectionBehavior = [.canJoinAllSpaces, .canJoinAllApplications, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        overlay.isOpaque = false
        overlay.backgroundColor = .clear
        overlay.hasShadow = true
        overlay.hidesOnDeactivate = false
        overlay.isMovableByWindowBackground = false
        overlay.minSize = NSSize(width: 440, height: 105)
        overlay.isReleasedWhenClosed = false
        overlay.delegate = self
        let hostingView = DraggableHostingView(rootView: OverlayView(model: model))
        hostingView.sizingOptions = []
        overlay.contentView = hostingView
        Publishers.CombineLatest4(model.$captions, model.$fontSize, model.$overlayWidth, model.$overlayAutoHeight)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.fitOverlayHeight() }
            .store(in: &overlaySubscriptions)
        let savedOrigin = model.overlayOrigin
        resetOverlayPosition()
        if let origin = savedOrigin {
            let savedFrame = NSRect(origin: origin, size: overlay.frame.size)
            if NSScreen.screens.contains(where: { $0.visibleFrame.intersection(savedFrame).width > 100 && $0.visibleFrame.intersection(savedFrame).height > 50 }) {
                overlay.setFrameOrigin(origin)
            }
        }
        model.onShowOverlay = { [weak self] in self?.overlay.orderFrontRegardless() }
        model.onHideOverlay = { [weak self] in self?.overlay.orderOut(nil) }
        model.onLockOverlay = { [weak self] locked in self?.overlay.ignoresMouseEvents = locked }
        model.onResetOverlay = { [weak self] in self?.resetOverlayPosition() }
        showMain()
        if CommandLine.arguments.contains("--demo") { model.preview() }
    }

    private func buildMenus() {
        let menu = NSMenu()
        let root = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(NSMenuItem(title: "显示双语字幕控制台", action: #selector(showMain), keyEquivalent: "1"))
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: "退出双语直播字幕", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        root.submenu = appMenu
        menu.addItem(root)
        NSApplication.shared.mainMenu = menu
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "captions.bubble", accessibilityDescription: "双语直播字幕")
        statusItem.button?.toolTip = "双语直播字幕"
        let statusMenu = NSMenu()
        for (title, action) in [
            ("打开控制台", #selector(showMain)),
            ("显示 / 隐藏悬浮字幕", #selector(toggleOverlay)),
            ("解锁字幕鼠标", #selector(unlockOverlay)),
            ("停止识别", #selector(stopCapture))
        ] {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            statusMenu.addItem(item)
        }
        statusMenu.addItem(.separator())
        statusMenu.addItem(NSMenuItem(title: "退出", action: #selector(NSApplication.terminate(_:)), keyEquivalent: ""))
        statusItem.menu = statusMenu
    }

    @objc func showMain() {
        mainWindow?.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
        model.refreshPermission()
    }
    @objc private func toggleOverlay() { model.setOverlay(visible: !model.overlayVisible) }
    @objc private func unlockOverlay() { if model.overlayLocked { model.toggleLock() } }
    @objc private func stopCapture() { model.stop() }

    private func resetOverlayPosition() {
        guard let screen = mainWindow?.screen ?? NSScreen.main else { return }
        let frame = screen.visibleFrame
        overlay.setFrameOrigin(NSPoint(x: frame.midX - overlay.frame.width / 2, y: frame.minY + 80))
    }

    private func fitOverlayHeight() {
        guard let overlay, !fittingOverlay else { return }
        overlay.minSize = NSSize(width: 440, height: max(105, ceil(model.fontSize * 2.1 + 60) + (model.current?.termNotes.isEmpty == false ? 18 : 0)))
        guard model.overlayAutoHeight else { return }
        let width = max(1, overlay.frame.width - 48)
        func textHeight(_ text: String, size: Double, weight: NSFont.Weight) -> Double {
            let font = NSFont.systemFont(ofSize: size, weight: weight)
            let bounds = (text as NSString).boundingRect(with: NSSize(width: width, height: 1000),
                options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: font])
            let lineHeight = NSLayoutManager().defaultLineHeight(for: font)
            return min(ceil(bounds.height) + 3, ceil(lineHeight * 3))
        }
        let height: Double
        if let caption = model.current {
            let source = CaptionDisplay.source(caption, width: overlay.frame.width, fontSize: model.fontSize)
            let target = caption.translation.isEmpty ? "正在翻译…" : CaptionDisplay.target(caption, width: overlay.frame.width, fontSize: model.fontSize)
            height = 62 + textHeight(source, size: model.fontSize * 0.74, weight: .medium)
                + textHeight(target, size: model.fontSize, weight: .semibold)
                + (caption.termNotes.isEmpty ? 0 : 18)
        } else {
            height = max(118, model.fontSize + 86)
        }
        var frame = overlay.frame
        let visible = (overlay.screen ?? NSScreen.main)?.visibleFrame
        let fittedHeight = min(360, max(overlay.minSize.height, ceil(height)))
        guard abs(frame.height - fittedHeight) > 1 else { return }
        frame.size.height = fittedHeight
        if let visible {
            frame.origin.y = min(max(frame.minY, visible.minY), visible.maxY - frame.height)
        }
        fittingOverlay = true
        overlay.setFrame(frame, display: true)
        model.overlayHeight = frame.height
        fittingOverlay = false
    }

    func windowDidResize(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window === overlay, !fittingOverlay else { return }
        if abs(model.overlayWidth - window.frame.width) > 1 { model.overlayWidth = window.frame.width }
        if abs(model.overlayHeight - window.frame.height) > 1 { model.overlayHeight = window.frame.height }
        model.overlayOrigin = window.frame.origin
        fitOverlayHeight()
    }

    func windowWillStartLiveResize(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window === overlay else { return }
        model.overlayAutoHeight = false
    }

    func windowDidMove(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window === overlay else { return }
        model.overlayOrigin = window.frame.origin
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showMain(); return true
    }
    func applicationWillTerminate(_ notification: Notification) {
        if let overlay {
            model.overlayOrigin = overlay.frame.origin
            model.overlayWidth = overlay.frame.width
            model.overlayHeight = overlay.frame.height
        }
        model.savePreferences()
    }
}

@main
struct LiveLingo {
    @MainActor static func main() {
        if CommandLine.arguments.contains("--diagnose") || CommandLine.arguments.contains("--transcribe-file") || CommandLine.arguments.contains("--translate-text") || CommandLine.arguments.contains("--prepare-speech") {
            Task { @MainActor in
                do { try await Diagnostics.run(arguments: CommandLine.arguments); exit(0) }
                catch { fputs("LiveLingo: \(error.localizedDescription)\n", stderr); exit(1) }
            }
            CFRunLoopRun()
        } else {
            let application = NSApplication.shared
            let delegate = ApplicationDelegate()
            application.delegate = delegate
            application.setActivationPolicy(.regular)
            withExtendedLifetime(delegate) { application.run() }
        }
    }
}
