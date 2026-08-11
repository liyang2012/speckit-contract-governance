---
description: "校验微服务契约注册表和前端消费契约"
---

# 校验契约注册表和前端消费契约

校验根目录 `contracts/` 是否符合微服务契约治理规则，并检查 `contracts/_consumers/*.yaml` 中的前端消费期望。

## 行为

该命令会检查：

1. `contracts/SERVICE-MAP.md` 是否存在
2. `contracts/_registry/*.yaml` 是否存在
3. 每个 registry 的 `service` 是否与文件名一致
4. `contract_files.api` 是否指向真实 `contracts/<service>/api.yaml`
5. registry 中声明的事件文件和 MQ `contract_path` 是否存在
6. Consumer 状态是否只使用 `PENDING`、`RESOLVED`、`MISMATCH`
7. 非空 OpenAPI 文件是否包含 `openapi`、`paths`、`components`、`operationId` 和 `/api/vN/` 路径
8. 每个 operation 是否用 tags 声明 `前端API`、`Feign`、`内部API` 或 `外部API`
9. `Feign` 和 `内部API` operation 路径是否包含 `/internal/`
10. `internal_service_auth_mode: network-only` 时，内部 operation 是否错误声明或继承 OpenAPI `security`
11. `前端API` 和 `Feign` 是否被错误标记在同一个 operation 上；共用时是否在 plan 中声明例外
12. `contracts/_consumers/<consumer>.yaml` 是否只记录前端消费期望，不定义 Provider 接口
13. 前端 `RESOLVED` 消费项是否能在 Provider `api.yaml` 中找到 operationId
14. 前端消费项是否只指向 `前端API` 或 `外部API`，不得指向 `Feign`
15. 当前 feature plan 涉及微服务时，是否写明禁止跨服务直连数据库或等价约束
16. Consumer `required_fields` 是否存在于 Provider 成功响应 schema
17. PENDING 是否已经语义可解析或超过 `pending_max_age_days`
18. SERVICE-MAP 的 Provider、Consumer、状态和依赖关系是否漂移
19. 后端 Feign Consumer 是否指向真实的 `Feign` operation
20. breaking change 的 Consumer ack 是否有效并已确认
21. registry 是否错误重复维护 `feign_operations` / `mq_operations`；Provider 能力和调用方必须分别从契约文件与 Consumer `consumes` 推导

如果当前 feature 不涉及微服务或契约，且仓库没有 `contracts/`，命令会跳过。

## 执行

- **Bash**: `.specify/extensions/contract-governance/scripts/bash/validate-registry.sh [--service <service-name>] [--consumer <consumer-name>] [--bootstrap-ok]`
- **PowerShell**: `.specify/extensions/contract-governance/scripts/powershell/validate-registry.ps1 [-Service <service-name>] [-Consumer <consumer-name>] [-BootstrapOk]`

示例：

```bash
.specify/extensions/contract-governance/scripts/bash/validate-registry.sh
.specify/extensions/contract-governance/scripts/bash/validate-registry.sh --service my-service
.specify/extensions/contract-governance/scripts/bash/validate-registry.sh --consumer web-app
```

该命令需要 `python3` 和 PyYAML，以稳定解析 YAML/OpenAPI；缺少依赖时会明确失败，不会静默跳过语义校验。
