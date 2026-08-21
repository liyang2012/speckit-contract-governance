# Spec Kit Contract Governance

FE/BE 契约边界、微服务 Provider 契约和前端 Consumer Contract 的 Spec Kit 扩展，并提供 schema 语义校验、影响面分析、运行时漂移检查和结构化报告。

这是一个独立、项目无关的开源实现。仓库只维护治理模型、Spec Kit 扩展、Agent Skill、跨平台脚本、测试和通用示例；业务项目自己的服务清单、运行配置、契约内容和历史告警基线不进入本仓库。

许可证：MIT。当前版本：`1.7.0`。要求 Spec Kit `>= 0.16.2`。

## 设计原则

- Provider 的唯一真相源是 `contracts/<service>/api.yaml` 或该服务拥有的事件 schema。
- 后端 Consumer 在自己的 `contracts/_registry/<consumer>.yaml` 中声明 `consumes`。
- 前端 Consumer 只在 `contracts/_consumers/<consumer>.yaml` 中声明消费期望，不能定义 Provider operation。
- `SERVICE-MAP.md` 是可再生视图，不是第二份契约真相源。
- 校验通过只代表没有结构硬错误；`PENDING`、运行时漂移和业务语义确认仍是交付门禁。

## 三层架构

| 层级 | 模块 | 职责 |
|------|------|------|
| 第一层 | FE/BE/Contract Boundary | 判断一个 feature 是否保持一个业务真相来源，并显式拆出 FE、BE、Contract 边界 |
| 第二层 | Microservice Contract Governance | 初始化和校验根目录 `contracts/` 注册表，约束服务所有权、Provider/Consumer、Feign/内部 HTTP/MQ 和跨服务安全规则 |
| 第三层 | Frontend Consumer Contract | 允许前端在 `contracts/_consumers/<consumer>.yaml` 记录消费期望，但不允许前端定义后端 Provider 接口 |

## Quick Start

### 1. 安装

克隆或下载本项目后，在目标 Spec Kit 项目中执行：

```bash
specify extension add --dev /absolute/path/to/speckit-contract-governance
```

Spec Kit 0.16.2 会读取仓库根目录的 `.extensionignore`，因此开发安装只复制扩展运行所需内容，不会把源仓库的 `.git`、CI 配置、本地学习记录或缓存带入目标项目。

也可以将本项目内容复制到目标项目的 `.specify/extensions/contract-governance/`，再按 Spec Kit 扩展注册机制注册。

### 2. 配置

按需编辑 `contract-governance-config.yml`（从 `config-template.yml` 复制），自定义 tags、consumer 名称等。

语义分析需要 `python3` 和 PyYAML。Spec Kit 通常已携带 PyYAML；如果当前 Python 环境缺失，运行 `python3 -m pip install pyyaml`。

### 3. 初始化

后端 Provider 服务：

```bash
.specify/extensions/contract-governance/scripts/bash/init-registry.sh --service <service-name> --database <database-name>
```

前端 Consumer：

```bash
.specify/extensions/contract-governance/scripts/bash/init-consumer.sh --consumer <consumer-name>
```

### 4. 生成目录结构

初始化后生成的目录结构示例：

```text
contracts/
├── SERVICE-MAP.md
├── _registry/
│   └── my-service.yaml
├── _consumers/
│   └── web-app.yaml
└── my-service/
    ├── api.yaml
    └── events/
        └── .gitkeep
```

`_consumers/web-app.yaml` 只表达前端需要消费哪些 Provider operation、页面/客户端证据、必要字段和状态；实际接口仍归 `contracts/<service>/api.yaml` 所属服务维护。

## 服务分类原则

初始化时用服务所有权来分辨 Provider 和 Consumer：

- **后端 Provider**：独立部署单元、独立数据库 owner、API owner、Feign Provider、内部 HTTP Provider 或 MQ Provider。
- **前端 Consumer**：Vue/Vite/React 应用、页面模块、前端 API client 或 BFF 消费方。
- 前端 Consumer 不进入 `contracts/_registry/<service>.yaml`，只进入 `contracts/_consumers/<consumer>.yaml`。

## 命令

命令主命名空间为 `speckit.contract-governance.*`；为兼容已有调用，继续保留对应的 `speckit.contract.*` 别名。Spec Kit 0.16.2 的 Codex 集成会把主命令和兼容别名分别物化为命令 Skill；新调用应统一使用主命名空间。

