import SwiftUI

struct OptionsView: View {
    @ObservedObject var model: AppModel
    @State private var draft: AppSettings
    @State private var tab = 0

    init(model: AppModel) {
        self.model = model
        _draft = State(initialValue: model.settings)
    }

    var body: some View {
        VStack(spacing: 0) {
            Text("选项")
                .font(.system(size: 16, weight: .semibold))
                .padding(.top, 16)

            Picker("", selection: $tab) {
                Text("常规").tag(0)
                Text("幻灯片").tag(1)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 220)
            .padding(.top, 14)

            Group {
                if tab == 0 {
                    generalPanel
                } else {
                    slideshowPanel
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(16)

            Divider()

            HStack {
                Spacer()
                Button("取消") { model.showingOptions = false }
                    .keyboardShortcut(.cancelAction)
                Button("保存") {
                    model.apply(settings: draft)
                    model.showingOptions = false
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(12)
        }
        .frame(width: 480, height: 380)
    }

    private var generalPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("打开图片时适应窗口", isOn: $draft.fitOnOpen)
            Toggle("记住最近打开的文件夹", isOn: $draft.rememberRecent)
            Toggle("滚轮缩放图片", isOn: $draft.wheelZoom)
            Toggle("双击在适应窗口与实际大小之间切换", isOn: $draft.doubleClickZoom)
            HStack {
                Text("图片区背景")
                Picker("", selection: $draft.background) {
                    Text("浅灰").tag("light")
                    Text("深灰").tag("gray")
                    Text("黑色").tag("black")
                }
                .labelsHidden()
                .frame(width: 120)
            }
            Spacer()
        }
        .padding(14)
    }

    private var slideshowPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("每张停留")
                TextField("", value: $draft.slideshowInterval, format: .number)
                    .frame(width: 64)
                    .multilineTextAlignment(.trailing)
                Text("秒")
            }
            Toggle("循环播放", isOn: $draft.slideshowLoop)
            Toggle("随机顺序", isOn: $draft.slideshowShuffle)
            HStack {
                Text("背景主题")
                Picker("", selection: $draft.slideshowTheme) {
                    Text("黑色").tag("black")
                    Text("白色").tag("white")
                    Text("渐变").tag("gradient")
                }
                .labelsHidden()
                .frame(width: 120)
            }
            Spacer()
        }
        .padding(14)
    }
}

struct PropertiesView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("属性")
                .font(.system(size: 16, weight: .semibold))

            if let properties = model.properties {
                Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 9) {
                    row("文件名", properties.name)
                    row("位置", properties.path)
                    row("格式", properties.format)
                    row("尺寸", properties.width.flatMap { width in
                        properties.height.map { "\(width) × \($0) 像素" }
                    } ?? "无法读取")
                    row("大小", formatByteCount(properties.bytes))
                    row("修改时间", properties.modified.map {
                        DateFormatter.localizedString(from: $0, dateStyle: .medium, timeStyle: .short)
                    } ?? "未知")
                    row("旋转", "\(properties.rotation) 度")
                }
            }

            HStack {
                Spacer()
                Button("关闭") { model.showingProperties = false }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 480)
    }

    private func row(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary)
            Text(value)
                .textSelection(.enabled)
                .lineLimit(3)
                .truncationMode(.middle)
        }
    }
}
