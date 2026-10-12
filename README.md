# 丛丛影视 iOS

基于 SwiftUI 的 iOS 点播应用，最低支持 iOS 17。工程配置的版本号为 `1.0.0`（build `1`），Bundle ID 为 `com.congcong.tv.xgzy`。中文系统下应用显示为“丛丛影视”。

## 功能概览

- 内置 `tvbox/Resources/xgzy_config_all.json` 点播配置，包含 46 个影视源；默认启动使用包内配置，不请求旧的远程默认 JSON，并会将旧默认地址迁移到内置配置。
- 多源首页、影视搜索与搜索建议；支持固定搜索源顺序及首页源设置。设置键 `7701`、`8801`、`9901` 分别选择瓜子、西瓜、荐片。
- 多线路播放地址整理、按站点处理请求头与播放线路、失败后线路回退；提供 M3U8 净化和系统代理设置。
- 弹幕自动搜索与手动选择，支持候选结果筛选、备用接口尝试、跨源本地缓存及播放时间轴同步。
- 播放器支持横竖屏、选集、倍速和画面比例控制。
- 下载页面支持直接媒体与 HLS 下载，并显示预估剩余时间。
- 收藏、播放历史及本地配置持久化。

影视源和第三方弹幕服务的可用性取决于对应服务端状态与网络环境；仓库中的验证脚本用于检查客户端规则，不代表所有外部源在任何时间均可用。

## 版本与迭代记录

工程版本由 `project.yml` 中的 `MARKETING_VERSION` 和 `CURRENT_PROJECT_VERSION` 管理，当前为 `1.0.0 (1)`。功能迭代保留在 Git 提交历史中；`variant-xgzy-20260923` 的提交链已通过 merge commit 合入 `main`，未 squash。阶段摘要见 [CHANGELOG.md](CHANGELOG.md)，Actions 构建结果与对应提交见 [BUILD_HISTORY.md](BUILD_HISTORY.md)。

## GitHub Actions 构建 IPA

仓库包含 `.github/workflows/build-ios.yml`，在相关源码、配置、脚本或工程文件推送后自动运行，也可以手动触发：

1. 打开 GitHub 仓库的 **Actions** 页面。
2. 选择 **Build CongcongTV iOS IPA (XGZY)**，点击 **Run workflow** 并选择 `main`。
3. 等待 macOS runner 完成验证和 Release 构建。
4. 从运行结果的 Artifacts 下载 `CongcongTV-iOS-unsigned-ipa`，解压后得到 `CongcongTV-unsigned.ipa` 和 `build.log`。

工作流会运行播放、配置、搜索、净化、弹幕和下载等 Swift 验证脚本，然后用 Xcode 构建并检查 App 元数据与内置配置。上传的是**未签名 IPA**，不能直接安装；请使用 SideStore、AltStore 等工具通过 Apple ID 签名后侧载。Actions 构建产物保存在 GitHub Actions Artifacts 中，不将大型二进制文件提交到 Git。

## 安装说明

1. 在 iPhone 上完成 SideStore 或 AltStore 的安装与设备配对。
2. 从 GitHub Actions 下载并解压 `CongcongTV-iOS-unsigned-ipa`。
3. 将 `CongcongTV-unsigned.ipa` 导入侧载工具，完成签名和安装。
4. 如使用免费 Apple ID，按侧载工具提示定期刷新签名。

不同侧载工具的界面和签名要求可能不同；未签名 IPA 需要先签名，不能直接通过“文件”App 安装。

## 本地 macOS 构建

需要 macOS、Xcode 及 XcodeGen：

```bash
brew install xcodegen
xcodegen generate --spec project.yml
xcodebuild \
  -project CongcongTV.xcodeproj \
  -scheme CongcongTV \
  -configuration Release \
  -sdk iphoneos \
  -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO
```

Windows 环境不能运行 Xcode，请使用 GitHub Actions 完成 iOS 构建。

## 目录

```text
tvbox/                    iOS 应用源码、资源和内置点播配置
Vendor/KSPlayer/          工程使用的 KSPlayer 源码
scripts/                  Swift 验证脚本
.github/workflows/        GitHub Actions 构建工作流
project.yml               XcodeGen 工程定义和版本号
CHANGELOG.md              功能阶段与版本迭代摘要
BUILD_HISTORY.md          GitHub Actions 构建记录
```
