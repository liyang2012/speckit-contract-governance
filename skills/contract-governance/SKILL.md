---
name: contract-governance
description: 当用户需要初始化、校验、审计或同步 Spec Kit 契约治理时使用，包括 contracts 目录初始化、前端 Consumer Contract、FE/BE/Contract 分区、OpenAPI schema 与 required_fields 语义校验、Feign/internal 隔离与认证策略、breaking-change 影响面、x-changelog、SERVICE-MAP、运行时 OpenAPI、事件兼容性、PENDING 老化和 JSON/SARIF 报告。
---

# 契约治理

当用户要求初始化 `contracts/`、校验契约治理、检查 FE/BE/Contract 分区、检查微服务接口契约、初始化前端消费契约，或要求区分前端接口和 Feign 内部接口时，使用这个 Skill。

这个 Skill 封装当前仓库里的扩展：`.specify/extensions/contract-governance/`，要求 Spec Kit `>= 0.16.2`。优先执行扩展脚本，不要手工重新实现校验逻辑；只有脚本缺失或损坏时，才按规则人工检查并说明原因。

## 配置来源

项目级自定义值存放在 `.specify/extensions/contract-governance/contract-governance-config.yml`（由 `config-template.yml` 安装生成）。执行脚本或判断默认值时，**必须先读取该配置文件**，获取以下关键字段：

| 配置字段 | 用途 | 回退值 |
|---|---|---|
| `default_consumer` | init-consumer 默认前端消费方 | `web-app` |
| `project_name` | SERVICE-MAP 标题 | 空字符串 |
| `default_services` / `services` | 批量 init-registry 的服务/数据库列表；当前项目配置可能使用 `services` | 空列表 |
| `allowed_tags` | OpenAPI tags 分类白名单 | `前端API`, `Feign`, `内部API`, `外部API` |
| `internal_http_tag` | 语言无关后端 HTTP operation 的 tag | `内部API` |
| `internal_path_prefix` | Feign/内部 HTTP 路径前缀 | `/internal/` |
| `internal_service_auth_mode` | Feign/内部 HTTP 的认证策略；`network-only` 禁止 operation 声明或继承认证 | `provider-defined` |
| `frontend_keywords` | 前端范围识别关键词 | 空字符串 |
| `response_wrapper_schemas` | 标准响应包装 schema | 空字符串；为空时跳过检查 |
| `consumer_statuses` | Consumer 合法状态 | `PENDING`, `RESOLVED`, `MISMATCH` |
| `changelog_types` | x-changelog 合法类型 | `breaking`, `non-breaking`, `deprecated` |
| `change_ack_values` | Consumer 变更确认状态 | `PENDING_ACK`, `ACKNOWLEDGED` |
| `pending_max_age_days` | PENDING 老化告警阈值；`0` 关闭老化告警 | `30` |
| `changelog_enforcement` | Provider 语义变化留痕范围：`all`、`breaking`、`off` | `all` |
| `changelog_baseline_ref` | 增量治理比较基线；CI 必须配置或显式传入 | 空字符串 |

如果配置文件不存在，回退到 `extension.yml` 的 `config.defaults` 节点。

## 意图识别

用户说「初始化 contracts」「初始化契约注册表」「bootstrap contracts」时：

- 执行 `.specify/extensions/contract-governance/scripts/bash/init-registry.sh`。
- 如果用户指定了服务名，使用 `--service <服务名>`，必要时补充 `--database <数据库名>`。
- 如果用户没有指定服务名，读取配置文件的 `default_services` 列表；若不存在，再读取当前项目常用的 `services` 列表，逐个执行 `--service <name> --database <db>`。
- 如果配置文件不存在，且 `default_services` / `services` 均为空，提示用户指定服务名。
- 多服务初始化后，确认 `contracts/SERVICE-MAP.md` 已列出所有初始化服务。

用户说「初始化前端消费契约」「初始化 Consumer Contract」「web-app 消费契约」「前端拥有契约文件」时：

