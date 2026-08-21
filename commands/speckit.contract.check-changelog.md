---
description: "校验 Provider 语义变化是否有 fingerprint 完整匹配的 x-changelog"
---

# 强制契约变更留痕

比较治理基线与当前工作区，对所有变化的 Provider 自动执行语义 diff。纯描述、注释和格式变化不产生语义变化；新增 Provider 契约按初始版本豁免。

## 通过条件

- 每项受治理的原子变化都由相对基线新增的 `changes[].fingerprint` 精确覆盖
- 同一 `method + path + operationId` 的变化位于同一个聚合条目
- fingerprint 不重复，聚合 `type` 与子变化一致
- 旧格式条目可以继续解析，但不能覆盖新门禁发现的变化

退出码：`0` 完整或本地无 Git 跳过；`1` 执行/配置错误；`2` 存在未记录或错误记录的语义变化。

## 执行

- Bash：`.specify/extensions/contract-governance/scripts/bash/check-changelog.sh [--base <git-ref>] [--service <name>] [--ci]`
- PowerShell：`.specify/extensions/contract-governance/scripts/powershell/check-changelog.ps1 [-Base <git-ref>] [-Service <name>] [-Ci]`

基线解析顺序为显式参数、项目 `changelog_baseline_ref`、本地 `HEAD`。CI 严格模式不允许隐式回退到 `HEAD`。
