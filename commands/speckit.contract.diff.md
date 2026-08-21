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
4. 按 `method + path + operationId` 聚合原子变化，并生成带稳定 SHA-256 fingerprint 的 `x-changelog` 条目
5. `--write` 将 changelog 追加到 `api.yaml`
6. breaking 聚合条目列出受影响 Consumer
7. `--consumer <file>` 可将 breaking change 自动注入到指定消费者文件的对应 http 条目下；该参数会修改文件，必须与 `--write` 同时使用
8. 自动列出 `_registry` 和 `_consumers` 中受影响的后端及前端 Consumer

退出码：

- `0` = 仅 non-breaking 或无变更
- `2` = 存在 breaking changes

纯描述、注释和格式变化不生成记录；新增 Provider 契约视为初始版本。条目 ID 由日期和聚合指纹生成，重复执行按 fingerprint 去重并保持幂等。旧格式条目继续可解析，但不能覆盖新门禁变化。

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
