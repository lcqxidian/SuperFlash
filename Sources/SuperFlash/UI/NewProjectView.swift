import SwiftUI

struct NewProjectView: View {
    @ObservedObject var settingsStore: SettingsStore
    @Binding var isPresented: Bool

    let families: [(name: String, display: String, repo: String)] = [
        ("F1", "STM32F1 (Cortex-M3)", "STM32CubeF1"),
        ("F4", "STM32F4 (Cortex-M4)", "STM32CubeF4"),
        ("F7", "STM32F7 (Cortex-M7)", "STM32CubeF7"),
        ("H7", "STM32H7 (Cortex-M7)", "STM32CubeH7"),
        ("G0", "STM32G0 (Cortex-M0+)", "STM32CubeG0"),
        ("G4", "STM32G4 (Cortex-M4)", "STM32CubeG4"),
        ("L4", "STM32L4 (Cortex-M4)", "STM32CubeL4"),
    ]

    @State private var selectedFamily = "F4"
    @State private var chipModel = "STM32F407ZG"
    @State private var projectName = ""
    @State private var projectLocation: URL?
    @State private var libraryPath: URL?
    @State private var isCreating = false
    @State private var statusMessage: String?

    private var libraryDirName: String {
        "STM32Cube\(selectedFamily)"
    }

    private var libraryDownloaded: Bool {
        guard let path = libraryPath else { return false }
        let cmsis = path.appendingPathComponent("Drivers/CMSIS")
        return FileManager.default.fileExists(atPath: cmsis.path)
    }

    var body: some View {
        NavigationStack {
            List {
                // MARK: 芯片选择
                Section {
                    Picker("系列", selection: $selectedFamily) {
                        ForEach(families, id: \.name) { f in
                            Text(f.display).tag(f.name)
                        }
                    }
                    .onChange(of: selectedFamily) { _, _ in
                        scanLibrary()
                    }

                    HStack {
                        Text("型号")
                            .foregroundColor(.secondary)
                        TextField("例 STM32F407ZG", text: $chipModel)
                            .textFieldStyle(.plain)
                            .font(.callout)
                    }
                } header: {
                    Label("选择芯片", systemImage: "cpu")
                }

                // MARK: 项目信息
                Section {
                    HStack {
                        Text("名称")
                            .foregroundColor(.secondary)
                        TextField("MyProject", text: $projectName)
                            .textFieldStyle(.plain)
                            .font(.callout)
                    }

                    HStack {
                        Text("位置")
                            .foregroundColor(.secondary)
                        if let loc = projectLocation {
                            Text(loc.path)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        } else {
                            Text("未选择")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Button("浏览...") {
                            pickLocation()
                        }
                        .controlSize(.small)
                    }
                } header: {
                    Label("项目信息", systemImage: "folder")
                }

                // MARK: 外设库
                Section {
                    HStack {
                        Image(systemName: libraryDownloaded ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundColor(libraryDownloaded ? .green : .red)
                            .font(.title3)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("STM32Cube\(selectedFamily)")
                                .font(.callout)
                            Text(libraryDownloaded ? "已就绪" : "未下载，需要先下载芯片库")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        if !libraryDownloaded {
                            Button("下载") {
                                Task { await downloadLibrary() }
                            }
                            .controlSize(.small)
                            .disabled(isCreating)
                        } else {
                            Button("重新选择") {
                                pickLibraryFolder()
                            }
                            .controlSize(.small)
                        }
                    }

                    if let msg = statusMessage {
                        Text(msg)
                            .font(.caption)
                            .foregroundColor(msg.contains("失败") ? .red : .secondary)
                    }
                } header: {
                    Label("芯片库", systemImage: "shippingbox")
                }
            }
            .navigationTitle("新建 STM32 项目")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { isPresented = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("创建项目") {
                        Task { await createProject() }
                    }
                    .disabled(isCreating || projectName.isEmpty || projectLocation == nil)
                }
            }
            .frame(width: 520, height: 440)
            .onAppear {
                scanLibrary()
                if projectLocation == nil {
                    projectLocation = URL(fileURLWithPath: NSHomeDirectory() + "/Desktop")
                }
            }
        }
    }

    // MARK: - 扫描本地库

    private func scanLibrary() {
        let libName = libraryDirName
        let candidates: [URL] = [
            URL(fileURLWithPath: NSHomeDirectory() + "/Desktop/\(libName)"),
            URL(fileURLWithPath: "/Applications/\(libName)"),
            URL(fileURLWithPath: "\(NSTemporaryDirectory())\(libName)"),
        ]
        libraryPath = candidates.first { FileManager.default.fileExists(atPath: $0.appendingPathComponent("Drivers").path) }
    }

    private func pickLibraryFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.message = "选择 STM32Cube\(selectedFamily) 文件夹"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        libraryPath = url
    }

