-- ============================================================================
-- BENA / بِناء — Reviews & Ratings
-- Run AFTER supabase_schema.sql and supabase_admin.sql
-- ============================================================================
-- What this does:
--   1. Auto-recalculates products.rating + products.review_count
--      whenever a review is inserted/updated/deleted
--   2. Adds a helper RPC for the site to insert a review safely
--   3. Allows logged-in users to read their own pending reviews
-- ============================================================================


-- =====================================================
-- 1. AUTO-AGGREGATE PRODUCT RATING
-- =====================================================
create or replace function recalculate_product_rating()
returns trigger as $$
declare
  v_product_id text;
  v_avg numeric(2,1);
  v_count int;
begin
  -- Pick the product id from the appropriate row (insert/update/delete)
  if tg_op = 'DELETE' then
    v_product_id := old.product_id;
  else
    v_product_id := new.product_id;
  end if;

  -- Aggregate visible (non-hidden) reviews
  select
    coalesce(round(avg(rating)::numeric, 1), 0),
    count(*)
  into v_avg, v_count
  from reviews
  where product_id = v_product_id and is_hidden = false;

  update products
    set rating = v_avg,
        review_count = v_count
    where id = v_product_id;

  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$ language plpgsql security definer;

drop trigger if exists trg_reviews_recalc_rating on reviews;
create trigger trg_reviews_recalc_rating
  after insert or update or delete on reviews
  for each row execute function recalculate_product_rating();


-- =====================================================
-- 2. INCREMENT REVIEW HELPFUL COUNT (RPC, safe)
-- =====================================================
create or replace function mark_review_helpful(review_id bigint)
returns int as $$
declare
  v_new_count int;
begin
  update reviews
    set helpful_count = helpful_count + 1
    where id = review_id and is_hidden = false
    returning helpful_count into v_new_count;
  return v_new_count;
end;
$$ language plpgsql security definer;

grant execute on function mark_review_helpful(bigint) to authenticated;


-- =====================================================
-- 3. POLICY: allow users to read their own reviews (even hidden ones)
-- =====================================================
drop policy if exists "review owner read own" on reviews;
create policy "review owner read own" on reviews
  for select using (auth.uid() = user_id);

-- Allow customer to DELETE their own review
drop policy if exists "reviews owner delete" on reviews;
create policy "reviews owner delete" on reviews
  for delete using (auth.uid() = user_id);


-- =====================================================
-- 4. RELAX REVIEW INSERT TEMPORARILY (optional — for testing)
--    For production with real orders, keep the strict 'verified buyer' rule.
--    During development, uncomment below so any logged-in user can post a review.
-- =====================================================
/*
drop policy if exists "reviews insert verified" on reviews;
create policy "reviews insert any logged user" on reviews
  for insert with check (auth.uid() = user_id);
*/


-- =====================================================
-- 5. VIEW: product reviews with user name (joined)
--    Easier to query from the frontend
-- =====================================================
drop view if exists product_reviews_view;
create view product_reviews_view
with (security_invoker = true)
as
select
  r.id,
  r.product_id,
  r.user_id,
  r.rating,
  r.comment,
  r.helpful_count,
  r.is_verified,
  r.created_at,
  coalesce(p.full_name, split_part(p.email, '@', 1)) as reviewer_name,
  p.avatar_url as reviewer_avatar
from reviews r
join profiles p on p.id = r.user_id
where r.is_hidden = false
order by r.created_at desc;

grant select on product_reviews_view to anon, authenticated;
