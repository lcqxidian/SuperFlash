import SwiftUI

@main
struct SuperFlashApp: App {
    @State private var ballManager = FloatingBallManager.shared

    init() {
        // CLI 模式：命令行参数直接执行，不启动 GUI
        let args = CommandLine.arguments
        if args.count >= 2 {
            if args[1] == "build" || args[1] == "flash" || args[1] == "build-flash" || args[1] == "verify" {
                guard let cli = CLIHandler.parse(args) else { CLIHandler.printUsage(); exit(1) }
                do { try cli.run(); exit(0) }
                catch { print("错误：\(error.localizedDescription)"); exit(1) }
            }
        }
    }

    var body: some Scene {
        Window("SuperFlash", id: "main") {
            ContentView()
                .frame(minWidth: 1000, minHeight: 600)
                .onAppear {
                    // 找到当前窗口并绑定到悬浮球管理器
                    if let window = NSApp.windows.first(where: { $0.title == "SuperFlash" }) {
                        ballManager.bind(mainWindow: window)
                    }
                }
        }
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(replacing: .appSettings) {
                Button("设置...") {
                    NotificationCenter.default.post(name: .showSuperFlashSettings, object: nil)
                }
                .keyboardShortcut(",", modifiers: .command)
            }
            CommandGroup(after: .windowSize) {
                Divider()
                Button("切换悬浮球") {
                    FloatingBallManager.shared.toggle()
                }
                .keyboardShortcut("m", modifiers: [.command, .shift])
            }
        }
    }
}

extension Notification.Name {
    static let showSuperFlashSettings = Notification.Name("showSuperFlashSettings")
}
