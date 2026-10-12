# GitHub Actions 构建记录

Actions 运行本身保存在 GitHub；此文件将重要构建与源码提交关联，便于从仓库追踪 IPA 和构建日志。IPA 是可重新生成的未签名产物，不提交到 Git。

| 时间（UTC） | 分支 | 源码提交 | 结果 | Actions 运行 |
| --- | --- | --- | --- | --- |
| 2026-10-12 06:37 | `variant-xgzy-20260923` | `44ded26` | 成功；上传未签名 IPA 与 `build.log` | [38213469936](https://github.com/JackEric6/CongcongTV-iOS-Swift/actions/runs/38213469936) |

## 版本标记

- `MARKETING_VERSION`: `1.0.0`
- `CURRENT_PROJECT_VERSION`: `1`
- 版本字段定义在 `project.yml`；日常迭代由 Git commit 和 Actions run 追踪。发布到需要唯一构建号的平台前，应先提升构建号。

## 构建产物

工作流 `Build CongcongTV iOS IPA (XGZY)` 上传名为 `CongcongTV-iOS-unsigned-ipa` 的 artifact，其中包含 `CongcongTV-unsigned.ipa` 和 `build.log`。在对应 Actions 运行页面下载；artifact 按 GitHub 的保留期限保存，过期后可重新运行 workflow 构建。
