# 发布流程（自动更新）

应用使用 [Sparkle 2](https://sparkle-project.org) 实现自动更新，appcast 托管在 GitHub Pages，DMG 托管在 GitHub Releases。

## 一次性配置（已完成）

- Sparkle 已通过 SPM 集成（`project.pbxproj`）
- GitHub Pages 的来源为 `main` 分支的 `/docs` 目录
- `Info.plist` 已配置 `SUFeedURL=https://hoxxxxx.github.io/notch-music/appcast.xml`、`SUPublicEDKey`、`SUEnableAutomaticChecks`
- EdDSA 签名私钥保存在本机钥匙串（`generate_keys` 生成，**丢失将无法签名新版本**）

## 发布新版本

```bash
./scripts/release.sh 0.3.0 "更新说明（支持 HTML）"
```

脚本会自动完成：bump 版本号 → Release 构建 → 打包 DMG → Sparkle 签名 → 更新 `docs/appcast.xml` → 提交推送 → 创建 GitHub Release 并上传 DMG。

## 注意事项

- 脚本会优先使用 `.build/SourcePackages/artifacts/sparkle/Sparkle/bin/sign_update`；找不到时再使用 `SPARKLE_BIN_DIR` 或 `/tmp/sparkle-tools/bin`
- 若 `/tmp/sparkle-tools` 被清理，重新下载工具并设置环境变量：

  ```bash
  curl -L -o /tmp/sparkle-tools.zip https://github.com/sparkle-project/Sparkle/releases/latest/download/Sparkle-for-Swift-Package-Manager.zip
  unzip -o /tmp/sparkle-tools.zip -d /tmp/sparkle-tools && chmod +x /tmp/sparkle-tools/bin/*
  ```

- 更新以 `CURRENT_PROJECT_VERSION`（build 号）作为版本比较依据，脚本会自动递增
- `docs/appcast.xml` 必须在 main 分支上保持最新；推送后等待 GitHub Pages 完成部署，再分发新版本
- DMG 的窗口布局由 `scripts/create-dmg.sh` 通过 Finder 写入，必须在本机已登录桌面时运行；SSH 或 CI 环境下布局不会生效
