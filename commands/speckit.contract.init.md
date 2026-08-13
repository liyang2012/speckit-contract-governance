---
description: "初始化根目录 contracts/ 微服务契约注册表"
---

# 初始化微服务契约注册表

创建根目录 `contracts/` 注册表骨架，用于全新项目或新增服务。

该命令初始化后端 Provider 服务契约。前端消费方不要在这里定义接口；需要记录前端消费期望时，使用 `speckit.contract-governance.init-consumer` 创建 `contracts/_consumers/<consumer>.yaml`。

## 行为

该命令会创建：

1. `contracts/SERVICE-MAP.md`
2. `contracts/_registry/<service>.yaml`
3. `contracts/<service>/api.yaml`
4. `contracts/<service>/events/.gitkeep`

已有文件不会被覆盖。

## 执行

- **Bash**: `.specify/extensions/contract-governance/scripts/bash/init-registry.sh --service <service-name> [--database <database-name>]`
- **PowerShell**: `.specify/extensions/contract-governance/scripts/powershell/init-registry.ps1 -Service <service-name> [-Database <database-name>]`

示例：

```bash
.specify/extensions/contract-governance/scripts/bash/init-registry.sh --service my-service --database db_myapp
```
