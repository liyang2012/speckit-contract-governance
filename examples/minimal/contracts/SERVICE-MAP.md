# Example Contract Topology

> This file is a derived navigation view. Provider and Consumer files remain authoritative.

## 服务注册文件

| 服务 | Registry 文件 | 契约目录 |
|------|-------------|---------|
| catalog-service | [`_registry/catalog-service.yaml`](_registry/catalog-service.yaml) | `contracts/catalog-service/` |

## 服务清单

| 服务 | 数据库 | 核心职责 | 契约状态 |
|------|--------|---------|---------|
| catalog-service | db_catalog | Product catalog | CONFIRMED |

## Consumers

| Consumer | Type | Framework | Contract |
|----------|------|-----------|----------|
| web-app | frontend | React | `contracts/_consumers/web-app.yaml` |

## 契约变更规则

1. Each Provider owns its registry and contract directory.
2. Consumers declare expectations without redefining Provider operations.
3. Consumer status is `PENDING`, `RESOLVED`, or `MISMATCH`.
4. Services do not access another service's database directly.
