---
description: "根据配置、服务注册表和 Consumer Contract 预览或同步 SERVICE-MAP.md"
---

# 同步 SERVICE-MAP

从项目配置、`contracts/_registry/*.yaml`、Provider OpenAPI 和 `contracts/_consumers/*.yaml` 推导服务地图。

默认只输出预览，不修改文件；只有显式 `--write` / `-Write` 才写入 `contracts/SERVICE-MAP.md`。

## 执行

- **Bash**: `.specify/extensions/contract-governance/scripts/bash/sync-service-map.sh [--write]`
- **PowerShell**: `.specify/extensions/contract-governance/scripts/powershell/sync-service-map.ps1 [-Write]`

示例：

```bash
.specify/extensions/contract-governance/scripts/bash/sync-service-map.sh
.specify/extensions/contract-governance/scripts/bash/sync-service-map.sh --write
```

同步内容包括 Provider、数据库、契约路径、Feign/内部 HTTP/MQ 能力、前端 Consumer、服务依赖和 tag 分类。
