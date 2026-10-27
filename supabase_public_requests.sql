-- مداد — public "latest customer requests" feed
-- Applied to project bena on 2026-10-27 (migrations public_requests_feed, public_requests_close_past_due).
-- ----------------------------------------------------------------------------
-- Quote requests live in public.orders, with the request packed into
-- customer_notes as "key: value" lines (see apiSubmitRFQ in index.html):
--   الفئة / المعدات المطلوبة / الكمية / الاسم / الجوال / البريد / المدينة /
--   الجهة / المطلوب بحلول / التفاصيل
--
-- Guests cannot SELECT orders, so this SECURITY DEFINER function is the only
-- public read path. It returns ONLY: category, selected items, quantity, city,
-- needed-by date, open/closed, date. Never name, phone, email, company or the
-- free-text details. A request reads "open" only while the order is active
-- and its needed-by date hasn't passed.
--
-- Rows whose notes contain a line "اختبار: نعم" are test data: hidden unless
-- p_include_test = true (the site passes that only in ?preview=1 mode).
-- The four pre-launch test orders from docs/CLEANUP_TEST_ORDERS.sql are
-- excluded outright.
-- ----------------------------------------------------------------------------

create or replace function public.public_requests(
  p_limit        int     default 8,
  p_offset       int     default 0,
  p_category     text    default null,
  p_cities       text[]  default null,
  p_status       text    default null,   -- 'open' | 'closed'
  p_search       text    default null,
  p_oldest_first boolean default false,
  p_include_test boolean default false
)
returns table (
  ref         text,
  category    text,
  items       text,
  qty         text,
  city        text,
  needed_by   date,
  status      text,
  created_at  timestamptz,
  total_count bigint
)
language sql
stable
security definer
set search_path = ''
as $$
  with parsed as (
    select
      ltrim(right(regexp_replace(o.order_number, '\D', '', 'g'), 5), '0')            as ref,
      nullif(trim(substring(o.customer_notes from '(?n)^الفئة: (.*)$')), '')            as category,
      left(nullif(trim(substring(o.customer_notes from '(?n)^المعدات المطلوبة: (.*)$')), ''), 120) as items,
      left(nullif(trim(substring(o.customer_notes from '(?n)^الكمية: (.*)$')), ''), 40) as qty,
      nullif(trim(substring(o.customer_notes from '(?n)^المدينة: (.*)$')), '')          as city,
      substring(o.customer_notes from '(?n)^المطلوب بحلول: ([0-9]{4}-[0-9]{2}-[0-9]{2})')::date as needed_by,
      o.status::text as order_status,
      o.created_at,
      (o.customer_notes ~ '(?n)^اختبار: ')                                              as is_test
    from public.orders o
    where o.customer_notes is not null
      and o.status::text not in ('cancelled', 'refunded')
      and o.order_number not in ('BENA-2026-00005', 'BENA-2026-00006', 'BENA-2026-00007', 'BENA-2026-00008')
  ), shaped as (
    select *,
      -- Open only while the order is active AND its needed-by date hasn't passed.
      case when order_status in ('pending', 'confirmed', 'preparing')
                and (needed_by is null or needed_by >= current_date)
           then 'open' else 'closed' end as status
    from parsed
  )
  select
    ref, category, items, qty, city, needed_by, status, created_at,
    count(*) over () as total_count
  from shaped
  where category is not null
    and (p_include_test or not is_test)
    and (p_category is null or category = p_category)
    and (p_cities   is null or city = any (p_cities))
    and (p_status   is null or status = p_status)
    and (p_search   is null or concat_ws(' ', category, items, qty, city) ilike '%' || p_search || '%')
  order by
    case when p_oldest_first then created_at end asc,
    created_at desc
  limit least(greatest(p_limit, 1), 50)
  offset greatest(p_offset, 0);
$$;

revoke all on function public.public_requests(int, int, text, text[], text, text, boolean, boolean) from public;
grant execute on function public.public_requests(int, int, text, text[], text, text, boolean, boolean) to anon, authenticated;
