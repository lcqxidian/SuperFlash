import SwiftUI

struct SettingsView: View {
    @ObservedObject var settingsStore: SettingsStore
    @Binding var isPresented: Bool
    @State private var isDownloading = false
    @State private var downloadMessage: String?

    var body: some View {
        NavigationStack {
            List {
                // MARK: STM32 工具链
                Section {
                    HStack(spacing: 10) {
                        Image(systemName: "cube.transparent")
                            .foregroundColor(.blue)
                            .font(.title3)
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 6) {
                            pathField("ARM GCC 路径", text: $settingsStore.armGccPath, placeholder: "自动检测")
                            pathField("OpenOCD 路径", text: $settingsStore.openocdPath, placeholder: "自动检测")
                            pathField("速度 (kHz)", text: $settingsStore.openocdSpeed, placeholder: "4000")
                            HStack(spacing: 8) {
                                TextField("Flash 大小", text: $settingsStore.stm32FlashSize)
                                    .textFieldStyle(.plain)
                                    .font(.callout)
                                    .help("留空自动推导，例 0x100000")
                                TextField("RAM 大小", text: $settingsStore.stm32RamSize)
                                    .textFieldStyle(.plain)
                                    .font(.callout)
                                    .help("留空自动推导，例 0x20000")
                            }
                        }
                    }
                    .padding(.vertical, 2)
                } header: {
                    Label("STM32 工具链", systemImage: "cpu")
                }

                // MARK: TI MSPM0 工具链
                Section {
                    HStack(spacing: 10) {
                        Image(systemName: "microchip")
                            .foregroundColor(.orange)
                            .font(.title3)
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 6) {
                            pathField("TI Arm Clang 根目录", text: $settingsStore.tiArmClangPath, placeholder: "自动检测")
                            pathField("MSPM0 SDK 根目录", text: $settingsStore.mspm0SDKPath, placeholder: "自动检测")
                            pathField("JLinkExe 路径", text: $settingsStore.jlinkPath, placeholder: "自动检测")
                            pathField("速度 (kHz)", text: $settingsStore.jlinkSpeed, placeholder: "4000")
                        }
                    }
                    .padding(.vertical, 2)
                } header: {
                    Label("TI MSPM0 工具链", systemImage: "antenna.radiowaves.left.and.right")
                }

                // MARK: 通用设置
                Section {
                    HStack(spacing: 10) {
                        Image(systemName: "gearshape.2")
                            .foregroundColor(.secondary)
                            .font(.title3)
                            .frame(width: 24)
                        Toggle("启动时打开最近项目", isOn: $settingsStore.saveRecentProjects)
                            .toggleStyle(.switch)
                            .controlSize(.small)
                    }
                    .padding(.vertical, 2)
                } header: {
                    Label("通用", systemImage: "gearshape")
                }

                // MARK: 下载外设库
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 10) {
                            Image(systemName: "arrow.down.circle.fill")
                                .foregroundColor(.blue)
                                .font(.title2)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("下载 STM32F4 外设库")
                                    .font(.callout.weight(.medium))
                                Text("STM32CubeF4 V1.29.0，约 300MB，从 Gitee 镜像下载")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Button("下载") {
                                Task { await downloadStdPeriphLib() }
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            .disabled(isDownloading)

                            Button("浏览器打开") {
                                NSWorkspace.shared.open(URL(string: "https://github.com/STMicroelectronics/STM32CubeF4/tree/V1.29.0")!)
                            }
                            .buttonStyle(.borderless)
                            .controlSize(.small)
                            .foregroundColor(.accentColor)
                        }

                        if isDownloading {
                            HStack {
                                ProgressView()
                                    .controlSize(.small)
                                Text(downloadMessage ?? "正在下载...")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.leading, 34)
                        }
                        if let msg = downloadMessage {
                            Text(msg)
                                .font(.caption)
                                .foregroundColor(msg.contains("完成") ? .green : msg.contains("失败") ? .red : .secondary)
                                .padding(.leading, 34)
                        }
                    }
                    .padding(.vertical, 4)
                } header: {
                    Label("资源下载", systemImage: "square.and.arrow.down")
                }

                // MARK: 关于
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 10) {
                            Image(systemName: "sparkles")
                                .foregroundColor(.accentColor)
                                .font(.title2)
                            VStack(alignment: .leading, spacing: 1) {
                                Text("SuperFlash")
                                    .font(.callout.weight(.medium))
                                Text("版本 1.0.0")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        Text("macOS 原生 SwiftUI 应用，一键编译烧录嵌入式项目。支持 STM32（ARM GCC + OpenOCD/ST-Link）和 TI MSPM0（TI Arm Clang + J-Link/SAM-ICE）。")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.leading, 34)
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("设置")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        settingsStore.save()
                        isPresented = false
                    }
                }
            }
            .frame(width: 520, height: 540)
        }
    }

    // MARK: - 路径输入行

    @ViewBuilder
    private func pathField(_ label: String, text: Binding<String>, placeholder: String = "") -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.callout)
                .foregroundColor(.secondary)
                .frame(width: 120, alignment: .trailing)
            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .font(.callout)
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

            downloadMessage = "正在解压..."
            let unzip = Process()
            unzip.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
            unzip.arguments = ["-o", zipPath.path, "-d", dest.path]
            try unzip.run()
            unzip.waitUntilExit()

            try FileManager.default.removeItem(at: zipPath)
            downloadMessage = "完成！已保存至 \(dest.lastPathComponent)/STM32CubeF4_V1.29.0"
        } catch {
            downloadMessage = "下载失败：\(error.localizedDescription)"
        }
        isDownloading = false
    }
}
