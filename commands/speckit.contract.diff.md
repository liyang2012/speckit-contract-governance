---
description: "对比契约文件 git 历史变更，生成 x-changelog 和消费者 changes 段"
---

# 检测契约变更

对比 `contracts/<service>/api.yaml` 的 git 历史版本与当前版本，执行 OpenAPI 语义 diff，生成 `x-changelog` YAML 条目和 Consumer 影响面。

## 行为

该命令会：

1. 从 git 获取指定基线（默认 HEAD）的旧版 `api.yaml`
2. 解析新旧版本的 operation、参数、响应、schema、enum 和 tags
3. 检测 operation/字段删除、类型变化、必填变化、枚举收窄、响应状态码和调用方边界变化
4. 生成 `x-changelog` YAML 条目，避免与已有条目重复
5. `--write` 将 changelog 追加到 `api.yaml`
6. 如果有 breaking change，输出消费者需关注的 `changes` 段内容
7. `--consumer <file>` 可将 breaking change 自动注入到指定消费者文件的对应 http 条目下；该参数会修改文件，必须与 `--write` 同时使用
8. 自动列出 `_registry` 和 `_consumers` 中受影响的后端及前端 Consumer

退出码：

- `0` = 仅 non-breaking 或无变更
- `2` = 存在 breaking changes

## 执行

- **Bash**: `.specify/extensions/contract-governance/scripts/bash/diff-contract.sh --service <service-name> [--base <git-ref>] [--write] [--consumer <file>]`
- **PowerShell**: `.specify/extensions/contract-governance/scripts/powershell/diff-contract.ps1 -Service <service-name> [-Base <git-ref>] [-Write] [-ConsumerFiles <file>]`

示例：

```bash
.specify/extensions/contract-governance/scripts/bash/diff-contract.sh --service my-service
.specify/extensions/contract-governance/scripts/bash/diff-contract.sh --service my-service --write
.specify/extensions/contract-governance/scripts/bash/diff-contract.sh --service my-service --base origin/main --write
.specify/extensions/contract-governance/scripts/bash/diff-contract.sh --service my-service --write --consumer contracts/_consumers/web-app.yaml
```
