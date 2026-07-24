# Restore TI MSPM0 Flash Safety Implementation Plan

**Goal:** 恢复已经通过 Test5 实机验证的 TI MSPM0 两阶段烧录成功判据，同时保留用户允许的项目自动监听删除。

**Architecture:** SAM-ICE 冷启动仍由 DSLite 先建立连接；DSLite 的 `Success/Running` 只作为进入下一阶段的条件。最终成功必须由 J-Link `loadfile` 完整 Program & Verify、设备级复位、寄存器检查和 `go` 共同确认。

**Tech Stack:** Swift 6、Python 3 标准库、TI DSLite、SEGGER JLinkExe。

---

### Task 1: 恢复 TI 安全判据

**Files:**

- Modify: `Sources/SuperFlash/Resources/scripts/ti_mspm0_build_flash.py`

1. 删除 DSLite 前无效的 JLinkExe 冷启动预连接。
2. 删除无证据的 DSLite 立即重试。
3. 将 J-Link 完整写入与运行验证结果赋回 `succeeded`。
4. 只在 J-Link 验证成功时设置 `jlink_loadfile_verified`。

### Task 2: 验证失败与成功路径

1. 运行 Python AST 语法检查。
2. 模拟 DSLite 成功、J-Link 失败，预期函数抛出失败且不设置已验证标记。
3. 模拟 DSLite 成功、J-Link 成功，预期函数成功并设置已验证标记。
4. 运行 `swift build -c release`。

### Task 3: 同步文档并部署

**Files:**

- Modify: `PROJECT_DOCUMENTATION.md`
- Keep: `Sources/SuperFlash/App/AppState.swift` 中项目自动监听删除

1. 记录用户接受删除自动监听。
2. 记录 TI 假成功回退、恢复内容和验证结果。
3. 重新部署 `/Applications/SuperFlash.app` 并执行签名校验。
4. 比对应用内 TI 脚本与源码 SHA-256。

不执行真实硬件烧录。Git 写操作仅在用户本人明确授权后执行；用户已于 2026-07-24 授权将当前版本作为“7月24日修复版”提交并推送。
