import SwiftUI

struct SettingsView: View {
    @ObservedObject var settingsStore: SettingsStore
    @Binding var isPresented: Bool

    var body: some View {
        TabView {
            Form {
                Section("STM32 工具链") {
                    TextField("ARM GCC 路径", text: $settingsStore.armGccPath)
                        .font(.caption)
                    TextField("OpenOCD 路径", text: $settingsStore.openocdPath)
                        .font(.caption)
                    TextField("OpenOCD 速度 (kHz)", text: $settingsStore.openocdSpeed)
                        .font(.caption)
                }

                Section("TI MSPM0 工具链") {
                    TextField("TI Arm Clang 根目录", text: $settingsStore.tiArmClangPath)
                        .font(.caption)
                    TextField("MSPM0 SDK 根目录", text: $settingsStore.mspm0SDKPath)
                        .font(.caption)
                    TextField("JLinkExe 路径", text: $settingsStore.jlinkPath)
                        .font(.caption)
                    TextField("J-Link 速度 (kHz)", text: $settingsStore.jlinkSpeed)
                        .font(.caption)
                }

                Section("行为设置") {
                    Toggle("保存最近项目", isOn: $settingsStore.saveRecentProjects)
                }

                Section {
                    Text("留空以自动检测。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding()
            .tabItem { Label("路径", systemImage: "gearshape") }

            VStack(alignment: .leading, spacing: 8) {
                Text("关于 SuperFlash")
                    .font(.headline)
                Text("版本 1.0.0")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("macOS 原生 SwiftUI 应用，一键编译烧录嵌入式项目。")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("支持 STM32F1、STM32F4（OpenOCD + ST-Link）和 TI MSPM0（J-Link + TI Arm Clang）。")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
            .tabItem { Label("关于", systemImage: "info.circle") }
        }
        .frame(width: 500, height: 400)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("完成") {
                    settingsStore.save()
                    isPresented = false
                }
            }
        }
    }
}
