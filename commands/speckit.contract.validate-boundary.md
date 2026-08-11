---
description: "校验 plan.md / tasks.md 是否包含 FE/BE/Contract 边界和契约引用"
---

# 校验 FE/BE/Contract 边界

校验当前 feature 的 `plan.md` 和 `tasks.md` 是否在保持一个业务 feature 的同时，明确写出前端、后端和契约边界。

## 行为

该命令检查当前 feature 的 `plan.md`：

1. 是否残留模板占位符或 `NEEDS CLARIFICATION`
2. 是否声明 `Upstream Dependencies` / 上游依赖
3. 是否包含契约边界内容，例如 `contracts/`、`api.yaml`、`_consumers`、OpenAPI、Provider/Consumer 等
4. 当前端在范围内时，是否包含前端边界内容
5. 当后端在范围内时，是否包含后端边界内容
6. 是否包含测试策略和完成定义

该命令检查当前 feature 的 `tasks.md`：

1. 是否残留模板占位符
2. 是否包含引用 `contracts/`、`api.yaml`、`_consumers`、OpenAPI、Provider/Consumer 等契约任务
3. 当前端在范围内时，是否包含前端任务
4. 当后端在范围内时，是否包含后端任务
5. 是否包含验证或测试任务
6. 是否包含写明 `Downstream Contract` 的最终交付任务

如果当前没有 active feature 目录，命令会输出跳过提示并正常退出，避免仓库级初始化命令在 `/speckit-specify` 创建 feature 前失败。

## 执行

- **Bash**: `.specify/extensions/contract-governance/scripts/bash/validate-boundary.sh --plan`
- **Bash**: `.specify/extensions/contract-governance/scripts/bash/validate-boundary.sh --tasks`
- **Bash**: `.specify/extensions/contract-governance/scripts/bash/validate-boundary.sh --all`
- **PowerShell**: `.specify/extensions/contract-governance/scripts/powershell/validate-boundary.ps1 -Plan`
- **PowerShell**: `.specify/extensions/contract-governance/scripts/powershell/validate-boundary.ps1 -Tasks`
- **PowerShell**: `.specify/extensions/contract-governance/scripts/powershell/validate-boundary.ps1 -All`

需要校验指定 feature 目录时，传入 `--feature-dir <path>`。
