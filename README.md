<div align="center">

<img src="assets/project-banner.svg" alt="Animated Stockroom inventory and order banner" width="900" />

# Stockroom — Inventory & Order Manager

**Accurate stock, reliable fulfillment, and fewer inventory surprises.**

[![React](https://img.shields.io/badge/React-19-149eca?logo=react)](https://react.dev/)
[![TypeScript](https://img.shields.io/badge/TypeScript-5-3178c6?logo=typescript)](https://www.typescriptlang.org/)
[![Vite](https://img.shields.io/badge/Vite-6-646cff?logo=vite)](https://vite.dev/)
[![License: MIT](https://img.shields.io/badge/License-MIT-2d6a58.svg)](LICENSE)

</div>

## Product scope

Stockroom gives small retail operations one place to review stock, catch products below their reorder point, receive stock, and move orders through fulfillment.

## Current release

The interactive demo supports product creation, category and text filtering, stock adjustments, order fulfillment with stock checks, and a movement log. Demo state persists in this browser with `localStorage`. No database, user accounts, suppliers, or live warehouse integrations are connected yet; use sample data only.

## Run locally

```bash
npm install
npm run dev
```

Open [http://localhost:5173](http://localhost:5173).

## Planned production architecture

- Supabase Auth and tenant-scoped PostgreSQL tables with row-level security.
- Append-only `stock_movements` ledger; current stock derived or reconciled from ledger entries.
- Atomic order reservation and fulfillment transactions with idempotency keys.
- Low-stock events, supplier purchase orders, and warehouse location support.
- Operator audit log and role-based permissions for stock corrections.

## Data model sketch

`products(id, tenant_id, sku, name, reorder_point, unit_cost)`

`stock_movements(id, product_id, delta, reason, order_id, actor_id, created_at)`

`orders(id, tenant_id, status, idempotency_key, created_at)`

## Stack

React · TypeScript · Vite · Lucide · CSS · browser `localStorage`

## License

MIT. See [LICENSE](LICENSE).

