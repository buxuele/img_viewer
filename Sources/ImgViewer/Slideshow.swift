import AppKit
import SwiftUI

@MainActor
final class SlideshowController: ObservableObject {
    static let shared = SlideshowController()

    @Published private(set) var isPaused = false

    private weak var model: AppModel?
    private var window: NSWindow?
    private var timer: Timer?
    private var order: [Int] = []
    private var position = 0

    var isRunning: Bool { window != nil }

    func start(model: AppModel) {
        stop(reloadMain: false)
        guard model.hasImages else { return }
        self.model = model
        order = makeOrder(count: model.images.count, start: model.index, shuffle: model.settings.slideshowShuffle)
        position = 0
        isPaused = false

        let frame = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        let panel = NSWindow(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.backgroundColor = .black
        panel.isOpaque = true
        panel.isReleasedWhenClosed = false
        panel.contentView = NSHostingView(rootView: SlideshowView(model: model, controller: self))
        panel.makeKeyAndOrderFront(nil)
        window = panel

        NSApp.presentationOptions = [.autoHideMenuBar, .autoHideDock]
        model.isSlideshowRunning = true
        showCurrent()
        schedule()
    }

    func stop(reloadMain: Bool = true) {
        guard window != nil else { return }
        timer?.invalidate()
        timer = nil
        window?.orderOut(nil)
        window = nil
        NSApp.presentationOptions = []
        if reloadMain {
            model?.isSlideshowRunning = false
            if let model, model.hasImages {
                model.loadCurrent(fit: true)
            }
        } else {
            model?.isSlideshowRunning = false
        }
    }

    func togglePause() {
        isPaused.toggle()
        if isPaused {
            timer?.invalidate()
            timer = nil
        } else {
            schedule()
        }
    }

    func advance(_ step: Int) {
        guard let model, !order.isEmpty else { return }
        let next = position + step
        if next >= order.count {
            guard model.settings.slideshowLoop else {
                stop()
                return
            }
            position = 0
        } else if next < 0 {
            position = order.count - 1
        } else {
            position = next
        }
        showCurrent()
    }

    private func showCurrent() {
        guard let model, order.indices.contains(position) else { return }
        model.showSlideshowImage(at: order[position])
    }

    private func schedule() {
        timer?.invalidate()
        guard let model else { return }
        let interval = TimeInterval(max(1, model.settings.slideshowInterval))
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.advance(1)
            }
        }
    }

    private func makeOrder(count: Int, start: Int, shuffle: Bool) -> [Int] {
        var indexes = Array(0..<count)
        if shuffle {
            indexes.shuffle()
        }
        if let current = indexes.firstIndex(of: start), current > 0 {
            indexes.remove(at: current)
            indexes.insert(start, at: 0)
        }
        return indexes
    }
}

struct SlideshowView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var controller: SlideshowController

    var body: some View {
        ZStack {
            background
            if let image = model.slideshowImage {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
            } else {
                ProgressView()
                    .controlSize(.large)
                    .tint(.white)
            }

            VStack {
                HStack {
                    Spacer()
                    HStack(spacing: 8) {
                        controlButton(controller.isPaused ? "继续" : "暂停") {
                            controller.togglePause()
                        }
                        controlButton("上一张") { controller.advance(-1) }
                        controlButton("下一张") { controller.advance(1) }
                        controlButton("退出") { controller.stop() }
                    }
                    .padding(14)
                }
                Spacer()
                Text("第 \(model.index + 1) 张 / 共 \(model.images.count) 张 · 空格暂停 · Esc 退出")
                    .font(.system(size: 13))
                    .foregroundStyle(themeForeground.opacity(0.75))
                    .padding(.bottom, 22)
            }
        }
        .ignoresSafeArea()
    }

    private var background: some View {
        Group {
            switch model.settings.slideshowTheme {
            case "white":
                Color.white
            case "gradient":
                LinearGradient(
                    colors: [Color(red: 0.04, green: 0.06, blue: 0.12),
                             Color(red: 0.17, green: 0.13, blue: 0.25),
                             Color(red: 0.04, green: 0.06, blue: 0.12)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            default:
                Color.black
            }
        }
    }

    private var themeForeground: Color {
        model.settings.slideshowTheme == "white" ? .black : .white
    }

    private func controlButton(_ title: String, action: @escaping () -> Void) -> some View {
        SlideshowControlButton(title: title, foreground: themeForeground, action: action)
    }
}


struct SlideshowControlButton: View {
    let title: String
    let foreground: Color
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .padding(.horizontal, 12)
                .frame(height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(foreground.opacity(hovering ? 0.22 : 0.12))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(foreground.opacity(hovering ? 0.45 : 0.25), lineWidth: 0.8)
                )
        }
        .buttonStyle(.plain)
        .foregroundStyle(foreground)
        .onHover { hovering = $0 }
    }
}
