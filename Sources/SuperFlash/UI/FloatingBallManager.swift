import SwiftUI
import AppKit

/// 悬浮球操作状态
enum BallStatus: Equatable {
    case idle
    case building
    case flashing
    case verifying
    case success(String)
    case failure(String)
}

/// 管理悬浮球窗口 — 点击切换正常/悬浮模式
@MainActor
final class FloatingBallManager: ObservableObject {
    static let shared = FloatingBallManager()

    @Published var isBallMode = false
    @Published var status: BallStatus = .idle
    @Published var buildProgress: Double = 0
    /// 每次 updateStatus 递增，强制 NSHostingView 刷新
    @Published var statusVersion: UInt = 0

    var onBuild: (() -> Void)?
    var onBuildAndFlash: (() -> Void)?
    var onVerify: (() -> Void)?

    private(set) var ballWindow: NSWindow?
    private weak var mainWindow: NSWindow?
    private var savedFrame: NSRect?
    private var revertTask: DispatchWorkItem?

    // MARK: - 绑定 & 切换

    func bind(mainWindow: NSWindow) {
        self.mainWindow = mainWindow
        NotificationCenter.default.addObserver(
            self, selector: #selector(windowWillClose),
            name: NSWindow.willCloseNotification, object: mainWindow
        )
    }

    func toggle() {
        if isBallMode { exitBallMode() } else { enterBallMode() }
    }

    func enterBallMode() {
        guard let mainWindow else { return }
        savedFrame = mainWindow.frame
        mainWindow.level = .normal
        if ballWindow == nil { createBallWindow() }
        ballWindow?.makeKeyAndOrderFront(nil)
        mainWindow.orderOut(nil)
        isBallMode = true
    }

    func exitBallMode() {
        guard let mainWindow, let ballWindow else { return }
        let targetFrame = savedFrame ?? defaultFrame(for: mainWindow)
        let ballFrame = ballWindow.frame
        let startRect = NSRect(
            x: ballFrame.midX - targetFrame.width / 2,
            y: ballFrame.midY - targetFrame.height / 2,
            width: targetFrame.width, height: targetFrame.height
        )
        ballWindow.orderOut(nil)
        mainWindow.level = .floating
        mainWindow.setFrame(startRect, display: false)
        mainWindow.alphaValue = 0
        mainWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            mainWindow.animator().setFrame(targetFrame, display: true)
            mainWindow.animator().alphaValue = 1
        }
        isBallMode = false
    }

    // MARK: - 状态

    func updateStatus(_ newStatus: BallStatus) {
        revertTask?.cancel()
        status = newStatus
        statusVersion &+= 1

        // 强制重建 NSHostingView 的 rootView（@Published 在 NSHostingView 中不可靠）
        if let hostView = ballWindow?.contentView as? NSHostingView<FloatingBallContent> {
            hostView.rootView = FloatingBallContent(manager: self, status: status, version: statusVersion)
        }

        // 清除 layer 底色（之前调试加上的）
        ballWindow?.contentView?.layer?.backgroundColor = nil

        // 取消之前的恢复任务
        revertTask?.cancel()

        // 成功状态 3 秒后恢复为 idle
        if case .success = newStatus {
            let item = DispatchWorkItem { [weak self] in
                self?.updateStatus(.idle)
            }
            revertTask = item
            DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: item)
        } else if case .failure = newStatus {
            let item = DispatchWorkItem { [weak self] in
                self?.updateStatus(.idle)
            }
            revertTask = item
            DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: item)
        }
    }

    // MARK: - Private

    private func defaultFrame(for window: NSWindow) -> NSRect {
        guard let screen = window.screen ?? NSScreen.main else {
            return NSRect(x: 200, y: 200, width: 1000, height: 600)
        }
        let frame = screen.visibleFrame
        return NSRect(
            x: frame.minX + (frame.width - 1000) / 2,
            y: frame.minY + (frame.height - 600) / 2,
            width: 1000, height: 600
        )
    }

    @objc private func windowWillClose(_ notification: Notification) {
        enterBallMode()
    }

    private func createBallWindow() {
        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let window = NSWindow(
            contentRect: NSRect(x: screenFrame.maxX - 320 - 20, y: screenFrame.minY + 40,
                                width: 320, height: 56),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.isMovableByWindowBackground = true
        for b in [window.standardWindowButton(.closeButton),
                  window.standardWindowButton(.miniaturizeButton),
                  window.standardWindowButton(.zoomButton)] { b?.isHidden = true }

        let host = NSHostingView(rootView: FloatingBallContent(manager: self, status: status, version: statusVersion))
        host.wantsLayer = true
        host.layer?.cornerRadius = 28
        host.layer?.masksToBounds = true
        window.contentView = host
        ballWindow = window
    }

    /// 更新 NSHostingView 的 rootView，强制 SwiftUI 刷新（不断重建窗口会导致显示异常）
    private func rebuildBallHostView() {
        guard let hostView = ballWindow?.contentView as? NSHostingView<FloatingBallContent> else {
            print("[rebuildBallHostView] SKIP: not a NSHostingView<FloatingBallContent>")
            return
        }
        hostView.rootView = FloatingBallContent(manager: self, status: status, version: statusVersion)
        print("[rebuildBallHostView] rootView updated, status=\(status)")
    }
}

// MARK: - 悬浮球内容

