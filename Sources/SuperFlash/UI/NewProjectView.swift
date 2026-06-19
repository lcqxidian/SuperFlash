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

    enum LibType: String, CaseIterable, Identifiable {
        case stdperiph = "标准外设库 (StdPeriph)"
        case hal      = "HAL 库"
        case ll       = "LL 库"
        case none     = "无（仅 CMSIS）"
        var id: Self { self }
    }

    @State private var selectedLib: LibType = .stdperiph

    private var libraryName: String { "STM32Cube\(selectedFamily)" }

    private func defaultModel(for family: String) -> String {
        switch family {
        case "F1": return "STM32F103C8"
        case "F4": return "STM32F407ZG"
        case "F7": return "STM32F767ZI"
        case "H7": return "STM32H743XI"
        case "G0": return "STM32G070KB"
        case "G4": return "STM32G474RE"
        case "L4": return "STM32L476RG"
        default: return "STM32F407ZG"
        }
    }

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
                    .onChange(of: selectedFamily) { _, _ in
                        chipModel = defaultModel(for: selectedFamily)
                        refreshLibraryPath()
                    }
                    HStack {
                        Text("型号").foregroundColor(.secondary)
                        Text(chipModel).font(.callout).foregroundColor(.primary)
                        Spacer()
                        Text("自动匹配").font(.caption).foregroundColor(.secondary)
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

                Section {
                    Picker("外设库", selection: $selectedLib) {
                        ForEach(LibType.allCases) { t in
                            Text(t.rawValue).tag(t)
                        }
                    }
                    Text(selectedLib == .stdperiph ? "传统 StdPeriph API（如 GPIO_Init），仅 F4 内置" :
                         selectedLib == .none ? "仅 CMSIS 头文件，寄存器操作" :
                         "从芯片包复制 HAL/LL 驱动，需已下载芯片包")
                        .font(.caption).foregroundColor(.secondary)
                } header: {
                    Label("外设驱动库", systemImage: "book")
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
                chipModel = defaultModel(for: selectedFamily)
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

    /// 用 URLSession download API 下载到文件，系统级下载更可靠。
    private func downloadToFile(request: URLRequest, to zipPath: URL) async throws {
        let fm = FileManager.default
        let (tempURL, response) = try await URLSession.shared.download(for: request)

        guard let httpResp = response as? HTTPURLResponse else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "非 HTTP 响应"])
        }
        guard httpResp.statusCode == 200 else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "HTTP \(httpResp.statusCode)"])
        }

        try? fm.removeItem(at: zipPath)
        try fm.moveItem(at: tempURL, to: zipPath)

        // 用 unzip -t 校验 ZIP 完整性（不解压，只测试）
        let test = Process()
        test.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        test.arguments = ["-tq", zipPath.path]
        try test.run()
        test.waitUntilExit()
        guard test.terminationStatus == 0 else {
            let size = (try? fm.attributesOfItem(atPath: zipPath.path))?[.size] as? Int64 ?? 0
            try? fm.removeItem(at: zipPath)
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "ZIP 校验失败（\(size/1_000_000)MB，下载不完整）"])
        }
    }

    /// 尝试从一组 URL 下载芯片包，直到成功或全部失败
    @MainActor
    private func downloadFromURLs(_ urls: [URL], repoName: String, tmp: URL) async throws {
        let fm = FileManager.default
        var lastError: Error?

        for (i, url) in urls.enumerated() {
            statusMessage = "正在下载（尝试 \(i+1)/\(urls.count)）..."
            var request = URLRequest(url: url)
            request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
            request.setValue("application/zip,application/octet-stream,*/*", forHTTPHeaderField: "Accept")
            request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData

            let zipPath = tmp.appendingPathComponent("\(repoName).zip")
            do {
                try await downloadToFile(request: request, to: zipPath)
                return // 成功
            } catch {
                lastError = error
                try? fm.removeItem(at: zipPath)
                continue
            }
        }
        throw lastError ?? NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "所有下载地址均失败"])
    }

    @MainActor
    private func downloadPackage() async {
        let repoName = families.first(where: { $0.name == selectedFamily })!.repo
        let dest = URL(fileURLWithPath: NSHomeDirectory() + "/Desktop/\(repoName)")
        let zipDest = URL(fileURLWithPath: NSHomeDirectory() + "/Desktop/\(repoName).zip")
        let tmp = URL(fileURLWithPath: "/tmp/superflash_dl")
        let fm = FileManager.default

        // 如果已经解压好了
        if fm.fileExists(atPath: dest.appendingPathComponent("Drivers/CMSIS").path) { libraryPath = dest; return }
        // 如果 zip 已经存在，提示解压
        if fm.fileExists(atPath: zipDest.path) {
            statusMessage = "\(repoName).zip 已存在，解压到桌面后点击「选择文件夹」"
            isBusy = false; return
        }

        isBusy = true
        statusMessage = "正在下载 \(repoName)..."

        let base = "https://github.com/STMicroelectronics/\(repoName)"
        let urls = [
            URL(string: "\(base)/archive/refs/heads/master.zip")!,
            URL(string: "\(base)/archive/master.zip")!,
            URL(string: "\(base)/archive/refs/heads/main.zip")!,
        ]

        do {
            // 下载到 tmp，最多重试 3 次
            var lastError: Error?
            for attempt in 1...3 {
                if attempt > 1 {
                    statusMessage = "重试中（第 \(attempt)/3 次）..."
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                }
                do {
                    // 清理 tmp
                    try? fm.removeItem(at: tmp)
                    try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
                    // 下载
                    try await downloadFromURLs(urls, repoName: repoName, tmp: tmp)
                    lastError = nil; break
                } catch {
                    lastError = error
                }
            }
            if let err = lastError { throw err }

            // 确认 zip 文件有效
            let zipPath = tmp.appendingPathComponent("\(repoName).zip")
            let attrs = try fm.attributesOfItem(atPath: zipPath.path)
            let fileSize = (attrs[.size] as? Int64) ?? 0
            guard fileSize > 1_000_000 else {
                throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "下载文件过小（\(fileSize/1_000_000)MB），请检查网络后重试"])
            }

            // 复制到桌面
            try? fm.removeItem(at: zipDest)
            try fm.copyItem(at: zipPath, to: zipDest)
            try? fm.removeItem(at: tmp)

            libraryPath = nil
            statusMessage = "已下载到桌面 \(repoName).zip，请解压后点击「选择文件夹」"

        } catch {
            statusMessage = "下载失败：\(error.localizedDescription)"
        }
        isBusy = false
    }

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
            try fm.createDirectory(at: projectDir.appendingPathComponent("DRIVE/CMSIS"), withIntermediateDirectories: true)

            // 从芯片包复制 CMSIS 头文件
            if let lib = libraryPath {
                let drivers = lib.appendingPathComponent("Drivers")
                // 复制 CMSIS Core 头文件（全部）
                let cmsisCore = drivers.appendingPathComponent("CMSIS/Core/Include")
                if fm.fileExists(atPath: cmsisCore.path) {
                    let files = (try? fm.contentsOfDirectory(at: cmsisCore, includingPropertiesForKeys: nil)) ?? []
                    for f in files {
                        try? fm.copyItem(atPath: f.path, toPath: projectDir.appendingPathComponent("DRIVE/CMSIS/\(f.lastPathComponent)").path)
                    }
                }
                // 搜索芯片包中的系统文件 + 设备头文件
                let family = chipModel.replacingOccurrences(of: "STM32", with: "").dropLast(4).lowercased()
                let sysBase = "stm32\(family)xx"
                let sysFiles = (try? fm.subpathsOfDirectory(atPath: lib.path).filter {
                    $0.hasSuffix("/system_\(sysBase).c") || $0.hasSuffix("/\(sysBase).h")
                }) ?? []
                for sf in sysFiles {
                    let name = URL(fileURLWithPath: sf).lastPathComponent
                    try? fm.copyItem(atPath: lib.appendingPathComponent(sf).path,
                                     toPath: projectDir.appendingPathComponent("DRIVE/CMSIS/\(name)").path)
                }
            }

            // 如果设备头文件没复制到，用内置的系列特定文件
            let familyMap = ["f1":"CMSIS_F1", "f4":"CMSIS", "f7":"CMSIS_F7", "h7":"CMSIS_H7"]
            let chipLower = chipModel.lowercased()
            for (key, bundleDir) in familyMap {
                if chipLower.contains("stm32\(key)") {
                    if let src = Bundle.main.resourceURL?.appendingPathComponent(bundleDir) {
                        let files = (try? fm.contentsOfDirectory(at: src, includingPropertiesForKeys: nil)) ?? []
                        for f in files {
                            let dst = projectDir.appendingPathComponent("DRIVE/CMSIS/\(f.lastPathComponent)")
                            if !fm.fileExists(atPath: dst.path) {
                                try? fm.copyItem(atPath: f.path, toPath: dst.path)
                            }
                        }
                    }
                    break
                }
            }

            // 按选择复制外设库
            switch selectedLib {
            case .stdperiph:
                let skipStdperiph = Set(["stm32f4xx_it.c", "stm32f4xx_it.h"])
                if let fwlibSrc = Bundle.main.resourceURL?.appendingPathComponent("FWLib") {
                    for dir in ["inc", "src"] {
                        let srcDir = fwlibSrc.appendingPathComponent(dir)
                        if let files = try? fm.contentsOfDirectory(at: srcDir, includingPropertiesForKeys: nil) {
                            for f in files where !skipStdperiph.contains(f.lastPathComponent) {
                                try? fm.copyItem(atPath: f.path,
                                    toPath: projectDir.appendingPathComponent("DRIVE/FWLib/\(dir)/\(f.lastPathComponent)").path)
                            }
                        }
                    }
                    let conf = fwlibSrc.appendingPathComponent("stm32f4xx_conf.h")
                    if fm.fileExists(atPath: conf.path) {
                        try? fm.copyItem(atPath: conf.path,
                            toPath: projectDir.appendingPathComponent("DRIVE/FWLib/stm32f4xx_conf.h").path)
                    }
                }
            case .hal, .ll:
                if let lib = libraryPath {
                    let family = chipModel.replacingOccurrences(of: "STM32", with: "").dropLast(4)
                    let halDir = lib.appendingPathComponent("Drivers/STM32\(family)_HAL_Driver")
                    if fm.fileExists(atPath: halDir.path) {
                        for dir in ["Inc", "Src"] {
                            let srcDir = halDir.appendingPathComponent(dir)
                            guard let files = try? fm.contentsOfDirectory(at: srcDir, includingPropertiesForKeys: nil) else { continue }
                            for f in files {
                                if selectedLib == .ll && !f.lastPathComponent.contains("_ll_") { continue }
                                try? fm.copyItem(atPath: f.path,
                                    toPath: projectDir.appendingPathComponent("DRIVE/FWLib/\(dir.lowercased())/\(f.lastPathComponent)").path)
                            }
                        }
                    }
                }
            case .none:
                break
            }

            // main.c 模板
            let template = """

            int main(void) {
                while (1) {
                }
            }

            void SysTick_Handler(void) {
            }

            """
            try template.write(to: URL(fileURLWithPath: projectDir.appendingPathComponent("USER/main.c").path), atomically: true, encoding: .utf8)

            // 保存芯片型号，供构建脚本检测
            try chipModel.write(to: projectDir.appendingPathComponent("DRIVE/stm32_mcu"), atomically: true, encoding: .utf8)

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
