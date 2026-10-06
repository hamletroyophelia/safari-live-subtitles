import Combine
import Foundation

/// The panel observes only what it draws, not meter, history, or model-preparation details.
struct SubtitleSnapshot: Equatable {
    let caption: Caption?
    let style: SubtitleStyle
    let targetSize: Double
    let width: Double
    let height: Double
    let automatic: Bool
    let opacity: Double
    let locked: Bool
    let running: Bool
    let preparing: Bool
    let status: String

    @MainActor init(_ model: AppModel) {
        caption = model.current; style = model.subtitleStyle; targetSize = model.fontSize
        width = model.overlayWidth; height = model.overlayHeight; automatic = model.overlayAutoHeight
        opacity = model.backgroundOpacity; locked = model.overlayLocked
        running = model.isRunning; preparing = model.isPreparing
        if model.isDemo { status = model.isTextTrial ? "词典文字试译 · 未读取音频" : "字幕预览 · 演示文字" }
        else if !model.busy { status = "字幕已停止" }
        else if preparing { status = "正在准备" }
        else if let caption {
            status = "\(model.language.title) → 中文" + (!caption.isFinal ? " · 实时更新"
                : caption.translatedSource != caption.source ? " · 正在翻译" : "")
        } else { status = "\(model.language.title) → 中文 · 等待语音" }
    }
}

@MainActor final class SubtitlePresentation: ObservableObject {
    @Published private(set) var snapshot: SubtitleSnapshot
    private var subscription: AnyCancellable?
    init(model: AppModel) {
        snapshot = SubtitleSnapshot(model)
        // Defer until @Published has changed, and merge the changes within one run-loop pass.
        subscription = model.objectWillChange
            .debounce(for: .milliseconds(0), scheduler: RunLoop.main)
            .sink { [weak self, weak model] in
                guard let self, let model else { return }
                let next = SubtitleSnapshot(model)
                if next != self.snapshot { self.snapshot = next }
            }
    }
}