struct FloatingBallContent: View {
    @ObservedObject var manager: FloatingBallManager
    let status: BallStatus
    let version: UInt
    @State private var isHovered = false
    @State private var isAnimating = false

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 4) {
                actionButton(icon: "hammer.fill", label: "编译", action: manager.onBuild)
                actionButton(icon: "bolt.fill", label: "烧录", action: manager.onBuildAndFlash)
                actionButton(icon: "antenna.radiowaves.left.and.right", label: "验证", action: manager.onVerify)
            }
            .padding(.leading, 4)
            .padding(.trailing, 8)
            .padding(.vertical, 4)
            .opacity(isHovered && status == .idle ? 1 : 0)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(.ultraThinMaterial)
                    .opacity(isHovered && status == .idle ? 1 : 0)
            )
            .animation(.easeInOut(duration: 0.12), value: isHovered)

            Spacer(minLength: 0)

            ballBody
                .onTapGesture { manager.exitBallMode() }
        }
        .padding(2)
        .onHover { hovering in
            isHovered = hovering
        }
    }

    @ViewBuilder
    private var ballBody: some View {
        Group {
            switch status {
            case .idle: idleBall
            case .building: hammerBall
            case .flashing: chipBall
            case .verifying: signalBall
            case .success: successBall
            case .failure: failureBall
            }
        }
        .id(version)
    }

    private var idleBall: some View {
        Circle()
            .fill(LinearGradient(colors: [.accentColor, .accentColor.opacity(0.7)],
                                 startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(width: 52, height: 52)
            .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
            .overlay(Image(systemName: "cpu").font(.system(size: 20, weight: .medium)).foregroundColor(.white))
    }

    private var hammerBall: some View {
        ZStack {
            progressTrack(color: .orange)
            progressRing(color: .orange)
            Circle().fill(Color.orange).frame(width: 52, height: 52)
                .shadow(color: .orange.opacity(0.3), radius: 6, y: 2)
                .overlay(
                    Image(systemName: "hammer.fill")
                        .font(.system(size: 22))
                        .foregroundColor(.white)
                        .rotationEffect(.degrees(isAnimating ? 6 : -4), anchor: .bottom)
                        .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: isAnimating)
                )
        }
        .onAppear { isAnimating = true }
        .onDisappear { isAnimating = false }
    }

    private var chipBall: some View {
        ZStack {
            progressTrack(color: .purple)
            progressRing(color: .purple)
            Circle().fill(Color.purple).frame(width: 52, height: 52)
                .shadow(color: .purple.opacity(0.3), radius: 6, y: 2)
                .overlay(
                    Image(systemName: "memorychip.fill")
                        .font(.system(size: 22))
                        .foregroundColor(.white)
                        .scaleEffect(isAnimating ? 1.2 : 0.8)
                        .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: isAnimating)
                )
        }
        .onAppear { isAnimating = true }
        .onDisappear { isAnimating = false }
    }

    private var signalBall: some View {
        ZStack {
            progressTrack(color: .blue)
            progressRing(color: .blue)
            Circle().fill(Color.blue).frame(width: 52, height: 52)
                .shadow(color: .blue.opacity(0.3), radius: 6, y: 2)
                .overlay(
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.system(size: 20))
                        .foregroundColor(.white)
                        .opacity(isAnimating ? 1 : 0.4)
                        .animation(.easeInOut(duration: 0.4).repeatForever(autoreverses: true), value: isAnimating)
                )
        }
        .onAppear { isAnimating = true }
        .onDisappear { isAnimating = false }
    }

    private var successBall: some View {
        Circle().fill(Color.green).frame(width: 52, height: 52)
            .shadow(color: .green.opacity(0.3), radius: 6, y: 2)
            .overlay(CheckmarkView().frame(width: 40, height: 40))
    }

    private var failureBall: some View {
        Circle().fill(Color.red).frame(width: 52, height: 52)
            .shadow(color: .red.opacity(0.3), radius: 6, y: 2)
            .overlay(
                Image(systemName: "xmark")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.white)
            )
    }

    private func actionButton(icon: String, label: String, action: (() -> Void)?) -> some View {
        Button { action?() } label: {
            Label(label, systemImage: icon)
                .font(.system(size: 12, weight: .medium))
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    // MARK: - 进度环

    private func progressTrack(color: Color) -> some View {
        Circle()
            .stroke(color.opacity(0.12), lineWidth: 3)
            .frame(width: 60, height: 60)
    }

    private func progressRing(color: Color) -> some View {
        Circle()
            .trim(from: 0, to: CGFloat(min(manager.buildProgress, 1)))
            .stroke(color, style: StrokeStyle(lineWidth: 3, lineCap: .round))
            .frame(width: 60, height: 60)
            .rotationEffect(.degrees(-90))
    }
}

// MARK: - 手写动画勾

struct CheckmarkView: View {
    @State private var progress: CGFloat = 0

    var body: some View {
        Path { path in
            path.move(to: CGPoint(x: 8, y: 22))
            path.addLine(to: CGPoint(x: 17, y: 29))
            path.addLine(to: CGPoint(x: 32, y: 13))
        }
        .trim(from: 0, to: progress)
        .stroke(Color.white, style: StrokeStyle(lineWidth: 4.5, lineCap: .round, lineJoin: .round))
        .frame(width: 40, height: 40)
        .onAppear {
            withAnimation(.easeOut(duration: 0.35)) {
                progress = 1
            }
        }
    }
}