- 执行 `.specify/extensions/contract-governance/scripts/bash/init-consumer.sh --consumer <consumer-name>`。
- 如果用户没有指定 consumer，读取配置文件的 `default_consumer`（回退值 `web-app`）。
- 生成的 `contracts/_consumers/<consumer>.yaml` 只记录前端消费期望，不定义 Provider 接口。
- Provider operation 仍由对应服务维护 `contracts/<service>/api.yaml`。

用户说「校验契约治理」「检查契约」「跑 contract governance」时：

- 执行 `.specify/extensions/contract-governance/scripts/bash/validate-all.sh`。
- 如果用户明确说明这是全新项目、初始化阶段或允许 bootstrap，追加 `--bootstrap-ok`。

用户说「校验前后端边界」「检查 FE/BE/Contract」时：

- 执行 `.specify/extensions/contract-governance/scripts/bash/validate-boundary.sh --all`。
- 只有当用户明确限定检查范围时，才改用 `--plan` 或 `--tasks`。

用户说「校验微服务契约」「检查 registry」「检查 Feign/内部 HTTP/MQ」时：

- 执行 `.specify/extensions/contract-governance/scripts/bash/validate-registry.sh`。
- 如果用户指定服务名，追加 `--service <服务名>`。
- 如果用户指定前端消费方，追加 `--consumer <consumer-name>`。

用户说「检查契约变更」「diff 契约」「contract diff」「生成 x-changelog」时：

- 默认只读执行 `.specify/extensions/contract-governance/scripts/bash/diff-contract.sh --service <服务名>`，只输出变更和建议的 YAML，不写文件。
- 服务名是必填项。用户未指定时，先只读检查变更的 `contracts/*/api.yaml`；只能唯一确定服务时才推断，否则询问用户。
- 用户指定基线时追加 `--base <git-ref>`。
- 单独执行 diff 时，只有用户明确要求写入 x-changelog 才追加 `--write`。
- **如果用户已经授权修改既有 Provider `contracts/<service>/api.yaml`，同文件的 `x-changelog` 是该语义修改的必要组成，不需要再次询问授权。完成 Provider 修改后必须自动执行 `diff-contract --service <service> --write`，并执行 `check-changelog --service <service>` 验证 fingerprint 完整覆盖。**
- 只有用户明确要求同步 Consumer Contract 时，才追加 `--write --consumer contracts/_consumers/<consumer-name>.yaml`；`--consumer` 接受文件路径而不是 consumer 名称，并且必须与 `--write` 同时使用。consumer 名称未指定时读取配置文件的 `default_consumer`。
- 脚本通过只读 Git 历史检测变更；不得因为“检查契约变更”自动 stage、commit、切换分支或写入契约文件。
- 语义 diff 必须覆盖 operation、参数、响应字段、类型/格式、必填、枚举、状态码、operationId 和 tags，并报告 `_registry` / `_consumers` 影响面。

用户说「检查 changelog 门禁」「强制变更留痕」「check changelog」时：

- 执行 `.specify/extensions/contract-governance/scripts/bash/check-changelog.sh`。
- 用户指定基线时追加 `--base <git-ref>`；指定服务时追加 `--service <服务名>`。
- CI/严格门禁场景追加 `--ci`。CI 缺 Git、缺基线或基线不可读必须失败；本地无 Git只告警并跳过。
- 退出码 `2` 表示存在未记录、部分记录、重复 fingerprint 或错误聚合的语义变化。

用户说「深度审计契约」「检查 required_fields」「对比 SpringDoc」「输出 JSON/SARIF」「检查事件兼容」「检查过期 PENDING」时：

- 执行 `.specify/extensions/contract-governance/scripts/bash/audit-contracts.sh`。
- 输出机器可读报告时追加 `--format json` 或 `--format sarif`。
- 对比运行时 OpenAPI 时使用 `--service <name> --runtime-openapi <导出文件>`；只读取导出文件，不自动请求线上服务。
- 对比事件 schema 时使用 `--event-old <file> --event-new <file>`。
- warning 也需要阻断时追加 `--strict-warnings`。

