---
description: "运行 FE/BE 边界、微服务注册表和前端消费契约综合校验"
---

# 综合校验契约治理

同时运行 FE/BE/Contract 边界校验、微服务契约注册表校验和 `contracts/_consumers/` 前端消费契约校验。

## 行为

该命令用于必须同时检查三层规则的门禁：

1. 第一层：`plan.md` / `tasks.md` 是否明确 FE、BE、Contract 边界
2. 第二层：根目录 `contracts/` 注册表是否符合服务所有权、Provider/Consumer、Feign/内部 HTTP/MQ 和跨服务安全规则
3. 第三层：`contracts/_consumers/*.yaml` 是否只记录前端消费期望，且不得消费 `Feign` 或 `内部API` operation

## 执行

- **Bash**: `.specify/extensions/contract-governance/scripts/bash/validate-all.sh`
- **PowerShell**: `.specify/extensions/contract-governance/scripts/powershell/validate-all.ps1`

按阶段执行：

```bash
.specify/extensions/contract-governance/scripts/bash/validate-all.sh --phase plan
.specify/extensions/contract-governance/scripts/bash/validate-all.sh --phase tasks
```

全新项目 bootstrap 阶段：

```bash
.specify/extensions/contract-governance/scripts/bash/validate-all.sh --phase plan --bootstrap-ok
```