- `speckit.contract-governance.init`（兼容别名：`speckit.contract.init`）
  - 初始化根目录 `contracts/` 契约注册表。
  - 创建服务自己的 `_registry/<service>.yaml`、`contracts/<service>/api.yaml` 和 `events/` 目录。
  - 只用于后端 Provider 服务，不用于前端定义接口。

- `speckit.contract-governance.init-consumer`（兼容别名：`speckit.contract.init-consumer`）
  - 初始化 `contracts/_consumers/<consumer>.yaml`。
  - 只记录前端消费期望，不创建或修改 Provider `api.yaml`。

- `speckit.contract-governance.validate-boundary`（兼容别名：`speckit.contract.validate-boundary`）
  - 校验当前 feature 的 `plan.md` / `tasks.md` 是否明确 FE/BE/Contract 边界。
  - 全新项目缺少 `contracts/` 时只给 warning，不阻断 bootstrap。

- `speckit.contract-governance.validate-registry`（兼容别名：`speckit.contract.validate-registry`）
  - 校验 `contracts/SERVICE-MAP.md`、`_registry/*.yaml`、`api.yaml` 和事件 schema 的基础一致性。
  - 校验 Consumer 状态只能是 `PENDING`、`RESOLVED`、`MISMATCH`。
  - 校验 registry 中的 `contract_files`、`contract_path` 指向真实文件。
  - 校验 OpenAPI operation 必须用 tags 声明调用方类型（默认：`前端API`、`Feign`、`内部API`、`外部API`，可在配置中自定义）。
  - 校验 `Feign` 和 `内部API` 接口路径必须包含 `/internal/`，默认不允许前端直接调用。
  - 可配置内部服务认证策略；`internal_service_auth_mode: network-only` 时，`Feign` 和 `内部API` operation 不得声明或继承 OpenAPI `security`。
  - 禁止同一 operation 同时标记 `前端API` 和 `Feign`；如确需共用，必须在 `plan.md` 声明共用接口例外、权限模型、字段暴露风险和兼容策略。
  - 校验前端消费契约只能引用已注册 Provider，`RESOLVED` 必须能找到对应 operationId。
  - 校验前端消费契约不得消费 `Feign` 或 `内部API` operation，只能消费 `前端API` 或 `外部API`。
  - 校验后端 `consumes.http` 的 `RESOLVED` operation 存在且标记为配置的 `internal_http_tag`。
  - 如果当前 feature plan 涉及微服务，要求 plan 写明禁止跨服务直连数据库或等价约束。

- `speckit.contract-governance.diff`（兼容别名：`speckit.contract.diff`）
  - 对比契约文件 git 历史变更，语义识别 operation、字段、类型、必填、枚举、状态码和 tags 变化。
  - 输出前端 `_consumers` 与后端 `_registry` Consumer 影响面，并生成 x-changelog 和消费者 changes 段。
  - 退出码：`0` = 仅 non-breaking 或无变更；`2` = 存在 breaking changes。

- `speckit.contract-governance.check-changelog`（兼容别名：`speckit.contract.check-changelog`）
  - 对比治理基线，自动发现变化的 Provider，并要求所有语义变化都有 fingerprint 完整匹配的新增 `x-changelog`。
  - 纯描述、注释和格式变化自动豁免；新增 Provider 按初始版本豁免。
  - 退出码：`0` = 完整；`1` = 执行或配置错误；`2` = 缺失、部分覆盖、重复 fingerprint 或聚合错误。

- `speckit.contract-governance.validate`（兼容别名：`speckit.contract.validate`）
  - 编排运行边界校验和 registry 校验。
  - 用于 `/speckit-tasks` 前后这类必须同时检查两层规则的门禁。

- `speckit.contract-governance.audit`（兼容别名：`speckit.contract.audit`）
  - 校验 Consumer `required_fields`、Feign/内部 HTTP 语义、PENDING 老化、SERVICE-MAP 漂移和 breaking ack。
  - 支持运行时 OpenAPI、事件 schema 兼容性，以及 text/JSON/SARIF 报告。

- `speckit.contract-governance.sync-map`（兼容别名：`speckit.contract.sync-map`）
  - 从配置、registry、Provider OpenAPI 和 Consumer Contract 推导 SERVICE-MAP。
  - 默认只预览，只有显式 `--write` / `-Write` 才修改文件。

## 手动运行

初始化单个服务：

