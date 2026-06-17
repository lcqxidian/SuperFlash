import Foundation

struct BuildPlanGenerator {
    func selectScript(for vendor: ProjectVendor) -> String? {
        switch vendor {
        case .stm32: return "stm32_build_flash"
        case .tiMSPM0: return "ti_mspm0_build_flash"
        case .unknown: return nil
        }
    }

    func shouldUseMakefile(_ info: ProjectInfo) -> Bool {
        info.vendor == .stm32 && info.makefile != nil
    }

    func openOCDConfig(for family: STM32Family?) -> String {
        family?.openOCDTarget ?? "target/stm32f4x.cfg"
    }
}
