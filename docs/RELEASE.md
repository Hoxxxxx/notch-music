# 发布流程（自动更新）

应用使用 [Sparkle 2](https://sparkle-project.org) 实现自动更新，更新源托管在 GitHub Releases。

## 一次性配置（已完成）

- Sparkle 已通过 SPM 集成（`project.pbxproj`）
- `Info.plist` 已配置 `SUFeedURL`（指向仓库 `appcast.xml`）、`SUPublicEDKey`、`SUEnableAutomaticChecks`
- EdDSA 签名私钥保存在本机钥匙串（`generate_keys` 生成，**丢失将无法签名新版本**，可用 `security find-generic-password -s "Sparkle for macOS" -w` 检查）

## 发布新版本

```bash
./scripts/release.sh 0.3.0 "更新说明（支持 HTML）"
```

脚本会自动完成：bump 版本号 → Release 构建 → 打包 DMG → Sparkle 签名 → 更新 appcast.xml → 提交推送 → 创建 GitHub Release 并上传 DMG。

## 注意事项

- 若 `/tmp/sparkle-tools` 被清理，重新下载工具并设置环境变量：

  ```bash
  curl -L -o /tmp/sparkle-tools.zip https://github.com/sparkle-project/Sparkle/releases/latest/download/Sparkle-for-Swift-Package-Manager.zip
  unzip -o /tmp/sparkle-tools.zip -d /tmp/sparkle-tools && chmod +x /tmp/sparkle-tools/bin/*
  ```

- 建议换一个永久位置存放 Sparkle 工具（如 `~/tools/sparkle`），并通过 `SPARKLE_BIN_DIR` 指向
- 更新以 `CURRENT_PROJECT_VERSION`（build 号）作为版本比较依据，脚本会自动递增
- appcast.xml 必须在 main 分支上保持最新（Sparkle 通过 raw.githubusercontent 拉取）