```bash
.specify/extensions/contract-governance/scripts/bash/init-registry.sh --service my-service --database db_myapp
```

初始化前端消费方：

```bash
.specify/extensions/contract-governance/scripts/bash/init-consumer.sh --consumer web-app
```

校验 FE/BE/Contract 边界：

```bash
.specify/extensions/contract-governance/scripts/bash/validate-boundary.sh --plan
.specify/extensions/contract-governance/scripts/bash/validate-boundary.sh --tasks
```

校验所有服务：

```bash
.specify/extensions/contract-governance/scripts/bash/validate-registry.sh
```

校验指定服务：

```bash
.specify/extensions/contract-governance/scripts/bash/validate-registry.sh --service my-service
```

校验指定前端消费方：

```bash
.specify/extensions/contract-governance/scripts/bash/validate-registry.sh --consumer web-app
```

全新项目 bootstrap 阶段可以使用宽松模式：

```bash
.specify/extensions/contract-governance/scripts/bash/validate-registry.sh --bootstrap-ok
```

运行三层综合校验：

```bash
.specify/extensions/contract-governance/scripts/bash/validate-all.sh
.specify/extensions/contract-governance/scripts/bash/validate-all.sh --phase plan --bootstrap-ok
```

检测契约变更：

```bash
.specify/extensions/contract-governance/scripts/bash/diff-contract.sh --service my-service
.specify/extensions/contract-governance/scripts/bash/diff-contract.sh --service my-service --write
.specify/extensions/contract-governance/scripts/bash/diff-contract.sh --service my-service --base origin/main --write --consumer contracts/_consumers/web-app.yaml
.specify/extensions/contract-governance/scripts/bash/check-changelog.sh --ci
```

执行语义审计或输出 CI 报告：

```bash
.specify/extensions/contract-governance/scripts/bash/audit-contracts.sh
.specify/extensions/contract-governance/scripts/bash/audit-contracts.sh --format sarif
.specify/extensions/contract-governance/scripts/bash/audit-contracts.sh --service my-service --runtime-openapi build/openapi.json
```

预览或同步 SERVICE-MAP：

```bash
.specify/extensions/contract-governance/scripts/bash/sync-service-map.sh
.specify/extensions/contract-governance/scripts/bash/sync-service-map.sh --write
```

## CI 集成

在 CI 流水线中依次运行 changelog 门禁、结构校验和严格语义审计。`check-changelog.sh --ci` 强制增量留痕，`validate-all.sh` 负责硬错误，`audit-contracts.sh --strict-warnings` 会让 warning 返回 exit `2`。

已有项目如果存在历史 warning，应使用仓库级精确基线暂时放行已知项，并在新增或消失的 warning 出现时阻断；不要永久关闭 `--strict-warnings`。

### GitHub Actions

```yaml
jobs:
  contract-check:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Validate contracts
        run: |
          bash .specify/extensions/contract-governance/scripts/bash/check-changelog.sh --ci
          bash .specify/extensions/contract-governance/scripts/bash/validate-all.sh --bootstrap-ok
          bash .specify/extensions/contract-governance/scripts/bash/audit-contracts.sh --strict-warnings
```

### GitLab CI

```yaml
contract-validation:
  script:
    - bash .specify/extensions/contract-governance/scripts/bash/check-changelog.sh --ci
    - bash .specify/extensions/contract-governance/scripts/bash/validate-all.sh --bootstrap-ok
    - bash .specify/extensions/contract-governance/scripts/bash/audit-contracts.sh --strict-warnings
  rules:
    - changes:
        - contracts/**/*
```

## 治理规则

