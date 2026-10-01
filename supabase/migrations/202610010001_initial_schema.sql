-- Stockroom reference schema: workspace-scoped catalog, stock ledger, and orders.
create table public.workspaces (
  id uuid primary key default gen_random_uuid(),
  name text not null check (length(trim(name)) between 1 and 120),
  owner_id uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now()
);

create table public.workspace_members (
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null check (role in ('owner','admin','manager','viewer')),
  created_at timestamptz not null default now(),
  primary key (workspace_id, user_id)
);

create table public.products (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  sku text not null,
  name text not null check (length(trim(name)) between 1 and 180),
  category text not null,
  unit_cost numeric(12,2) not null default 0 check (unit_cost >= 0),
  quantity_on_hand integer not null default 0 check (quantity_on_hand >= 0),
  reorder_point integer not null default 0 check (reorder_point >= 0),
  location text,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (workspace_id, sku),
  unique (id, workspace_id)
);

create table public.orders (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.workspaces(id) on delete restrict,
  order_number text not null,
  customer_name text not null,
  status text not null default 'pending' check (status in ('pending','processing','fulfilled','cancelled')),
  idempotency_key text not null,
  created_at timestamptz not null default now(),
  fulfilled_at timestamptz,
  unique (workspace_id, order_number),
  unique (workspace_id, idempotency_key),
  unique (id, workspace_id)
);

create table public.order_items (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  order_id uuid not null,
  product_id uuid not null,
  quantity integer not null check (quantity > 0),
  unit_price numeric(12,2) not null check (unit_price >= 0),
  unique (order_id, product_id),
  foreign key (order_id, workspace_id) references public.orders(id, workspace_id) on delete cascade,
  foreign key (product_id, workspace_id) references public.products(id, workspace_id) on delete restrict
);

create table public.stock_movements (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  product_id uuid not null,
  order_id uuid,
  actor_id uuid references auth.users(id) on delete set null,
  quantity_delta integer not null check (quantity_delta <> 0),
  reason text not null check (reason in ('receipt','adjustment','fulfillment','return')),
  note text,
  created_at timestamptz not null default now(),
  foreign key (product_id, workspace_id) references public.products(id, workspace_id) on delete restrict,
  foreign key (order_id, workspace_id) references public.orders(id, workspace_id) on delete restrict
);

create index products_workspace_category_idx on public.products(workspace_id, category) where active;
create index products_low_stock_idx on public.products(workspace_id, quantity_on_hand, reorder_point) where active;
create index orders_workspace_status_idx on public.orders(workspace_id, status, created_at desc);
create index stock_movements_product_created_idx on public.stock_movements(product_id, created_at desc);

create or replace function public.is_workspace_member(target_workspace uuid)
returns boolean language sql stable security definer set search_path = public, auth as $$
  select exists (
    select 1 from public.workspace_members m
    where m.workspace_id = target_workspace and m.user_id = auth.uid()
  );
$$;

create or replace function public.can_manage_workspace(target_workspace uuid)
returns boolean language sql stable security definer set search_path = public, auth as $$
  select exists (
    select 1 from public.workspace_members m
    where m.workspace_id = target_workspace and m.user_id = auth.uid()
      and m.role in ('owner','admin','manager')
  );
$$;

alter table public.workspaces enable row level security;
alter table public.workspace_members enable row level security;
alter table public.products enable row level security;
alter table public.orders enable row level security;
alter table public.order_items enable row level security;
alter table public.stock_movements enable row level security;

create policy workspace_member_read on public.workspaces for select
  using (public.is_workspace_member(id));
create policy workspace_owner_create on public.workspaces for insert
  with check (owner_id = auth.uid());
create policy member_list_read on public.workspace_members for select
  using (public.is_workspace_member(workspace_id));
create policy member_admin_write on public.workspace_members for all
  using (public.can_manage_workspace(workspace_id))
  with check (public.can_manage_workspace(workspace_id));

create policy products_member_read on public.products for select
  using (public.is_workspace_member(workspace_id));
create policy products_manager_write on public.products for all
  using (public.can_manage_workspace(workspace_id))
  with check (public.can_manage_workspace(workspace_id));
create policy orders_member_read on public.orders for select
  using (public.is_workspace_member(workspace_id));
create policy orders_manager_write on public.orders for all
  using (public.can_manage_workspace(workspace_id))
  with check (public.can_manage_workspace(workspace_id));
create policy order_items_member_read on public.order_items for select
  using (public.is_workspace_member(workspace_id));
create policy order_items_manager_write on public.order_items for all
  using (public.can_manage_workspace(workspace_id))
  with check (public.can_manage_workspace(workspace_id));
create policy movements_member_read on public.stock_movements for select
  using (public.is_workspace_member(workspace_id));
create policy movements_manager_write on public.stock_movements for insert
  with check (public.can_manage_workspace(workspace_id) and actor_id = auth.uid());

-- Invoke only after the caller has created the order and its line items.
-- Product rows are locked in stable ID order to prevent overselling and reduce deadlocks.
create or replace function public.fulfill_order(target_order uuid)
returns void language plpgsql security invoker set search_path = public, auth as $$
declare
  order_row public.orders%rowtype;
  item record;
  changed_product uuid;
begin
  select * into order_row from public.orders where id = target_order for update;
  if not found then raise exception 'Order not found'; end if;
  if not public.can_manage_workspace(order_row.workspace_id) then raise exception 'Not authorized'; end if;
  if order_row.status not in ('pending','processing') then raise exception 'Order is not fulfillable'; end if;

  for item in
    select oi.product_id, oi.quantity
    from public.order_items oi
    where oi.order_id = target_order
    order by oi.product_id
  loop
    update public.products
      set quantity_on_hand = quantity_on_hand - item.quantity, updated_at = now()
      where id = item.product_id and workspace_id = order_row.workspace_id
        and active and quantity_on_hand >= item.quantity
      returning id into changed_product;
    if changed_product is null then raise exception 'Insufficient stock for product %', item.product_id; end if;
    insert into public.stock_movements(workspace_id, product_id, order_id, actor_id, quantity_delta, reason)
      values (order_row.workspace_id, item.product_id, target_order, auth.uid(), -item.quantity, 'fulfillment');
    changed_product := null;
  end loop;

  update public.orders set status = 'fulfilled', fulfilled_at = now() where id = target_order;
end;
$$;

