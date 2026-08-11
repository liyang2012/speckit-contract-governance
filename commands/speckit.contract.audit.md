---
description: "执行契约语义审计、运行时 OpenAPI 对比、事件兼容性检查并输出结构化报告"
---

# 契约语义审计

使用稳定的 YAML/OpenAPI 解析器执行结构之上的语义校验。

## 行为

默认审计：

1. 校验前端 `required_fields` 是否能在 Provider 成功响应 schema 中解析。
2. 校验后端 Feign/内部 HTTP PENDING/RESOLVED 是否存在对应 Provider operation，并符合调用边界 tag。
3. 检查 SERVICE-MAP 的 Provider、Consumer、状态和依赖关系漂移。
4. 检查 breaking change ack 和超期 PENDING。
5. 检查事件契约身份、版本和 payload/schema 基础结构。
6. 支持 text、JSON 和 SARIF 输出。

可选模式：

- `--runtime-openapi <file>`：对比导出的 `/v3/api-docs` 与设计契约。
- `--event-old/--event-new`：检查事件 schema 字段删除、类型变化和必填变化。

## 执行

- **Bash**: `.specify/extensions/contract-governance/scripts/bash/audit-contracts.sh [options]`
- **PowerShell**: `.specify/extensions/contract-governance/scripts/powershell/audit-contracts.ps1 [options]`

示例：

```bash
.specify/extensions/contract-governance/scripts/bash/audit-contracts.sh
.specify/extensions/contract-governance/scripts/bash/audit-contracts.sh --format sarif
.specify/extensions/contract-governance/scripts/bash/audit-contracts.sh --service my-service --runtime-openapi build/openapi.json
.specify/extensions/contract-governance/scripts/bash/audit-contracts.sh --event-old contracts/demo/events/v1.yaml --event-new contracts/demo/events/v2.yaml
```

退出码：`0` 表示通过，`1` 表示错误，`2` 表示 breaking change 或严格 warning。
