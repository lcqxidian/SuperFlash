import Foundation

struct ToolchainInfo {
    var armGcc: URL?
    var armObjcopy: URL?
    var armSize: URL?
    var openocd: URL?
    var stlinkConnected: Bool = false

    var tiArmClang: URL?
    var tiObjcopy: URL?
    var tiSize: URL?
    var mspm0SDK: URL?
    var jlinkExe: URL?
    var jlinkConnected: Bool = false

    var hasArmGCC: Bool { armGcc != nil }
    var hasOpenOCD: Bool { openocd != nil }
    var hasTIArmClang: Bool { tiArmClang != nil }
    var hasMSPM0SDK: Bool { mspm0SDK != nil }
    var hasJLink: Bool { jlinkExe != nil }
}
