import AppKit
import SwiftUI

/// Explicit native drag surfaces avoid SwiftUI text swallowing window gestures.
struct PanelHandle: NSViewRepresentable {
    enum Kind { case move, resize }
    let kind: Kind
    var onResize: () -> Void = {}

    func makeNSView(context: Context) -> PanelHandleView {
        let view = PanelHandleView()
        view.kind = kind
        view.onResize = onResize
        view.setAccessibilityElement(true)
        view.setAccessibilityRole(.button)
        view.setAccessibilityLabel(kind == .move ? "拖动字幕位置" : "拖动调整字幕大小")
        return view
    }
    func updateNSView(_ view: PanelHandleView, context: Context) {
        view.kind = kind
        view.onResize = onResize
        view.needsDisplay = true
    }
}

final class PanelHandleView: NSView {
    var kind: PanelHandle.Kind = .move
    var onResize: () -> Void = {}
    private var initialMouse = NSPoint.zero
    private var initialFrame = NSRect.zero

    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func resetCursorRects() {
        addCursorRect(bounds, cursor: kind == .move ? .openHand : .crosshair)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard kind == .resize else { return }
        NSColor.white.withAlphaComponent(0.5).setStroke()
        let path = NSBezierPath()
        path.lineWidth = 1.5
        for length in [6.0, 11.0, 16.0] {
            path.move(to: NSPoint(x: bounds.maxX - length - 3, y: bounds.minY + 3))
            path.line(to: NSPoint(x: bounds.maxX - 3, y: bounds.minY + length + 3))
        }
        path.stroke()
    }

    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        initialMouse = window.convertPoint(toScreen: event.locationInWindow)
        initialFrame = window.frame
        if kind == .resize { onResize() }
        // Track the whole gesture here; an NSHostingView can otherwise claim drag events.
        while let next = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp],
                                           until: .distantFuture, inMode: .eventTracking, dequeue: true) {
            if next.type == .leftMouseUp { break }
            updateWindow(window, event: next)
        }
        if kind == .move {
            setAccessibilityValue(String(format: "位置 %.0f, %.0f", window.frame.minX, window.frame.minY))
        } else {
            setAccessibilityValue(String(format: "大小 %.0f × %.0f", window.frame.width, window.frame.height))
        }
    }

    private func updateWindow(_ window: NSWindow, event: NSEvent) {
        let mouse = window.convertPoint(toScreen: event.locationInWindow)
        if kind == .move {
            var origin = NSPoint(x: initialFrame.minX + mouse.x - initialMouse.x,
                                 y: initialFrame.minY + mouse.y - initialMouse.y)
            if let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? window.screen {
                let visible = screen.visibleFrame
                origin.x = min(max(origin.x, visible.minX), max(visible.minX, visible.maxX - window.frame.width))
                origin.y = min(max(origin.y, visible.minY), max(visible.minY, visible.maxY - window.frame.height))
            }
            window.setFrameOrigin(origin)
        } else {
            let width = max(window.minSize.width, initialFrame.width + mouse.x - initialMouse.x)
            let height = max(window.minSize.height, initialFrame.height - mouse.y + initialMouse.y)
            window.setFrame(NSRect(x: initialFrame.minX, y: initialFrame.maxY - height,
                                   width: width, height: height), display: true)
        }
    }
}
