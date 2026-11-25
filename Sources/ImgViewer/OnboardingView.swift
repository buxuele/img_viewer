import SwiftUI

struct OnboardingView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .overlay(Circle().stroke(Color.white.opacity(0.75), lineWidth: 1))
                Image(systemName: "lock.open.display")
                    .font(.system(size: 38, weight: .light))
                    .foregroundStyle(Color.accentColor)
            }
            .frame(width: 88, height: 88)

            Text("第一次使用，只授权一次")
                .font(.system(size: 17, weight: .semibold))

            Text("选择照片文件夹后，应用会保存这个位置的访问权限。以后打开图片不会再弹系统权限。")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)

            Button {
                model.completeOnboarding()
            } label: {
                Label("选择照片文件夹", systemImage: "folder")
                    .font(.system(size: 14, weight: .medium))
                    .padding(.horizontal, 10)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Button("以后再说") {
                model.dismissOnboarding()
            }
            .buttonStyle(.plain)
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
        }
        .padding(28)
        .frame(width: 440)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
