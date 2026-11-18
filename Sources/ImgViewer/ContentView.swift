import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Group {
            if model.hasImages {
                ViewerContent(model: model)
            } else {
                EmptyLibraryView(model: model)
            }
        }
        .frame(minWidth: 680, minHeight: 500)
        .navigationTitle(model.windowTitle)
        .sheet(isPresented: $model.showingOptions) {
            OptionsView(model: model)
        }
        .sheet(isPresented: $model.showingProperties) {
            PropertiesView(model: model)
        }
        .alert(
            "提示",
            isPresented: Binding(
                get: { model.alertMessage != nil },
                set: { if !$0 { model.dismissAlert() } }
            )
        ) {
            Button("好", role: .cancel) { model.dismissAlert() }
        } message: {
            Text(model.alertMessage ?? "")
        }
    }
}

struct EmptyLibraryView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .overlay(Circle().stroke(Color.white.opacity(0.7), lineWidth: 1))
                    .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 38, weight: .light))
                    .foregroundStyle(Color.accentColor.opacity(0.9))
            }
            .frame(width: 92, height: 92)

            Text("打开一个文件夹开始浏览")
                .font(.system(size: 16))
                .foregroundStyle(.secondary)

            Button {
                model.openFolderPanel()
            } label: {
                Label("打开文件夹", systemImage: "folder")
                    .font(.system(size: 14, weight: .medium))
                    .padding(.horizontal, 10)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            if !model.recent.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("最近打开")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("清除") {
                            model.clearRecent()
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 4)
                    ForEach(model.recent.prefix(6), id: \.path) { url in
                        RecentFolderRow(url: url) {
                            model.loadFolder(url)
                        }
                    }
                }
                .frame(width: 470)
                .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.972, green: 0.98, blue: 0.988),
                    Color(red: 0.902, green: 0.925, blue: 0.947),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }
}

struct RecentFolderRow: View {
    let url: URL
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.accentColor.opacity(0.85))
                Text(url.lastPathComponent)
                    .font(.system(size: 13, weight: .medium))
                Spacer(minLength: 12)
                Text(url.deletingLastPathComponent().path)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .padding(.horizontal, 12)
            .frame(height: 36)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(hovering ? 0.92 : 0.7))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.black.opacity(hovering ? 0.1 : 0.06), lineWidth: 0.7)
            )
            .shadow(color: .black.opacity(hovering ? 0.08 : 0.04), radius: hovering ? 6 : 3, y: 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

struct ViewerContent: View {
    @ObservedObject var model: AppModel
    @ObservedObject var canvas: CanvasState

    init(model: AppModel) {
        self.model = model
        _canvas = ObservedObject(wrappedValue: model.canvas)
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                stageBackground
                ImageCanvas(
                    canvas: canvas,
                    background: model.settings.background,
                    wheelZoom: model.settings.wheelZoom,
                    doubleClickZoom: model.settings.doubleClickZoom,
                    menuEntries: model.menuEntries,
                    onMenuAction: { model.handleMenu($0) }
                )
                HStack {
                    NavigationChevron(system: "chevron.left", help: "上一张", enabled: model.canGoPrevious) {
                        model.goPrevious()
                    }
                    Spacer()
                    NavigationChevron(system: "chevron.right", help: "下一张", enabled: model.canGoNext) {
                        model.goNext()
                    }
                }
                .padding(.horizontal, 18)

                if !canvas.hasImage {
                    ProgressView()
                        .controlSize(.large)
                        .padding(20)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(Color.white.opacity(0.7), lineWidth: 0.8)
                        )
                }
            }
            ViewerToolbar(model: model, canvas: canvas)
        }
    }

    private var stageBackground: Color {
        switch model.settings.background {
        case "black": return .black
        case "gray": return Color(nsColor: NSColor(calibratedWhite: 0.34, alpha: 1))
        default: return Color(nsColor: NSColor(calibratedWhite: 0.96, alpha: 1))
        }
    }
}

struct NavigationChevron: View {
    let system: String
    let help: String
    let enabled: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Color(nsColor: .secondaryLabelColor).opacity(hovering ? 1 : 0.72))
                .frame(width: 46, height: 104)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Color.white.opacity(hovering ? 0.82 : 0.58))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(Color.black.opacity(hovering ? 0.12 : 0.08), lineWidth: 0.8)
                )
                .shadow(color: .black.opacity(hovering ? 0.18 : 0.1), radius: hovering ? 9 : 5, y: 2)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0)
        .help(help)
        .onHover { hovering = $0 }
    }
}