用户说「同步 SERVICE-MAP」「生成服务地图」「检查服务拓扑漂移」时：

- 默认只读执行 `.specify/extensions/contract-governance/scripts/bash/sync-service-map.sh` 预览。
- 只有用户明确要求写入时，才追加 `--write`。
- 同步来源必须是项目配置、`_registry`、Provider OpenAPI 和 `_consumers`；不要凭聊天内容编造服务关系。

## 初始化提示词写法

初始化契约治理时，如果用户没有明确服务名，先按这些信号分辨：

- Provider 服务：独立部署单元、独立应用、独立数据库 owner、API owner、Feign Provider、内部 HTTP Provider 或 MQ Provider。
- 前端 consumer：Vue/Vite/React 应用、页面模块、前端 API client、BFF 消费方。
- 不把前端 consumer 当作 Provider 服务；前端只写 `contracts/_consumers/<consumer>.yaml`。
- 不把一个业务 feature 拆成多个 feature；在同一个 `plan.md` 内分 FE、BE、Contract 区。

可直接使用这类初始化提示词：

```text
使用 contract-governance 初始化当前 feature 的契约治理。
先根据部署单元、数据库 owner、API owner、Feign/内部 HTTP/MQ Provider 分辨后端服务；
前端按 consumer 处理，默认 consumer 从 contract-governance-config.yml 的 default_consumer 读取。
后端 Provider 初始化 contracts/_registry/<service>.yaml 和 contracts/<service>/api.yaml；
前端只初始化 contracts/_consumers/<consumer>.yaml，用于记录 required_fields、evidence 和 PENDING/RESOLVED/MISMATCH。
前端只能消费 tags 为配置 allowed_tags 白名单的 operation，不能消费 Feign 或 internal_path_prefix 路径。
```

## 核心规则

- `spec.md` 只写业务能力和验收口径；实现细节和接口细节放到 `plan.md`、`contracts/`、`data-model.md`、`quickstart.md` 和 `tasks.md`。
- 一个业务能力通常只建一个 feature 目录；前端、后端、契约工作在 `plan.md` 和 `tasks.md` 内部分区。
- `contracts/` 是项目级共享契约注册表；`specs/<feature>/contracts/` 只作为 feature 内临时草稿。
- 每个服务只能维护自己的 `contracts/_registry/<service>.yaml` 和 `contracts/<service>/`。
- 前端只能维护自己的 `contracts/_consumers/<consumer>.yaml`，用来记录消费期望、必要字段、页面/客户端证据和状态。
- 前端 Consumer Contract 不定义 Provider operation，也不改变 `contracts/<service>/api.yaml` 的所有权。
- OpenAPI operation 的 `tags` 是调用方边界来源，以配置文件的 `allowed_tags` 为准；当前默认值为 `前端API`、`Feign`、`内部API`、`外部API`。
- `Feign` operation 只允许其他后端服务调用，路径必须匹配配置文件的 `internal_path_prefix`；当前默认值为 `/internal/`。
- 语言无关的后端 HTTP operation 使用配置的 `internal_http_tag`（默认 `内部API`），调用方登记到 `consumes.http`，路径同样必须匹配 `internal_path_prefix`。
- `internal_service_auth_mode=network-only` 时，`Feign` 和配置的内部 HTTP operation 不得声明或继承 OpenAPI `security`；如果契约顶层声明了认证，必须在内部 operation 显式写 `security: []`。该规则只约束服务间内部接口，不取消前端/外部接口的 Token 认证。
- 前端消费契约中 `RESOLVED` 的 operationId 必须能在 Provider `api.yaml` 中找到，且 tags 必须是 `前端API` 或 `外部API`。
- `RESOLVED` 的 `required_fields` 必须能递归解析到 Provider 成功响应 schema；仅 operationId 同名不足以自动确认业务语义。
- 同一个 operation 不应同时标记 `前端API` 和 `Feign`。如果确实无法拆分，`plan.md` 必须明确共享接口例外、权限模型、字段暴露风险和兼容策略。
- 如果配置了 `response_wrapper_schemas`，Provider OpenAPI 必须声明或引用至少一个匹配的标准响应包装 schema。
- Consumer 状态、x-changelog 类型和变更确认状态分别以 `consumer_statuses`、`changelog_types`、`change_ack_values` 为准。
- `changelog_enforcement=all` 时，既有 Provider 的 breaking 与 non-breaking 语义变化都必须按 operation 聚合写入 `x-changelog`；纯描述、注释、格式变化和新增 Provider 初始版本豁免。
- 新格式 `x-changelog` 的每项原子变化必须带稳定 SHA-256 fingerprint；旧格式条目继续可解析，但不能覆盖门禁检测到的新变化。
- registry 不维护 `provides`、`feign_operations`、`http_operations` 或 `mq_operations` 等派生摘要；Feign/内部 HTTP/MQ Provider 能力从契约文件推导，调用方从各 Consumer registry 的 `consumes` 推导。
- SERVICE-MAP 必须覆盖已注册 Provider、前端 Consumer 和 registry 中的跨服务依赖；状态漂移需要报告。
- 不自动把 PENDING 改成 RESOLVED；语义分析通过后仍需确认权限、错误语义和业务含义。
- 如果 `plan.md` 涉及 Feign 或配置的 `internal_path_prefix`，`tasks.md` 必须包含网关限制、访问控制和内部接口隔离相关任务；是否允许服务级认证由 `internal_service_auth_mode` 决定。