- 每个服务只写自己的 `contracts/_registry/<service>.yaml` 和 `contracts/<service>/`。
- Provider 在自己的 `api.yaml` 或 `events/` 中定义端点和事件。
- Consumer 在自己的 registry 的 `consumes.feign`、`consumes.http` 或 `consumes.mq` 中声明期望。
- 前端 Consumer 在 `contracts/_consumers/<consumer>.yaml` 中声明 HTTP 消费期望、必要字段和页面/客户端证据。
- 前端 Consumer 不定义 Provider 端点，不修改 `contracts/<service>/api.yaml` 的服务所有权。
- `PENDING` 表示期望尚未被提供方确认。
- `RESOLVED` 表示消费方已确认提供方契约满足需求。
- `MISMATCH` 表示提供方契约与消费方期望不一致，必须记录差异和决议。
- 微服务之间禁止跨服务直连数据库，必须通过 Feign、内部 HTTP、MQ 或明确的外部接口契约交互。
- 前端只能调用 `tags: [前端API]` 或明确标记 `外部API` 的接口。
- 其他后端服务通过 Feign 调用 `tags: [Feign]` 的接口，且路径必须使用 `/internal/`。
- 非 Feign 的后端 HTTP 调用登记到 `consumes.http`，Provider 使用 `tags: [内部API]`，且路径必须使用 `/internal/`。
- `internal_service_auth_mode: network-only` 时，内部 operation 不使用服务级 Token；若 OpenAPI 顶层配置了认证，内部 operation 必须用 `security: []` 显式覆盖。前端和外部接口的认证不受影响。
- `前端API` 和 `Feign` 默认不能共用同一个 operation；共用必须在 plan 中写明例外理由和风险控制。
- `RESOLVED` Consumer 的 `required_fields` 必须能在 Provider 成功响应 schema 中解析。
- PENDING 超过配置阈值会产生老化告警，但不会自动修改状态。
- SERVICE-MAP 必须覆盖注册的 Provider、Consumer 和 registry 中的跨服务依赖。
- registry 不得重复维护 `provides`、`feign_operations` 或 `mq_operations`；Provider 能力从 OpenAPI/事件契约推导，调用方从各 Consumer 的 `consumes` 推导。
- breaking change 必须列出受影响 Consumer，并跟踪 `PENDING_ACK` / `ACKNOWLEDGED`。
- 既有 Provider 的所有 breaking/non-breaking 语义变化都必须按 operation 聚合写入 `x-changelog`；每项原子变化使用规范 JSON 的 SHA-256 fingerprint 去重和验收。
- 修改既有 Provider 契约时，同文件的 changelog 是必要组成；Consumer ack、SERVICE-MAP 和 Git 写操作仍需独立授权。

## 可配置项

所有规则均可通过 `contract-governance-config.yml` 自定义：

| 配置项 | 说明 | 默认值 |
|--------|------|--------|
| `default_consumer` | init-consumer 的默认消费方名称 | `web-app` |
| `project_name` | SERVICE-MAP 标题使用的项目名称 | `""` |
| `default_services` | 批量初始化提示的服务列表 | `[]` |
| `allowed_tags` | OpenAPI operation 允许的调用方标签 | `前端API`, `Feign`, `内部API`, `外部API` |
| `internal_http_tag` | 语言无关后端 HTTP operation 使用的 tag | `内部API` |
| `internal_path_prefix` | Feign/内部 HTTP 接口必须包含的路径前缀 | `/internal/` |
| `internal_service_auth_mode` | 内部接口认证策略：`provider-defined` 或 `network-only` | `provider-defined` |
| `frontend_keywords` | 边界校验中额外的前端应用关键词（逗号分隔） | `""` |
| `response_wrapper_schemas` | 响应包装 schema 名称模式（逗号分隔，空则跳过检查） | `""` |
| `consumer_statuses` | 合法的 consumer 状态值 | `PENDING`, `RESOLVED`, `MISMATCH` |
| `changelog_types` | 合法的 x-changelog 类型 | `breaking`, `non-breaking`, `deprecated` |
| `change_ack_values` | 合法的变更确认状态 | `PENDING_ACK`, `ACKNOWLEDGED` |
| `pending_max_age_days` | PENDING 老化告警阈值；`0` 表示关闭 | `30` |
| `changelog_enforcement` | 留痕范围：`all`、`breaking` 或 `off` | `all` |
| `changelog_baseline_ref` | 增量治理基线；CI 必须配置或传 `--base` | `""` |

## 开发与发布

本项目要求 Bash、Python 3 和 PyYAML。提交变更前运行：

```bash
bash -n scripts/bash/*.sh
bash scripts/bash/test-smoke.sh
PYTHONDONTWRITEBYTECODE=1 python3 scripts/python/test_contract_analyzer.py -v
PYTHONDONTWRITEBYTECODE=1 python3 scripts/python/validate_distribution.py
```

如果环境提供 PowerShell，再运行：

```powershell
pwsh -File scripts/powershell/test-smoke.ps1
```

行为规则、兼容性要求和发布流程见 [CONTRIBUTING.md](CONTRIBUTING.md)，规范模型见 [docs/contract-model.md](docs/contract-model.md)。
