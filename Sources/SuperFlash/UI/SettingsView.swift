import SwiftUI

struct SettingsView: View {
    @ObservedObject var settingsStore: SettingsStore
    @Binding var isPresented: Bool
    @State private var isDownloading = false
    @State private var downloadMessage: String?

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
                    TextField("Flash 大小（留空自动推导，例 0x100000）", text: $settingsStore.stm32FlashSize)
                        .font(.caption)
                    TextField("RAM 大小（留空自动推导，例 0x20000）", text: $settingsStore.stm32RamSize)
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

                Section("下载外设库") {
                    Button("下载 STM32F4 标准外设库") {
                        Task { await downloadStdPeriphLib() }
                    }
                    .font(.caption)
                    .disabled(isDownloading)
                    if isDownloading {
                        ProgressView("正在下载...")
                            .font(.caption)
                    }
                    if let dlMsg = downloadMessage {
                        Text(dlMsg)
                            .font(.caption)
                            .foregroundColor(dlMsg.contains("成功") ? .green : .secondary)
                    }
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

    // MARK: - 下载外设库

    @MainActor
    private func downloadStdPeriphLib() async {
        isDownloading = true
        downloadMessage = nil

        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.message = "选择下载目录"
        guard panel.runModal() == .OK, let dest = panel.url else {
            isDownloading = false
            return
        }

        let url = URL(string: "https://github.com/STMicroelectronics/STM32CubeF4/archive/refs/tags/V1.29.0.zip")!
        let zipPath = dest.appendingPathComponent("STM32CubeF4_V1.29.0.zip")

        do {
            downloadMessage = "正在下载 STM32CubeF4 库..."
            let (data, _) = try await URLSession.shared.data(from: url)
            try data.write(to: zipPath)
            downloadMessage = "下载完成！已保存到 \(zipPath.lastPathComponent)"
        } catch {
            downloadMessage = "下载失败：\(error.localizedDescription)"
        }
        isDownloading = false
    }
}
