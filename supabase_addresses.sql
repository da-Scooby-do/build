-- ============================================================================
-- BENA / بِناء — Address columns for map coordinates
-- Run AFTER supabase_schema.sql in Supabase SQL Editor
-- ============================================================================
-- Adds latitude, longitude, and a friendly_label to the existing addresses table
-- so customers can pin their delivery location on a map.

alter table addresses
  add column if not exists latitude   numeric(10, 7),
  add column if not exists longitude  numeric(10, 7),
  add column if not exists location_label text;   -- e.g. "موقع المشروع — حي النخيل"

-- Index for any future geolocation queries (e.g. "addresses near point")
create index if not exists idx_addresses_lat_lng
  on addresses (latitude, longitude)
  where latitude is not null;

-- Helper: set this address as the user's default (and unset others)
create or replace function set_default_address(p_address_id bigint)
returns void
language plpgsql
security invoker
as $$
begin
  -- Clear current default for this user
  update addresses
    set is_default = false
    where user_id = auth.uid() and is_default = true;
  -- Set new default (only if it belongs to this user)
  update addresses
    set is_default = true
    where id = p_address_id and user_id = auth.uid();
end;
$$;

grant execute on function set_default_address(bigint) to authenticated;