struct GlassToolbarButton: View {
    var title: String = ""
    var systemImage: String?
    var help: String = ""
    var enabled = true
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 13, weight: .medium))
                }
                if !title.isEmpty {
                    Text(title)
                        .font(.system(size: 13, weight: .medium))
                }
            }
            .foregroundStyle(Color(nsColor: .labelColor).opacity(enabled ? 0.9 : 0.35))
            .padding(.horizontal, title.isEmpty ? 0 : 9)
            .frame(minWidth: 32, minHeight: 30)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.white.opacity(enabled ? (hovering ? 0.94 : 0.68) : 0.3))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(Color.black.opacity(hovering && enabled ? 0.1 : 0.06), lineWidth: 0.7)
            )
            .shadow(color: .black.opacity(hovering && enabled ? 0.12 : 0.06), radius: 3, y: 1)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .help(help)
        .onHover { hovering = $0 }
    }
}

struct ViewerToolbar: View {
    @ObservedObject var model: AppModel
    @ObservedObject var canvas: CanvasState

    var body: some View {
        GeometryReader { proxy in
            content(compact: proxy.size.width < 1000)
        }
        .frame(height: 56)
        .background {
            ZStack {
                Rectangle().fill(.regularMaterial)
                LinearGradient(
                    colors: [
                        Color(red: 0.975, green: 0.982, blue: 0.99),
                        Color(red: 0.905, green: 0.933, blue: 0.955),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .opacity(0.92)
            }
        }
        .overlay(alignment: .top) {
            Rectangle().fill(Color.white.opacity(0.7)).frame(height: 0.6)
        }
    }

    private func content(compact: Bool) -> some View {
        HStack(spacing: compact ? 6 : 9) {
            GlassToolbarButton(systemImage: "minus.magnifyingglass", help: "缩小", enabled: canvas.hasImage) {
                canvas.zoomOut()
            }

            Slider(
                value: Binding(
                    get: { logPosition },
                    set: { canvas.zoom(to: zoomValue($0)) }
                ),
                in: 0...1
            )
            .frame(width: compact ? 86 : 140)
            .disabled(!canvas.hasImage)

            GlassToolbarButton(systemImage: "plus.magnifyingglass", help: "放大", enabled: canvas.hasImage) {
                canvas.zoomIn()
            }

            Text("\(canvas.percent)%")
                .font(.system(size: 12, weight: .medium).monospacedDigit())
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .frame(height: 26)
                .background(Capsule().fill(Color.white.opacity(0.62)))
                .overlay(Capsule().stroke(Color.black.opacity(0.06), lineWidth: 0.6))

            separator

            GlassToolbarButton(
                title: compact ? "" : (canvas.mode == .fit ? "实际大小" : "适应窗口"),
                systemImage: compact ? "arrow.up.left.and.arrow.down.right" : nil,
                help: "在适应窗口与实际大小之间切换",
                enabled: canvas.hasImage
            ) {
                canvas.toggleZoom()
            }

            GlassToolbarButton(
                title: compact ? "" : "逆时针旋转",
                systemImage: "rotate.left",
                help: "逆时针旋转",
                enabled: canvas.hasImage
            ) {
                model.rotate(-90)
            }

            GlassToolbarButton(
                title: compact ? "" : "顺时针旋转",
                systemImage: "rotate.right",
                help: "顺时针旋转",
                enabled: canvas.hasImage
            ) {
                model.rotate(90)
            }

            GlassToolbarButton(
                title: compact ? "" : "删除",
                systemImage: "trash",
                help: "删除",
                enabled: canvas.hasImage
            ) {
                model.deleteCurrent()
            }

            GlassToolbarButton(
                title: compact ? "" : "幻灯片",
                systemImage: "play.rectangle",
                help: "幻灯片",
                enabled: canvas.hasImage
            ) {
                model.startSlideshow()
            }

            Spacer(minLength: 6)

            Text(compact ? "\(model.index + 1)/\(model.images.count)" : model.counterText)
                .font(.system(size: 12, weight: .medium).monospacedDigit())
                .foregroundStyle(.secondary)
                .padding(.horizontal, 9)
                .frame(height: 26)
                .background(Capsule().fill(Color.white.opacity(0.38)))
                .overlay(Capsule().stroke(Color.white.opacity(0.55), lineWidth: 0.7))
        }
        .padding(.horizontal, compact ? 10 : 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var separator: some View {
        Rectangle()
            .fill(Color.black.opacity(0.08))
            .frame(width: 1, height: 22)
            .padding(.horizontal, 2)
    }

    private var logPosition: Double {
        let value = canvas.scale
        return log(Double(value) / 0.1) / log(80.0)
    }

    private func zoomValue(_ position: Double) -> CGFloat {
        CGFloat(0.1 * pow(80.0, position))
    }
}
