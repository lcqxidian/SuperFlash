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
    @State private var isBusy = false
    @State private var statusMessage: String?
    @State private var showSuccessAlert = false
    @State private var createdProjectPath = ""

    private var libraryName: String { "STM32Cube\(selectedFamily)" }

    private var libraryReady: Bool {
        guard let path = libraryPath else { return false }
        return FileManager.default.fileExists(atPath: path.appendingPathComponent("Drivers/CMSIS").path)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("系列", selection: $selectedFamily) {
                        ForEach(families, id: \.name) { f in
                            Text(f.display).tag(f.name)
                        }
                    }
                    .onChange(of: selectedFamily) { _, _ in refreshLibraryPath() }
                    HStack {
                        Text("型号").foregroundColor(.secondary)
                        TextField("例 STM32F407ZG", text: $chipModel).textFieldStyle(.plain)
                    }
                } header: {
                    Label("选择芯片", systemImage: "cpu")
                }

                Section {
                    HStack {
                        Text("名称").foregroundColor(.secondary)
                        TextField("MyProject", text: $projectName).textFieldStyle(.plain)
                    }
                    HStack {
                        Text("位置").foregroundColor(.secondary)
                        if let loc = projectLocation {
                            Text(loc.path).font(.caption).foregroundColor(.secondary).lineLimit(1)
                        } else {
                            Text("未选择").font(.caption).foregroundColor(.secondary)
                        }
                        Spacer()
                        Button("浏览...") { pickLocation() }.controlSize(.small)
                    }
                } header: {
                    Label("项目信息", systemImage: "folder")
                }

                Section {
                    HStack {
                        Image(systemName: libraryReady ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                            .foregroundColor(libraryReady ? .green : .orange)
                            .font(.title3)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(libraryName).font(.callout)
                            Text(libraryReady ? "已就绪（位于桌面）" : "下载后解压到桌面，再点「选择文件夹」")
                                .font(.caption).foregroundColor(.secondary)
                        }
                        Spacer()
                        Button(libraryReady ? "重新选择" : "选择文件夹") { pickLibraryFolder() }
                            .controlSize(.small)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        let repo = families.first(where: { $0.name == selectedFamily })!.repo
                        Button("直接下载芯片包（~150MB，仅首次需要）") {
                            Task { await downloadPackage() }
                        }
                        .controlSize(.small).buttonStyle(.bordered)
                        .disabled(isBusy)
                        if isBusy {
                            HStack {
                                ProgressView().controlSize(.small)
                                Text("下载中...").font(.caption).foregroundColor(.secondary)
                            }
                        }
                        Button("在浏览器中打开 GitHub 页") {
                            NSWorkspace.shared.open(URL(string: "https://github.com/STMicroelectronics/\(repo)")!)
                        }
                        .controlSize(.small)
                    }
                    .padding(.leading, 28)
                    if let msg = statusMessage {
                        Text(msg).font(.caption).foregroundColor(msg.contains("失败") ? .red : .green)
                    }
                } header: {
                    Label("芯片支持包", systemImage: "shippingbox")
                }
            }
            .navigationTitle("新建 STM32 项目")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { isPresented = false } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("创建项目") { Task { await createProject() } }
                        .disabled(isBusy || projectName.isEmpty || projectLocation == nil || !libraryReady)
                }
            }
            .alert("项目创建成功", isPresented: $showSuccessAlert) {
                Button("打开文件夹") {
                    NSWorkspace.shared.open(URL(fileURLWithPath: createdProjectPath))
                    isPresented = false
                }
                Button("继续创建") {
                    isPresented = false
                }
            } message: {
                Text(createdProjectPath)
                    .font(.caption)
            }
            .frame(width: 520, height: 400)
            .onAppear {
                if let saved = UserDefaults.standard.string(forKey: "newProjectLocation") {
                    projectLocation = URL(fileURLWithPath: saved)
                }
                if projectLocation == nil {
                    projectLocation = URL(fileURLWithPath: NSHomeDirectory() + "/Desktop")
                }
                refreshLibraryPath()
            }
        }
    }

    private func refreshLibraryPath() {
        // 搜索常见位置
        let dirs = [
            "\(NSHomeDirectory())/Desktop/\(libraryName)",
            "\(NSHomeDirectory())/Desktop/\(libraryName)-master",
            "\(NSHomeDirectory())/Desktop/ORICO/WorkSpace/\(libraryName)",
            "\(NSHomeDirectory())/Desktop/ORICO/WorkSpace/\(libraryName)-master",
        ]
        for d in dirs {
            let url = URL(fileURLWithPath: d)
            if FileManager.default.fileExists(atPath: url.appendingPathComponent("Drivers/CMSIS").path) {
                libraryPath = url
                return
            }
        }
        libraryPath = nil
    }

    private func pickLocation() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.message = "选择项目保存位置"
        if let saved = UserDefaults.standard.string(forKey: "newProjectLocation") {
            panel.directoryURL = URL(fileURLWithPath: saved)
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        projectLocation = url
        UserDefaults.standard.set(url.path, forKey: "newProjectLocation")
    }

    private func pickLibraryFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.message = "选择 \(libraryName) 文件夹"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        libraryPath = url
    }

    @MainActor
    private func downloadPackage() async {
        let repo = families.first(where: { $0.name == selectedFamily })!.repo
        let dest = URL(fileURLWithPath: NSHomeDirectory() + "/Desktop/\(repo)")
        let zipPath = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("\(repo).zip")

        // 如果已经下载过了
        if FileManager.default.fileExists(atPath: dest.appendingPathComponent("Drivers/CMSIS").path) {
            libraryPath = dest
            return
        }

        isBusy = true
        statusMessage = "正在下载 \(repo)（约 150MB）..."
        let url = URL(string: "https://github.com/STMicroelectronics/\(repo)/archive/refs/heads/master.zip")!
        do {
            var request = URLRequest(url: url)
            request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
            let (data, _) = try await URLSession.shared.data(for: request)
            try data.write(to: zipPath)
            statusMessage = "正在解压..."
            let unzip = Process()
            unzip.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
            unzip.arguments = ["-o", zipPath.path, "-d", NSTemporaryDirectory()]
            try unzip.run()
            unzip.waitUntilExit()
            try FileManager.default.removeItem(at: zipPath)
            // 移动解压后的文件夹到桌面
            let extracted = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("\(repo)-master")
            if FileManager.default.fileExists(atPath: extracted.path) {
                try? FileManager.default.removeItem(at: dest)
                try FileManager.default.moveItem(at: extracted, to: dest)
            }
            statusMessage = "下载完成！"
            refreshLibraryPath()
        } catch {
            statusMessage = "下载失败：\(error.localizedDescription)"
        }
        isBusy = false
    }

    @MainActor
    private func createProject() async {
        guard let location = projectLocation, !projectName.isEmpty else { return }
        isBusy = true
        statusMessage = "正在创建项目..."
        let projectDir = location.appendingPathComponent(projectName)
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: projectDir.appendingPathComponent("USER"), withIntermediateDirectories: true)
            try fm.createDirectory(at: projectDir.appendingPathComponent("DRIVE/FWLib/src"), withIntermediateDirectories: true)
            try fm.createDirectory(at: projectDir.appendingPathComponent("DRIVE/FWLib/inc"), withIntermediateDirectories: true)

            // 从芯片包复制 CMSIS 头文件
            if let lib = libraryPath {
                let drivers = lib.appendingPathComponent("Drivers")
                // 复制核心头文件
                let cmsisCore = drivers.appendingPathComponent("CMSIS/Core/Include")
                if fm.fileExists(atPath: cmsisCore.path) {
                    let files = (try? fm.contentsOfDirectory(at: cmsisCore, includingPropertiesForKeys: nil)) ?? []
                    for f in files where f.lastPathComponent.hasPrefix("core_") || f.lastPathComponent.hasPrefix("cmsis_") {
                        try? fm.copyItem(atPath: f.path, toPath: projectDir.appendingPathComponent("DRIVE/CMSIS/\(f.lastPathComponent)").path)
                    }
                }
                // 搜索设备头文件目录（各芯片系列路径不同）
                let deviceST = drivers.appendingPathComponent("CMSIS/Device/ST")
                if fm.fileExists(atPath: deviceST.path) {
                    let devFamilies = (try? fm.contentsOfDirectory(at: deviceST, includingPropertiesForKeys: nil)) ?? []
                    for fam in devFamilies {
                        let inc = fam.appendingPathComponent("Include")
                        if fm.fileExists(atPath: inc.path) {
                            let files = (try? fm.contentsOfDirectory(at: inc, includingPropertiesForKeys: nil)) ?? []
                            for f in files where f.lastPathComponent.hasPrefix("stm32") || f.lastPathComponent.hasPrefix("system_stm32") {
                                try? fm.copyItem(atPath: f.path, toPath: projectDir.appendingPathComponent("DRIVE/CMSIS/\(f.lastPathComponent)").path)
                            }
                        }
                    }
                }
            }

            // main.c 模板，自动适配芯片系列
            let chipHeader = chipModel.lowercased().contains("stm32f1") ? "stm32f1xx.h" :
                             chipModel.lowercased().contains("stm32f7") ? "stm32f7xx.h" :
                             chipModel.lowercased().contains("stm32h7") ? "stm32h7xx.h" :
                             chipModel.lowercased().contains("stm32g0") ? "stm32g0xx.h" :
                             chipModel.lowercased().contains("stm32g4") ? "stm32g4xx.h" :
                             chipModel.lowercased().contains("stm32l4") ? "stm32l4xx.h" : "stm32f4xx.h"
            let template = """
            #include "\(chipHeader)"

            int main(void) {
                while (1) {
                }
            }

            void SysTick_Handler(void) {
            }

            """
            try template.write(to: URL(fileURLWithPath: projectDir.appendingPathComponent("USER/main.c").path), atomically: true, encoding: .utf8)

            createdProjectPath = projectDir.path
            isBusy = false
            showSuccessAlert = true
            return
        } catch {
            statusMessage = "创建失败：\(error.localizedDescription)"
        }
        isBusy = false
    }
}
