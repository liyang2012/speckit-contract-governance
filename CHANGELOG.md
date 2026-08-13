# 变更日志

本文记录 `contract-governance` 扩展的重要变更。

## [Unreleased]

## [1.6.0] - 2026-08-13

### 新增
- 新增 `internal_service_auth_mode` 配置；`network-only` 模式下，`Feign` 与 `内部API` operation 不得声明或继承 OpenAPI `security`。
- 语义校验新增 `internal-service-auth-forbidden` 与 `internal-service-auth-mode-invalid` 门禁，同时支持通过 operation 级 `security: []` 覆盖顶层认证。
- 新增 Spec Kit 0.16.2 真实安装烟测，覆盖扩展注册表、Hook 优先级和 Codex 命令 Skill 物化。

### 变更
- 最低 Spec Kit 版本提升到 0.16.2，并补齐 `repository`、`homepage`、`category`、`effect`、核心命令依赖和显式 Hook 优先级元数据。
- CI Action 升级到 Node 24 运行时版本，并关闭无依赖锁文件的 uv 缓存。

### 修复
- 新增 `.extensionignore`，防止开发安装把 `.git`、CI 配置、本地学习记录和缓存复制到消费项目。

## [1.5.0] - 2026-07-22

### 新增
- 新增语言无关的内部 HTTP 契约模型：OpenAPI `tags: [内部API]`、后端 Registry `consumes.http` 和可配置的 `internal_http_tag`。
- 内部 HTTP operation 纳入 `/internal/` 路径、Consumer 状态、SERVICE-MAP 拓扑、breaking change 影响面和前端隔离校验。
- 初始化模板、Bash/PowerShell 结构校验、语义单元测试和 smoke test 同步覆盖 `consumes.http`。

### 文档
- CI 示例同时运行结构校验和 `--strict-warnings` 语义审计，避免 warning 在交付阶段被静默放行。

## [1.4.1] - 2026-07-15

### 修复
- 删除各 registry 中重复且可能漂移的 `feign_operations` / `mq_operations` 摘要。
- Feign Provider 能力统一从 OpenAPI `tags: [Feign]` 推导，事件 Provider 能力从 `contract_files.events` 推导，调用方统一从各 Consumer registry 的 `consumes` 推导。
- 语义校验新增 `registry-derived-summary-forbidden` 门禁，阻止重新引入 operation/callers 的第二份真相来源。
- 更新机制文档、通用检查清单、命令说明和 Skill 规则；测试增至 49 项 Bash smoke 和 12 项 Python 单元测试。

## [1.4.0] - 2026-07-14

### 新增
- 新增共享 Python/PyYAML 语义分析引擎，稳定解析 YAML/OpenAPI，降低固定缩进文本匹配风险。
- Consumer `required_fields` 现在会递归解析 `$ref`、`allOf`、数组和嵌套 schema；`RESOLVED` 缺字段会失败。
- OpenAPI diff 新增字段删除、类型/格式变化、必填变化、枚举收窄、参数、状态码、operationId 和 tags 语义检测。
- breaking change 自动列出前端 `_consumers` 和后端 `_registry` 影响面。
- 新增 `audit` 命令，支持运行时 OpenAPI、事件 schema、PENDING 老化以及 JSON/SARIF 报告。
- 新增 `sync-map` 命令；默认只预览，显式写入时从配置和契约注册表生成 SERVICE-MAP。
- SERVICE-MAP 校验新增 Provider、Consumer、状态和依赖关系漂移检查。
- 新增 `project_name` 与 `pending_max_age_days` 配置。

### 变更
- 扩展新增 `python3`/PyYAML 语义分析依赖；缺失时明确失败而不是静默降级。
- init-consumer 会把新 Consumer 补充到初始化生成的 SERVICE-MAP 索引。
- Bash smoke suite 扩展至 47 项，并新增 11 项 Python 单元测试。

## [1.3.2] - 2026-07-14

