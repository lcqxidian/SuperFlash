import SwiftUI

@main
struct SuperFlashApp: App {
    @State private var ballManager = FloatingBallManager.shared

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