    private func pickLocation() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.message = "选择项目保存位置"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        projectLocation = url
    }

    // MARK: - 下载库

    @MainActor
    private func downloadLibrary() async {
        isCreating = true
        statusMessage = "正在下载 STM32Cube\(selectedFamily)..."
        defer { isCreating = false }

        let repoName = families.first(where: { $0.name == selectedFamily })!.repo
        let url = URL(string: "https://github.com/STMicroelectronics/\(repoName)/archive/refs/tags/V1.29.0.zip")!
        let dest = URL(fileURLWithPath: NSHomeDirectory() + "/Desktop")
        let zipPath = dest.appendingPathComponent("\(repoName).zip")

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            try data.write(to: zipPath)

            statusMessage = "正在解压..."
            let unzip = Process()
            unzip.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
            unzip.arguments = ["-o", zipPath.path, "-d", dest.path]
            try unzip.run()
            unzip.waitUntilExit()

            try FileManager.default.removeItem(at: zipPath)

            // 找到解压后的文件夹
            let contents = try FileManager.default.contentsOfDirectory(at: dest, includingPropertiesForKeys: nil)
            if let extracted = contents.first(where: { $0.lastPathComponent.hasPrefix(repoName) && $0.pathExtension.isEmpty }) {
                libraryPath = extracted
            } else {
                libraryPath = dest
            }
            statusMessage = "下载完成！"
            scanLibrary()
        } catch {
            statusMessage = "下载失败：\(error.localizedDescription)"
        }
    }

    // MARK: - 创建项目

    @MainActor
    private func createProject() async {
        guard let location = projectLocation, !projectName.isEmpty else { return }
        isCreating = true
        statusMessage = "正在创建项目..."
        defer { isCreating = false }

        let projectDir = location.appendingPathComponent(projectName)
        let fm = FileManager.default

        do {
            // 创建目录结构
            try fm.createDirectory(at: projectDir.appendingPathComponent("USER"), withIntermediateDirectories: true)
            try fm.createDirectory(at: projectDir.appendingPathComponent("DRIVE/CMSIS"), withIntermediateDirectories: true)
            try fm.createDirectory(at: projectDir.appendingPathComponent("DRIVE/FWLib/src"), withIntermediateDirectories: true)
            try fm.createDirectory(at: projectDir.appendingPathComponent("DRIVE/FWLib/inc"), withIntermediateDirectories: true)

            // 从下载的库中复制 CMSIS 文件
            if let lib = libraryPath {
                let drivers = lib.appendingPathComponent("Drivers")
                let srcCmsis = drivers.appendingPathComponent("CMSIS")
                if fm.fileExists(atPath: srcCmsis.path) {
                    if fm.fileExists(atPath: srcCmsis.appendingPathComponent("Device")) {
                        try? fm.copyItem(at: srcCmsis.appendingPathComponent("Device"), to: projectDir.appendingPathComponent("DRIVE/CMSIS/Device"))
                    }
                    for file in try fm.contentsOfDirectory(at: srcCmsis, includingPropertiesForKeys: nil) {
                        if file.lastPathComponent.hasPrefix("core_") || file.lastPathComponent.hasPrefix("cmsis_") {
                            try? fm.copyItem(at: file, to: projectDir.appendingPathComponent("DRIVE/CMSIS/\(file.lastPathComponent)"))
                        }
                    }
                }
            }

            // 生成 main.c
            let chipUpper = chipModel.uppercased()
            let mainC = """
            #include "stm32f4xx.h"

            int main(void) {
                // TODO: 初始化代码
                while (1) {
                    // 主循环
                }
            }

            void SysTick_Handler(void) {
                // 1ms 定时器中断
            }

            """
            try mainC.write(to: projectDir.appendingPathComponent("USER/main.c"), atomically: true, encoding: .utf8)

            statusMessage = "项目已创建：\(projectDir.path)"
            isPresented = false

        } catch {
            statusMessage = "创建失败：\(error.localizedDescription)"
        }
    }
}
