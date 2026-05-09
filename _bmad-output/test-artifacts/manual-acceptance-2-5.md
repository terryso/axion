# Story 2-5 手工验收文档

**Story:** Homebrew 私有 Tap 分发与打包
**Date:** 2026-05-09
**Version:** 0.1.0

## 验收检查项

### AC5/AC4: build-release.sh 完整流程 + Code Signing

- [x] 1. 运行 `bash Distribution/homebrew/build-release.sh --sign` 成功退出（exit 0）
- [x] 2. 生成 `.build/dist/axion-0.1.0.tar.gz` 文件存在（6.6M）
- [x] 3. tar.gz 内容结构正确（`axion-0.1.0/bin/axion` + `axion-0.1.0/libexec/axion/AxionHelper.app/Contents/MacOS/AxionHelper`）
- [x] 4. AxionHelper.app 包含 `Contents/Info.plist`，版本号为 `0.1.0`
- [x] 5. AxionHelper.app 有有效的 ad-hoc 签名（`codesign --verify` 通过）
- [x] 6. 签名包含 entitlements（`com.apple.security.automation.apple-events`）
- [x] 7. 生成的 `Distribution/homebrew/axion.rb` 包含正确的 sha256、URL 和 version

### AC6: HelperApp 路径解析

- [x] 8. `AXION_HELPER_PATH` 环境变量覆盖有效（单元测试通过）
- [x] 9. 开发模式下（`.build` 目录中运行）能解析到 AxionHelper.app（单元测试通过）
- [x] 10. 无 Helper 且无环境变量时返回 nil（不崩溃）

### AC1/AC2: Homebrew Formula 验证

- [x] 11. `axion.rb.template` 包含 `desc`、`homepage`、`version`、`url`、`sha256` 字段
- [x] 12. formula 的 `install` 方法包含 `bin.install "bin/axion"` 和 `libexec.install`
- [x] 13. formula 包含 `caveats` 引导信息（`axion setup` / `axion doctor`）
- [x] 14. formula 包含 `test` 块验证 `--version`
- [x] 15. formula 声明 `depends_on :macos => :sonoma`

### AC7: publish-release.sh 脚本验证

- [x] 16. `publish-release.sh` 存在且可执行
- [x] 17. 脚本包含 GitHub Release 创建（`gh release create`）
- [x] 18. 脚本包含 Homebrew tap 更新逻辑

### 单元测试回归

- [x] 19. 全部 211 个单元测试通过，0 failures

## 结果

- **通过/失败:** PASS
- **测试人:** Claude Code (GLM-5.1)
- **备注:** 所有 19 项验收检查通过。sha256=41746f98a11e6ba6bb28c146b017e3aa4930e297b6cd0ea6b451dfe368065852