## 操作边界

- 除非用户明确要求，不执行 Git 写操作；`diff-contract` 场景只允许读取 Git 历史。
- 修改既有 Provider 契约的授权自动包含同文件 `x-changelog` 写入，但不包含 Consumer ack、SERVICE-MAP 写入或任何 Git 写操作；这些操作仍需独立授权。
- 除非用户明确要求恢复历史文件，不使用 `git restore`、`git checkout` 或破坏性清理来恢复已删除的 `contracts/`。
- `init-registry.sh` 只创建空白骨架，不恢复旧的 OpenAPI 端点、事件 schema 或历史契约内容。
- 如果发现已有 `contracts/` 文件处于删除状态，同时又存在未跟踪的新骨架文件，要如实报告状态，不要静默 stage、恢复或合并。

## 验证方式

修改脚本或初始化契约后，优先运行：

```bash
.specify/extensions/contract-governance/scripts/bash/validate-registry.sh
.specify/extensions/contract-governance/scripts/bash/validate-all.sh --bootstrap-ok
```

修改扩展脚本后，还要运行：

```bash
bash -n .specify/extensions/contract-governance/scripts/bash/init-registry.sh \
  .specify/extensions/contract-governance/scripts/bash/init-consumer.sh \
  .specify/extensions/contract-governance/scripts/bash/validate-boundary.sh \
  .specify/extensions/contract-governance/scripts/bash/validate-registry.sh \
  .specify/extensions/contract-governance/scripts/bash/validate-all.sh \
  .specify/extensions/contract-governance/scripts/bash/diff-contract.sh \
  .specify/extensions/contract-governance/scripts/bash/check-changelog.sh

.specify/extensions/contract-governance/scripts/bash/test-smoke.sh
PYTHONDONTWRITEBYTECODE=1 python3 .specify/extensions/contract-governance/scripts/python/test_contract_analyzer.py -v
```

修改本 Skill 后，运行 skill-creator 的 `quick_validate.py` 校验目录；重新安装或注册扩展后，还要确认 `.specify/extensions/.registry` 的 `registered_commands.codex` 包含 `speckit.contract-governance.*` 主命令，并存在对应的 `.agents/skills/speckit-contract-governance-*` 命令 Skill。Spec Kit 0.16.2 会把扩展命令及其兼容别名分别物化为 Skill，因此 `registered_skills` 可以为空；自动化和新文档统一使用 `speckit.contract-governance.*` 主命令。
