<div align="center">

<img src="assets/project-banner.svg" alt="Animated Stockroom — Inventory & Order Manager banner" width="900" />

# Stockroom — Inventory & Order Manager

**Accurate stock, reliable fulfillment, and fewer inventory surprises.**

React · PostgreSQL · Supabase · Tailwind CSS

![Project status](https://img.shields.io/badge/status-in%20progress-7a8b71)

</div>

## Product scope

Inventory ledger and order lifecycle with explicit reservations, adjustments, and low-stock signals.

## Architecture notes

Postgres constraints protect quantities; stock movements form the audit ledger; order placement reserves stock transactionally; RLS scopes operator access.

### Data model sketch

    products(id, sku, name, reorder_point) · stock_movements(id, product_id, delta, reason, order_id, created_at) · orders(id, status, created_at)

## Stack

React · PostgreSQL · Supabase · Tailwind CSS

## Build sequence

1. Catalog and stock ledger
2. Order reservation and release
3. Reorder rules and operations view
4. Policies and audit trail

## Current status

Public repository with an animated README. Product code is being built incrementally, one project at a time. This page records the planned product boundary and engineering milestones.

## License

MIT.