### 修复
- `diff-contract` 的 Consumer Contract 注入现在必须显式携带 `--write` / `-Write`，避免只读检查意外修改文件。
- Bash `--consumer` 与 PowerShell `-ConsumerFiles` 的文档统一为消费者文件路径，并补充写入保护 smoke 用例。
- 扩展默认配置、配置模板、README 与 Skill 对 `default_consumer` 和 1.3.x 可配置规则的描述保持一致。
- Skill 验证流程新增行为级 smoke suite 和扩展命令 Skill 注册检查。
- 扩展命令改用 Speckit 0.12.14 要求的 `speckit.contract-governance.*` 主命名空间，同时保留 `speckit.contract.*` 兼容别名。

## [1.3.1] - 2026-06-17

### 修复
- Bash 和 PowerShell 配置加载器现在支持读取项目级 `defaults:` 配置块，同时保持对顶层模板配置键的兼容。
- 新增 Bash smoke 测试，覆盖嵌套 `defaults:` 配置解析。

## [1.3.0] - 2026-06-06

### 新增
- 新增 `frontend_keywords` 配置项，用于在边界校验中识别项目特定的前端应用。
- 新增 `response_wrapper_schemas` 配置项，用于配置化校验 API 响应包装结构。
- 新增 PowerShell 共享模块 `common-utils.ps1`，从重复的内联逻辑中抽取公共函数。

### 变更
- 移除 validate-boundary.sh 和 validate-registry.sh 中硬编码的项目级前端标识与路径，改为由 `frontend_keywords` 配置驱动。
- 移除 validate-registry.sh 中硬编码的 `Result<T>` / `PageResult<T>` 检查，改为由 `response_wrapper_schemas` 配置驱动；为空时跳过该检查。
- 泛化 init-consumer.sh 模板示例，移除项目特定路径引用。
- 泛化命令文档示例，将项目级服务和前端名称替换为通用名称。
- 将 `Find-RepoRoot` 和 `Resolve-FeatureDir` 从 5 个 PowerShell 脚本中抽取到共享模块 `common-utils.ps1`。
- 将 SKILL.md 中 `default_consumer` 的回退值与实际配置默认值 `web-app` 对齐。
- 补充缺失的 PowerShell smoke 测试场景：错误 x-changelog 检测、diff-contract breaking change 检测。

### 修复
- PowerShell `common-config.ps1` 现在会加载 `frontend_keywords` 和 `response_wrapper_schemas`。

## [1.2.0] - 2026-06-06

### 新增
- 新增 `speckit.contract.diff` 命令：通过 git diff 检测契约变更，并生成 x-changelog 条目。
- diff-contract.sh 新增 `--consumer` 参数，用于将 breaking changes 注入到 consumer 文件。
- validate-registry.sh 新增 `x-changelog` 校验，检查 type、date、summary。
- Consumer contract 新增 `changes` 段，用于跟踪 breaking change 的确认状态。

### 变更
- 将扩展作者名称调整为 `spec-kit-community`。
- 所有脚本统一使用 `set -eo pipefail`，移除 `u` 标志以兼容 macOS bash 3.x。

## [1.1.0] - 2026-06-05

### 新增
- 新增 `speckit.contract.validate` 编排命令，统一执行边界校验和注册表校验。
- validate-registry.sh 和 validate-all.sh 新增 `--bootstrap-ok` 参数。
- 新增 Feign/internal 路径前缀校验。
- 新增 `前端API` + `Feign` 标签冲突检测，并允许通过 plan 中的例外说明放行。
- 强制校验 Consumer contract 的 `MISMATCH` 状态，要求同时记录 `mismatches` 和 `resolution`。

### 变更
- 将边界校验和注册表校验合并到 `validate-all.sh`。

## [1.0.0] - 2026-06-04

### 新增
- 初始版本：提供三层契约治理能力，包括 FE/BE 边界、微服务注册表、前端 Consumer Contract。
- 提供 6 个命令：init、init-consumer、validate-boundary、validate-registry、diff、validate。
- 提供 Bash 和 PowerShell 脚本实现。
- 提供配置模板，支持自定义 tags、statuses 和 changelog types。
- 提供 Bash 和 PowerShell 两个平台的 smoke 测试套件。
- 提供 CI 集成示例，包括 GitHub Actions 和 GitLab CI。
