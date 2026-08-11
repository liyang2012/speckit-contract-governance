---
description: "初始化前端 Consumer Contract"
---

# 初始化前端消费契约

创建根目录 `contracts/_consumers/<consumer>.yaml`，用于记录前端对后端 Provider operation 的消费期望。

## 行为

该命令会创建：

1. `contracts/_consumers/`
2. `contracts/_consumers/<consumer>.yaml`

已有文件不会被覆盖。该文件只记录前端消费期望，不定义后端 Provider 接口；Provider 仍由对应服务维护 `contracts/<service>/api.yaml`。

## 执行

- **Bash**: `.specify/extensions/contract-governance/scripts/bash/init-consumer.sh --consumer <consumer-name> [--type frontend]`
- **PowerShell**: `.specify/extensions/contract-governance/scripts/powershell/init-consumer.ps1 -Consumer <consumer-name> [-Type frontend]`

示例：

```bash
.specify/extensions/contract-governance/scripts/bash/init-consumer.sh --consumer web-app
```
