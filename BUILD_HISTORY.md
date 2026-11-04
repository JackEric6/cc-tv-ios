# GitHub Actions 构建记录

Actions 运行本身保存在 GitHub；此文件将重要构建与源码提交关联，便于从仓库追踪 IPA 和构建日志。IPA 是可重新生成的未签名产物，不提交到 Git。

| 时间（UTC） | 分支 | 源码提交 | 结果 | Actions 运行 |
| --- | --- | --- | --- | --- |
| 2026-11-04 14:43 | `main` | `40e238b` | 成功；版本 `1.0.7 (10)`，全控件横屏布局回归、Release 编译、元数据校验及 IPA 打包通过；本地保留未签名 IPA | [41848448122](https://github.com/JackEric6/cc-tv-ios/actions/runs/41848448122) |
| 2026-11-04 13:09 | `main` | `589331f` | 成功；版本 `1.0.6 (9)`，片尾标记改为按本集剩余时间切集；已更新 GitHub Release，附件为 `CongcongTV-unsigned-1.0.6.ipa` | [41835603498](https://github.com/JackEric6/cc-tv-ios/actions/runs/41835603498) · [Release 1.0.6](https://github.com/JackEric6/cc-tv-ios/releases/tag/1.0.6) |
| 2026-11-04 12:10 | `main` | `1641a9a` | 成功；版本 `1.0.6 (8)`，回归校验、Release 编译、元数据核验及 IPA 打包完成；已发布 GitHub Release 并附 IPA | [41826947704](https://github.com/JackEric6/cc-tv-ios/actions/runs/41826947704) · [Release 1.0.6](https://github.com/JackEric6/cc-tv-ios/releases/tag/1.0.6) |
| 2026-10-24 18:12 | `codex/ios-1.0.5-m3u8` | `69da535` | Release 编译和 IPA 打包成功；Actions Artifact 上传受仓库存储配额限制，后续已将本地构建 IPA 附加到 GitHub Release | [40119665580](https://github.com/JackEric6/cc-tv-ios/actions/runs/40119665580) · [Release 1.0.5](https://github.com/JackEric6/cc-tv-ios/releases/tag/1.0.5) |
| 2026-10-13 10:28 | `codex/ios-1.0.3-fixes` | `0624845` | 成功；发布构建版本 `1.0.3 (4)`，回归校验、Release 编译、元数据核验及 IPA 打包完成 | [38383049363](https://github.com/JackEric6/cc-tv-ios/actions/runs/38383049363) |
| 2026-10-13 09:22 | `codex/danmu-speed-search-stability` | `8435fb4` | 成功；发布构建版本 `1.0.2 (3)`，39 项校验、Release 编译、元数据核验及 IPA 打包完成 | [38375356331](https://github.com/JackEric6/cc-tv-ios/actions/runs/38375356331) |
| 2026-10-13 08:32 | `codex/danmaku-speed` | `6b191a6` | 成功；发布构建版本 `1.0.1 (2)`，校验、Release 编译、元数据核验及 IPA 上传完成 | [38369452960](https://github.com/JackEric6/cc-tv-ios/actions/runs/38369452960) |
| 2026-10-13 08:23 | `codex/danmaku-speed` | `3c56659` | 成功；版本 `1.0.1 (2)`，安卓优先弹幕查询验证、Release 编译及未签名 IPA 打包完成 | [38368414882](https://github.com/JackEric6/cc-tv-ios/actions/runs/38368414882) |
| 2026-10-12 07:28 | `main` | `6bfbadc` | 成功；验证、Release 编译及未签名 IPA 上传完成 | [38217941276](https://github.com/JackEric6/CongcongTV-iOS-Swift/actions/runs/38217941276) |
| 2026-10-12 06:37 | `variant-xgzy-20260923` | `44ded26` | 成功；上传未签名 IPA 与 `build.log` | [38213469936](https://github.com/JackEric6/CongcongTV-iOS-Swift/actions/runs/38213469936) |

## 版本标记

- `MARKETING_VERSION`: `1.0.7`
- `CURRENT_PROJECT_VERSION`: `10`
- 版本字段定义在 `project.yml`；日常迭代由 Git commit 和 Actions run 追踪。发布到需要唯一构建号的平台前，应先提升构建号。

## 构建产物

工作流 `Build CongcongTV iOS IPA (XGZY)` 上传的 IPA 文件名包含版本号，例如 `CongcongTV-unsigned-1.0.7.ipa`，并附带 `build.log`。在对应 Actions 运行页面下载；artifact 按 GitHub 的保留期限保存，过期后可重新运行 workflow 构建。
