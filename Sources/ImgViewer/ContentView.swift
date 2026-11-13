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
        .frame(minWidth: 720, minHeight: 480)
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
        VStack(spacing: 18) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 52, weight: .light))
                .foregroundStyle(Color.accentColor.opacity(0.75))
            Text("打开一个文件夹开始浏览")
                .font(.system(size: 17))
                .foregroundStyle(.secondary)
            Button {
                model.openFolderPanel()
            } label: {
                Label("打开文件夹", systemImage: "folder")
                    .font(.system(size: 15))
                    .padding(.horizontal, 8)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            if !model.recent.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("最近打开")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                    ForEach(model.recent.prefix(6), id: \.path) { url in
                        Button {
                            model.loadFolder(url)
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "folder")
                                Text(url.lastPathComponent)
                                Spacer(minLength: 12)
                                Text(url.deletingLastPathComponent().path)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            .font(.system(size: 13))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .padding(.vertical, 4)
                        .padding(.horizontal, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.primary.opacity(0.04))
                        )
                    }
                }
                .frame(width: 460)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
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
                    navigationButton(system: "chevron.left", enabled: model.canGoPrevious) {
                        model.goPrevious()
                    }
                    Spacer()
                    navigationButton(system: "chevron.right", enabled: model.canGoNext) {
                        model.goNext()
                    }
                }
                .padding(.horizontal, 14)

                if !canvas.hasImage {
                    ProgressView()
                        .controlSize(.large)
                        .padding(18)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
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

    private func navigationButton(system: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                .frame(width: 46, height: 112)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(nsColor: .controlBackgroundColor).opacity(0.92))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.black.opacity(0.12), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.25)
        .help(system.contains("left") ? "上一张" : "下一张")
    }
}

struct ViewerToolbar: View {
    @ObservedObject var model: AppModel
    @ObservedObject var canvas: CanvasState

    var body: some View {
        HStack(spacing: 10) {
            Button { canvas.zoomOut() } label: {
                Image(systemName: "minus.magnifyingglass")
            }
            .help("缩小")
            .disabled(!canvas.hasImage)

            Slider(
                value: Binding(
                    get: { logPosition },
                    set: { canvas.zoom(to: zoomValue($0)) }
                ),
                in: 0...1
            )
            .frame(width: 150)
            .disabled(!canvas.hasImage)

            Button { canvas.zoomIn() } label: {
                Image(systemName: "plus.magnifyingglass")
            }
            .help("放大")
            .disabled(!canvas.hasImage)

            Text("\(canvas.percent)%")
                .font(.system(size: 13).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 52, alignment: .leading)

            Divider().frame(height: 24)

            Button(canvas.mode == .fit ? "实际大小" : "适应窗口") {
                canvas.toggleZoom()
            }
            .disabled(!canvas.hasImage)

            Button { model.rotate(-90) } label: {
                Label("逆时针旋转", systemImage: "rotate.left")
            }
            .disabled(!canvas.hasImage)

            Button { model.rotate(90) } label: {
                Label("顺时针旋转", systemImage: "rotate.right")
            }
            .disabled(!canvas.hasImage)

            Button { model.deleteCurrent() } label: {
                Label("删除", systemImage: "trash")
            }
            .disabled(!canvas.hasImage)

            Button { model.startSlideshow() } label: {
                Label("幻灯片", systemImage: "play.rectangle")
            }
            .disabled(!canvas.hasImage)

            Spacer(minLength: 12)

            Text(model.counterText)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.borderless)
        .font(.system(size: 13))
        .padding(.horizontal, 16)
        .frame(height: 54)
        .background(
            LinearGradient(
                colors: [Color(nsColor: .windowBackgroundColor), Color(nsColor: .controlBackgroundColor)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .overlay(alignment: .top) {
            Rectangle().fill(Color.black.opacity(0.08)).frame(height: 1)
        }
    }

    private var logPosition: Double {
        let value = canvas.scale
        return log(Double(value) / 0.1) / log(80.0)
    }

    private func zoomValue(_ position: Double) -> CGFloat {
        CGFloat(0.1 * pow(80.0, position))
    }
}
