import Foundation

final class SettingsStore: ObservableObject {
    @Published var armGccPath: String = ""
    @Published var openocdPath: String = ""
    @Published var tiArmClangPath: String = ""
    @Published var mspm0SDKPath: String = ""
    @Published var jlinkPath: String = ""
    @Published var openocdSpeed: String = "4000"
    @Published var jlinkSpeed: String = "4000"
    @Published var saveRecentProjects: Bool = true
    @Published var stm32FlashSize: String = ""
    @Published var stm32RamSize: String = ""

    private let defaultsKey = "com.superflash.settings"

    init() {
        load()
    }

    func load() {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: String] else { return }
        armGccPath = dict["armGccPath"] ?? ""
        openocdPath = dict["openocdPath"] ?? ""
        tiArmClangPath = dict["tiArmClangPath"] ?? ""
        mspm0SDKPath = dict["mspm0SDKPath"] ?? ""
        jlinkPath = dict["jlinkPath"] ?? ""
        openocdSpeed = dict["openocdSpeed"] ?? "4000"
        jlinkSpeed = dict["jlinkSpeed"] ?? "4000"
        saveRecentProjects = dict["saveRecentProjects"] != "false"
        stm32FlashSize = dict["stm32FlashSize"] ?? ""
        stm32RamSize = dict["stm32RamSize"] ?? ""
    }

    func save() {
        let dict: [String: String] = [
            "armGccPath": armGccPath,
            "openocdPath": openocdPath,
            "tiArmClangPath": tiArmClangPath,
            "mspm0SDKPath": mspm0SDKPath,
            "jlinkPath": jlinkPath,
            "openocdSpeed": openocdSpeed,
            "jlinkSpeed": jlinkSpeed,
            "saveRecentProjects": saveRecentProjects ? "true" : "false",
            "stm32FlashSize": stm32FlashSize,
            "stm32RamSize": stm32RamSize,
        ]
        if let data = try? JSONSerialization.data(withJSONObject: dict) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }

    var envOverrides: [String: String] {
        var env: [String: String] = [:]
        if !armGccPath.isEmpty { env["ARM_GCC"] = armGccPath }
        if !openocdPath.isEmpty { env["OPENOCD"] = openocdPath }
        if !tiArmClangPath.isEmpty { env["CGT_ROOT"] = tiArmClangPath }
        if !mspm0SDKPath.isEmpty { env["SDK_ROOT"] = mspm0SDKPath }
        if !jlinkPath.isEmpty { env["JLINK"] = jlinkPath }
        return env
    }
}
