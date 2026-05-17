-- ============================================================================
-- BENA / بِناء — Admin (Owner) Role Layer
-- Run this AFTER supabase_schema.sql has been applied.
-- ============================================================================
-- What this adds:
--   1. is_admin() function — fast check whether the current user is the owner
--   2. RLS policies giving admin full CRUD on products, suppliers, categories
--   3. Admin can read ALL orders, profiles, etc. (for the dashboard)
--   4. sales_stats view — aggregate revenue numbers for the dashboard
--   5. monthly_sales view — month-by-month breakdown for charts
-- ============================================================================


-- =====================================================
-- 1. ADMIN CHECK FUNCTION
-- SECURITY DEFINER so the policies can call it without triggering RLS recursion
-- =====================================================
create or replace function public.is_admin()
returns boolean
language sql
security definer
stable
as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid()
      and user_type = 'admin'
  );
$$;

grant execute on function public.is_admin() to authenticated, anon;


-- =====================================================
-- 2. ADMIN POLICIES — owner can do everything on catalog
-- =====================================================

-- Products: admin can insert, update, delete
drop policy if exists "admin manage products" on products;
create policy "admin manage products" on products
  for all
  using (is_admin())
  with check (is_admin());

drop policy if exists "admin manage product_images" on product_images;
create policy "admin manage product_images" on product_images
  for all using (is_admin()) with check (is_admin());

drop policy if exists "admin manage product_specs" on product_specs;
create policy "admin manage product_specs" on product_specs
  for all using (is_admin()) with check (is_admin());

drop policy if exists "admin manage product_tiers" on product_tiers;
create policy "admin manage product_tiers" on product_tiers
  for all using (is_admin()) with check (is_admin());

-- Suppliers
drop policy if exists "admin manage suppliers" on suppliers;
create policy "admin manage suppliers" on suppliers
  for all using (is_admin()) with check (is_admin());

-- Categories
drop policy if exists "admin manage categories" on categories;
create policy "admin manage categories" on categories
  for all using (is_admin()) with check (is_admin());

-- Cities
drop policy if exists "admin manage cities" on cities;
create policy "admin manage cities" on cities
  for all using (is_admin()) with check (is_admin());

-- Orders: admin can read all orders, update status, etc.
drop policy if exists "admin read all orders" on orders;
create policy "admin read all orders" on orders
  for select using (is_admin());
drop policy if exists "admin update orders" on orders;
create policy "admin update orders" on orders
  for update using (is_admin()) with check (is_admin());

drop policy if exists "admin read all order_items" on order_items;
create policy "admin read all order_items" on order_items
  for select using (is_admin());

-- Profiles: admin can see all customers
drop policy if exists "admin read all profiles" on profiles;
create policy "admin read all profiles" on profiles
  for select using (is_admin());

-- Reviews: admin can moderate (hide/unhide)
drop policy if exists "admin moderate reviews" on reviews;
create policy "admin moderate reviews" on reviews
  for update using (is_admin()) with check (is_admin());
drop policy if exists "admin delete reviews" on reviews;
create policy "admin delete reviews" on reviews
  for delete using (is_admin());

-- RFQs: admin can see all
drop policy if exists "admin read all rfqs" on rfqs;
create policy "admin read all rfqs" on rfqs
  for select using (is_admin());


-- =====================================================
-- 3. SALES STATS — aggregate revenue view
-- =====================================================
drop view if exists sales_stats;
create view sales_stats
with (security_invoker = true)
as
select
  count(*)::int                                                       as total_orders,
  count(distinct user_id)::int                                        as total_customers,
  coalesce(sum(total), 0)::numeric(12,2)                              as total_revenue,
  coalesce(sum(case when created_at >= date_trunc('day', now())
                    then total else 0 end), 0)::numeric(12,2)         as revenue_today,
  coalesce(sum(case when created_at >= date_trunc('week', now())
                    then total else 0 end), 0)::numeric(12,2)         as revenue_this_week,
  coalesce(sum(case when created_at >= date_trunc('month', now())
                    then total else 0 end), 0)::numeric(12,2)         as revenue_this_month,
  coalesce(sum(case when created_at >= date_trunc('year', now())
                    then total else 0 end), 0)::numeric(12,2)         as revenue_this_year,
  coalesce(sum(case when status = 'pending' then total else 0 end), 0)::numeric(12,2)
                                                                       as pending_revenue,
  count(*) filter (where status = 'pending')::int                     as pending_orders,
  count(*) filter (where status = 'delivered')::int                   as delivered_orders,
  count(*) filter (where created_at >= date_trunc('month', now()))::int
                                                                       as orders_this_month
from orders
where payment_status in ('paid', 'partial') or status in ('confirmed', 'preparing', 'shipped', 'delivered');

grant select on sales_stats to authenticated;


-- =====================================================
-- 4. MONTHLY SALES — last 12 months for chart
-- =====================================================
drop view if exists monthly_sales;
create view monthly_sales
with (security_invoker = true)
as
select
  to_char(date_trunc('month', created_at), 'YYYY-MM')           as month,
  to_char(date_trunc('month', created_at), 'Mon YYYY')          as month_label,
  count(*)::int                                                  as order_count,
  coalesce(sum(total), 0)::numeric(12,2)                        as revenue
from orders
where created_at >= now() - interval '12 months'
  and (payment_status in ('paid', 'partial') or status in ('confirmed', 'preparing', 'shipped', 'delivered'))
group by date_trunc('month', created_at)
order by date_trunc('month', created_at) desc;

grant select on monthly_sales to authenticated;


-- =====================================================
-- 5. TOP PRODUCTS — best sellers
-- =====================================================
drop view if exists top_products;
create view top_products
with (security_invoker = true)
as
select
  oi.product_id,
  oi.product_name_snapshot                  as product_name,
  count(*)::int                              as times_ordered,
  sum(oi.quantity)::int                      as units_sold,
  sum(oi.subtotal)::numeric(12,2)            as revenue
from order_items oi
join orders o on o.id = oi.order_id
where o.created_at >= now() - interval '90 days'
  and (o.payment_status in ('paid', 'partial') or o.status in ('confirmed', 'preparing', 'shipped', 'delivered'))
group by oi.product_id, oi.product_name_snapshot
order by revenue desc
limit 20;

grant select on top_products to authenticated;


-- =====================================================
-- 6. HOW TO MAKE A USER ADMIN
--    After they sign up via the site, run this with their email:
-- =====================================================
-- update profiles set user_type = 'admin' where email = 'OWNER@example.com';

-- Or auto-promote a specific email on signup:
-- (uncomment and put your owner email in to make signups from that email
--  automatically become admins)
/*
create or replace function trg_auto_admin()
returns trigger as $$
begin
  if new.email = lower('YOUR_OWNER_EMAIL@example.com') then
    new.user_type = 'admin';
  end if;
  return new;
end;
$$ language plpgsql;

drop trigger if exists profile_auto_admin on profiles;
create trigger profile_auto_admin
  before insert on profiles
  for each row execute function trg_auto_admin();
*/
