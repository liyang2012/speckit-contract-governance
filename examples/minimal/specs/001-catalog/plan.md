# Plan: Catalog

## Scope and boundaries

- FE: `web-app` renders a product list and consumes only `前端API` operations.
- BE: `catalog-service` owns catalog behavior and `db_catalog`.
- Contract: the Provider owns `contracts/catalog-service/api.yaml`; the frontend owns
  `contracts/_consumers/web-app.yaml`.
- 禁止跨服务直连数据库。Services integrate through declared HTTP, Feign, or event contracts.

## Contract impact

The feature adds `listProducts`. There are no internal service operations or events.
