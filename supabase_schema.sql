-- ============================================================================
-- BENA / بِناء — Saudi Build Materials Marketplace
-- Supabase / PostgreSQL Schema
-- ============================================================================
-- Run this entire file in your Supabase SQL Editor (one shot).
-- Sections:
--   1. Extensions
--   2. Enums
--   3. Reference tables (cities, categories)
--   4. Users / profiles / suppliers
--   5. Products + images + specs + tier pricing
--   6. Addresses (Saudi National Address format)
--   7. Cart + wishlist
--   8. Orders + order items
--   9. Reviews
--  10. RFQ (Request for Quote)
--  11. ZATCA e-invoicing
--  12. Indexes
--  13. Triggers (updated_at, order numbering)
--  14. Row Level Security (RLS) policies
--  15. Storage bucket policy hints
--  16. Seed data
-- ============================================================================


-- =====================================================
-- 0. CLEANUP — drops any existing version from previous runs.
--    Safe to re-run this whole file as many times as you want.
-- =====================================================
drop trigger if exists on_auth_user_created on auth.users;

drop table if exists zatca_invoices  cascade;
drop table if exists rfq_responses   cascade;
drop table if exists rfq_items       cascade;
drop table if exists rfqs            cascade;
drop table if exists reviews         cascade;
drop table if exists order_items     cascade;
drop table if exists orders          cascade;
drop table if exists wishlist        cascade;
drop table if exists cart_items      cascade;
drop table if exists addresses       cascade;
drop table if exists product_tiers   cascade;
drop table if exists product_specs   cascade;
drop table if exists product_images  cascade;
drop table if exists products        cascade;
drop table if exists suppliers       cascade;
drop table if exists profiles        cascade;
drop table if exists categories      cascade;
drop table if exists cities          cascade;

drop type if exists user_type            cascade;
drop type if exists order_status         cascade;
drop type if exists payment_status       cascade;
drop type if exists payment_method_type  cascade;
drop type if exists rfq_status           cascade;
drop type if exists response_status      cascade;
drop type if exists language_pref        cascade;

drop function if exists trg_set_updated_at()      cascade;
drop function if exists trg_create_profile()      cascade;
drop function if exists generate_order_number()   cascade;
drop function if exists generate_rfq_number()     cascade;

drop sequence if exists order_number_seq cascade;
drop sequence if exists rfq_number_seq   cascade;


-- =====================================================
-- 1. EXTENSIONS
-- =====================================================
create extension if not exists "uuid-ossp";
create extension if not exists "pgcrypto";


-- =====================================================
-- 2. ENUMS
-- =====================================================
create type user_type as enum ('customer', 'contractor', 'business', 'supplier', 'admin');
create type order_status as enum ('pending', 'confirmed', 'preparing', 'shipped', 'delivered', 'cancelled', 'refunded');
create type payment_status as enum ('pending', 'paid', 'failed', 'refunded', 'partial');
create type payment_method_type as enum ('mada', 'visa', 'mastercard', 'apple_pay', 'stc_pay', 'tabby', 'tamara', 'bank_transfer', 'cod');
create type rfq_status as enum ('open', 'closed', 'awarded', 'expired', 'cancelled');
create type response_status as enum ('pending', 'accepted', 'rejected', 'withdrawn');
create type language_pref as enum ('ar', 'en');


-- =====================================================
-- 3. REFERENCE TABLES
-- =====================================================

-- Saudi cities
create table cities (
  code        text primary key,
  name_ar     text not null,
  name_en     text not null,
  region      text,
  is_active   boolean default true
);

-- Product categories (supports subcategories via parent_id)
create table categories (
  id          text primary key,
  name_ar     text not null,
  name_en     text,
  parent_id   text references categories(id) on delete set null,
  icon        text,
  sort_order  int default 0,
  is_active   boolean default true
);


-- =====================================================
-- 4. PROFILES & SUPPLIERS
-- =====================================================

-- Profiles extend auth.users (created automatically by Supabase Auth)
-- Email is REQUIRED for every customer account.
create table profiles (
  id                 uuid primary key references auth.users(id) on delete cascade,
  full_name          text,
  phone              text,
  email              text not null,
  user_type          user_type default 'customer',
  preferred_language language_pref default 'ar',
  avatar_url         text,
  created_at         timestamptz default now(),
  updated_at         timestamptz default now(),
  constraint profiles_email_format check (email ~* '^[^@\s]+@[^@\s]+\.[^@\s]+$'),
  constraint profiles_email_unique unique (email)
);

-- Suppliers (vendors / merchants)
create table suppliers (
  id              text primary key,             -- 's1', 's2', etc. or use uuid
  user_id         uuid references profiles(id) on delete set null,
  name_ar         text not null,
  name_en         text,
  description_ar  text,
  description_en  text,
  cr_number       text,                          -- Saudi Commercial Registration
  vat_number      text,                          -- 15-digit ZATCA VAT number
  phone           text,
  email           text,
  established_year int,
  rating          numeric(2,1) default 0,
  review_count    int default 0,
  cities_served   text[] default '{}',           -- array of city codes
  cover_image     text,
  logo            text,
  is_verified     boolean default false,
  is_active       boolean default true,
  created_at      timestamptz default now(),
  updated_at      timestamptz default now()
);


-- =====================================================
-- 5. PRODUCTS
-- =====================================================

create table products (
  id                   text primary key,         -- 'p1', 'p2', etc.
  supplier_id          text not null references suppliers(id) on delete cascade,
  category_id          text references categories(id),
  city_code            text references cities(code),
  name_ar              text not null,
  name_en              text,
  description_ar       text,
  description_en       text,
  price                numeric(10,2) not null check (price >= 0),
  unit_ar              text,                     -- e.g. 'م³', 'طن', 'باب'
  unit_en              text,
  rating               numeric(2,1) default 0,
  review_count         int default 0,
  tag_ar               text,                     -- 'فوري', 'معتمد SASO'
  tag_en               text,
  main_image           text,
  in_stock             boolean default true,
  stock_quantity       int,
  min_order_quantity   int default 1,
  is_active            boolean default true,
  created_at           timestamptz default now(),
  updated_at           timestamptz default now()
);

-- Multiple images per product
create table product_images (
  id          bigserial primary key,
  product_id  text not null references products(id) on delete cascade,
  url         text not null,
  sort_order  int default 0
);

-- Flexible key/value specs (e.g. "Strength: 35 MPa")
create table product_specs (
  id          bigserial primary key,
  product_id  text not null references products(id) on delete cascade,
  spec_key    text not null,
  spec_value  text not null,
  sort_order  int default 0
);

-- Volume-based tier pricing (e.g. "1-9 طن → 3750 SAR, 10+ → 3450 SAR")
create table product_tiers (
  id              bigserial primary key,
  product_id      text not null references products(id) on delete cascade,
  quantity_label  text,                    -- '1-9 طن'
  min_quantity    int not null,
  max_quantity    int,                     -- null = unlimited
  price           numeric(10,2) not null,
  sort_order      int default 0
);


-- =====================================================
-- 6. ADDRESSES (Saudi National Address format)
-- =====================================================

create table addresses (
  id                  bigserial primary key,
  user_id             uuid not null references profiles(id) on delete cascade,
  label               text,                     -- 'منزل', 'عمل', 'موقع البناء'
  recipient_name      text not null,
  phone               text not null,
  building_number     text,                     -- 4-digit primary
  street_name         text,
  district            text,
  city_code           text references cities(code),
  postal_code         text,                     -- 5 digits
  additional_number   text,                     -- 4-digit secondary (Wassel)
  notes               text,
  is_default          boolean default false,
  created_at          timestamptz default now()
);


-- =====================================================
-- 7. CART & WISHLIST
-- =====================================================

create table cart_items (
  id          bigserial primary key,
  user_id     uuid not null references profiles(id) on delete cascade,
  product_id  text not null references products(id) on delete cascade,
  quantity    int not null check (quantity > 0),
  added_at    timestamptz default now(),
  unique (user_id, product_id)
);

create table wishlist (
  id          bigserial primary key,
  user_id     uuid not null references profiles(id) on delete cascade,
  product_id  text not null references products(id) on delete cascade,
  added_at    timestamptz default now(),
  unique (user_id, product_id)
);


-- =====================================================
-- 8. ORDERS
-- =====================================================

create table orders (
  id                   uuid primary key default gen_random_uuid(),
  order_number         text unique not null,        -- 'BENA-2026-00001'
  user_id              uuid not null references profiles(id),
  status               order_status default 'pending',
  subtotal             numeric(10,2) not null,
  vat_rate             numeric(4,2) default 15.00,  -- 15% in KSA
  vat_amount           numeric(10,2) not null,
  delivery_fee         numeric(10,2) default 0,
  discount             numeric(10,2) default 0,
  total                numeric(10,2) not null,
  payment_method       payment_method_type,
  payment_status       payment_status default 'pending',
  payment_reference    text,                        -- gateway transaction id
  delivery_address_id  bigint references addresses(id),
  delivery_date        date,
  delivery_time_slot   text,                        -- 'morning', '8am-12pm', etc.
  customer_notes       text,
  internal_notes       text,
  created_at           timestamptz default now(),
  updated_at           timestamptz default now()
);

create table order_items (
  id                     bigserial primary key,
  order_id               uuid not null references orders(id) on delete cascade,
  product_id             text references products(id),
  supplier_id            text references suppliers(id),
  product_name_snapshot  text not null,            -- snapshot for record-keeping
  unit_snapshot          text,
  quantity               int not null check (quantity > 0),
  unit_price             numeric(10,2) not null,
  subtotal               numeric(10,2) not null
);


-- =====================================================
-- 9. REVIEWS
-- =====================================================

create table reviews (
  id              bigserial primary key,
  product_id      text not null references products(id) on delete cascade,
  user_id         uuid not null references profiles(id) on delete cascade,
  order_id        uuid references orders(id),         -- enforces verified buyer
  rating          int not null check (rating between 1 and 5),
  comment         text,
  helpful_count   int default 0,
  is_verified     boolean default false,
  is_hidden       boolean default false,
  created_at      timestamptz default now(),
  unique (product_id, user_id, order_id)
);


-- =====================================================
-- 10. RFQ — Request for Quote
-- =====================================================

create table rfqs (
  id              uuid primary key default gen_random_uuid(),
  rfq_number      text unique not null,             -- 'RFQ-2026-00001'
  user_id         uuid not null references profiles(id),
  project_name    text,
  description     text,
  city_code       text references cities(code),
  delivery_date   date,
  status          rfq_status default 'open',
  total_estimate  numeric(12,2),
  closes_at       timestamptz,
  created_at      timestamptz default now()
);

create table rfq_items (
  id                    bigserial primary key,
  rfq_id                uuid not null references rfqs(id) on delete cascade,
  product_description   text not null,
  category_id           text references categories(id),
  quantity              int not null,
  unit                  text,
  notes                 text
);

create table rfq_responses (
  id              bigserial primary key,
  rfq_id          uuid not null references rfqs(id) on delete cascade,
  supplier_id     text not null references suppliers(id) on delete cascade,
  total_price     numeric(12,2) not null,
  delivery_time   text,
  notes           text,
  status          response_status default 'pending',
  created_at      timestamptz default now(),
  unique (rfq_id, supplier_id)
);


-- =====================================================
-- 11. ZATCA E-INVOICES (Saudi tax compliance)
-- =====================================================

create table zatca_invoices (
  id              bigserial primary key,
  order_id        uuid not null references orders(id) on delete cascade,
  invoice_number  text unique not null,
  invoice_uuid    uuid default gen_random_uuid(),
  invoice_date    timestamptz default now(),
  seller_name     text,
  seller_vat      text,
  buyer_name      text,
  buyer_vat       text,
  subtotal        numeric(10,2),
  vat_amount      numeric(10,2),
  total           numeric(10,2),
  qr_code_base64  text,                  -- TLV-encoded QR per ZATCA spec
  xml_hash        text,
  previous_hash   text,
  is_submitted    boolean default false,
  submitted_at    timestamptz
);


-- =====================================================
-- 12. INDEXES (for query performance)
-- =====================================================
create index idx_products_supplier on products(supplier_id);
create index idx_products_category on products(category_id);
create index idx_products_city on products(city_code);
create index idx_products_active on products(is_active) where is_active = true;
create index idx_product_images_product on product_images(product_id);
create index idx_product_specs_product on product_specs(product_id);
create index idx_product_tiers_product on product_tiers(product_id);
create index idx_orders_user on orders(user_id);
create index idx_orders_status on orders(status);
create index idx_order_items_order on order_items(order_id);
create index idx_order_items_supplier on order_items(supplier_id);
create index idx_reviews_product on reviews(product_id);
create index idx_addresses_user on addresses(user_id);
create index idx_cart_user on cart_items(user_id);
create index idx_wishlist_user on wishlist(user_id);
create index idx_rfqs_user on rfqs(user_id);
create index idx_rfq_responses_rfq on rfq_responses(rfq_id);


-- =====================================================
-- 13. TRIGGERS
-- =====================================================

-- Auto-update updated_at
create or replace function trg_set_updated_at()
returns trigger as $$
begin
  new.updated_at = now();
  return new;
end;
$$ language plpgsql;

create trigger profiles_set_updated_at before update on profiles
  for each row execute function trg_set_updated_at();
create trigger suppliers_set_updated_at before update on suppliers
  for each row execute function trg_set_updated_at();
create trigger products_set_updated_at before update on products
  for each row execute function trg_set_updated_at();
create trigger orders_set_updated_at before update on orders
  for each row execute function trg_set_updated_at();

-- Auto-create profile when a new user signs up via Supabase Auth.
-- Pulls full_name and phone from the raw_user_meta_data sent by the signup form.
create or replace function trg_create_profile()
returns trigger as $$
begin
  insert into public.profiles (id, email, phone, full_name)
  values (
    new.id,
    new.email,
    coalesce(new.phone, new.raw_user_meta_data->>'phone'),
    new.raw_user_meta_data->>'full_name'
  );
  return new;
end;
$$ language plpgsql security definer;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function trg_create_profile();

-- Sequential order number generator (BENA-YYYY-NNNNN)
create sequence if not exists order_number_seq start 1;

create or replace function generate_order_number()
returns text as $$
begin
  return 'BENA-' || to_char(now(), 'YYYY') || '-' || lpad(nextval('order_number_seq')::text, 5, '0');
end;
$$ language plpgsql;

create sequence if not exists rfq_number_seq start 1;

create or replace function generate_rfq_number()
returns text as $$
begin
  return 'RFQ-' || to_char(now(), 'YYYY') || '-' || lpad(nextval('rfq_number_seq')::text, 5, '0');
end;
$$ language plpgsql;


-- =====================================================
-- 14. ROW LEVEL SECURITY (RLS)
-- Critical for Supabase: anyone with the anon key can hit your DB,
-- so RLS must be enabled on every table that holds user data.
-- =====================================================

alter table profiles        enable row level security;
alter table suppliers       enable row level security;
alter table products        enable row level security;
alter table product_images  enable row level security;
alter table product_specs   enable row level security;
alter table product_tiers   enable row level security;
alter table categories      enable row level security;
alter table cities          enable row level security;
alter table addresses       enable row level security;
alter table cart_items      enable row level security;
alter table wishlist        enable row level security;
alter table orders          enable row level security;
alter table order_items     enable row level security;
alter table reviews         enable row level security;
alter table rfqs            enable row level security;
alter table rfq_items       enable row level security;
alter table rfq_responses   enable row level security;
alter table zatca_invoices  enable row level security;

-- PUBLIC READ tables (catalog data anyone should be able to browse)
create policy "public read cities"     on cities     for select using (true);
create policy "public read categories" on categories for select using (true);
create policy "public read suppliers"  on suppliers  for select using (is_active = true);
create policy "public read products"   on products   for select using (is_active = true);
create policy "public read product_images" on product_images for select using (true);
create policy "public read product_specs"  on product_specs  for select using (true);
create policy "public read product_tiers"  on product_tiers  for select using (true);
create policy "public read reviews"        on reviews        for select using (is_hidden = false);

-- PROFILES: users can read & update their own profile
create policy "profile self read"   on profiles for select using (auth.uid() = id);
create policy "profile self update" on profiles for update using (auth.uid() = id);

-- ADDRESSES: only owner
create policy "addresses owner all" on addresses
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- CART: only owner
create policy "cart owner all" on cart_items
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- WISHLIST: only owner
create policy "wishlist owner all" on wishlist
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- ORDERS: customer reads own orders, suppliers read orders for their items (handled via order_items)
create policy "orders owner read"   on orders for select using (auth.uid() = user_id);
create policy "orders owner insert" on orders for insert with check (auth.uid() = user_id);

-- ORDER ITEMS: visible to order owner OR the supplier
create policy "order_items owner read" on order_items for select using (
  exists (select 1 from orders o where o.id = order_items.order_id and o.user_id = auth.uid())
  or exists (
    select 1 from suppliers s where s.id = order_items.supplier_id and s.user_id = auth.uid()
  )
);
create policy "order_items insert via order" on order_items for insert with check (
  exists (select 1 from orders o where o.id = order_items.order_id and o.user_id = auth.uid())
);

-- REVIEWS: anyone can read non-hidden, only verified buyers can write
create policy "reviews insert verified" on reviews for insert with check (
  auth.uid() = user_id
  and exists (
    select 1 from orders o
    join order_items oi on oi.order_id = o.id
    where o.user_id = auth.uid()
      and oi.product_id = reviews.product_id
      and o.status = 'delivered'
  )
);
create policy "reviews owner update" on reviews for update using (auth.uid() = user_id);

-- RFQs: owner sees own, suppliers see open ones in their served cities
create policy "rfqs owner read"   on rfqs for select using (auth.uid() = user_id);
create policy "rfqs supplier read" on rfqs for select using (
  exists (
    select 1 from suppliers s
    where s.user_id = auth.uid()
      and (rfqs.city_code is null or rfqs.city_code = any(s.cities_served))
      and rfqs.status = 'open'
  )
);
create policy "rfqs owner insert" on rfqs for insert with check (auth.uid() = user_id);

create policy "rfq_items rfq owner read" on rfq_items for select using (
  exists (select 1 from rfqs r where r.id = rfq_items.rfq_id and r.user_id = auth.uid())
);
create policy "rfq_items insert" on rfq_items for insert with check (
  exists (select 1 from rfqs r where r.id = rfq_items.rfq_id and r.user_id = auth.uid())
);

create policy "rfq_responses read"  on rfq_responses for select using (
  exists (select 1 from rfqs r where r.id = rfq_responses.rfq_id and r.user_id = auth.uid())
  or exists (select 1 from suppliers s where s.id = rfq_responses.supplier_id and s.user_id = auth.uid())
);
create policy "rfq_responses supplier insert" on rfq_responses for insert with check (
  exists (select 1 from suppliers s where s.id = rfq_responses.supplier_id and s.user_id = auth.uid())
);

-- ZATCA invoices: visible to order owner
create policy "zatca order owner read" on zatca_invoices for select using (
  exists (select 1 from orders o where o.id = zatca_invoices.order_id and o.user_id = auth.uid())
);


-- =====================================================
-- 15. STORAGE — create these buckets in the Supabase dashboard:
--      • product-images   (public read)
--      • supplier-logos   (public read)
--      • user-avatars     (public read, authenticated write to own folder)
--      • invoices         (private)
-- See setup_guide.md for the storage policies SQL.
-- =====================================================


-- =====================================================
-- 16. SEED DATA — matches the placeholder data in index.html
-- =====================================================

-- Cities
insert into cities (code, name_ar, name_en, region) values
  ('RUH', 'الرياض',           'Riyadh',          'Central'),
  ('JED', 'جدة',              'Jeddah',          'Western'),
  ('DAM', 'الدمام',           'Dammam',          'Eastern'),
  ('MED', 'المدينة المنورة',  'Medina',          'Western'),
  ('MEC', 'مكة المكرمة',      'Mecca',           'Western'),
  ('TAB', 'تبوك',             'Tabuk',           'Northern'),
  ('ABH', 'أبها',             'Abha',            'Southern'),
  ('TAI', 'الطائف',           'Taif',            'Western'),
  ('BUR', 'بريدة',            'Buraydah',        'Qassim'),
  ('HAI', 'حائل',             'Hail',            'Northern');

-- Categories
insert into categories (id, name_ar, name_en, sort_order) values
  ('cat-concrete', 'خرسانة',  'Concrete',        1),
  ('cat-blocks',   'طوب',     'Blocks',          2),
  ('cat-rebar',    'حديد',    'Rebar / Steel',   3),
  ('cat-equipment','معدات',   'Equipment',       4),
  ('cat-wood',     'أخشاب',   'Wood',            5),
  ('cat-doors',    'أبواب',   'Doors',           6),
  ('cat-cement',   'أسمنت',   'Cement',          7),
  ('cat-tiles',    'بلاط',    'Tiles',           8),
  ('cat-paint',    'دهانات',  'Paints',          9),
  ('cat-plumbing', 'سباكة',   'Plumbing',       10),
  ('cat-electric', 'كهرباء',  'Electrical',     11);

-- Suppliers (10 suppliers matching site)
insert into suppliers (id, name_ar, cr_number, vat_number, phone, established_year, rating, review_count, cities_served, is_verified) values
  ('s1',  'مصنع الخرسانة الجاهزة',    '1010001111', '300000000000003', '+966500000001', 1985, 4.9, 1245, '{RUH,JED}',             true),
  ('s2',  'مؤسسة الطوب الأحمر',       '1010002222', '300000000000004', '+966500000002', 1992, 4.8,  876, '{MED,MEC}',              true),
  ('s3',  'شركة الحديد السعودي',      '1010003333', '300000000000005', '+966500000003', 1978, 4.9, 2103, '{DAM,RUH,JED}',          true),
  ('s4',  'تأجير المعدات الكبرى',     '1010004444', '300000000000006', '+966500000004', 2001, 4.7,  432, '{RUH,DAM}',              true),
  ('s5',  'معرض الأخشاب الفاخرة',     '1010005555', '300000000000007', '+966500000005', 1995, 4.6,  321, '{JED,MEC}',              true),
  ('s6',  'مصنع الأبواب الحديثة',     '1010006666', '300000000000008', '+966500000006', 2005, 4.5,  198, '{RUH}',                  true),
  ('s7',  'مستودع الأسمنت',           '1010007777', '300000000000009', '+966500000007', 1988, 4.8,  654, '{RUH,DAM,MED}',          true),
  ('s8',  'بلاط الفنون',              '1010008888', '300000000000010', '+966500000008', 2010, 4.7,  287, '{JED,TAI}',              true),
  ('s9',  'دهانات الجزيرة',           '1010009999', '300000000000011', '+966500000009', 1998, 4.8,  543, '{RUH,JED,DAM}',          true),
  ('s10', 'جوتن السعودية',            '1010001122', '300000000000012', '+966500000010', 1990, 4.9, 1102, '{RUH,JED,DAM}',          true);

-- Products (12 products matching site)
insert into products (id, supplier_id, category_id, city_code, name_ar, price, unit_ar, rating, review_count, tag_ar, main_image, stock_quantity, min_order_quantity) values
  ('p1',  's1', 'cat-concrete', 'RUH', 'خرسانة جاهزة C35',                  220,   'م³',  4.9, 584,  'فوري',              'https://images.unsplash.com/photo-1585849132777-22ff9b8ed9ea?auto=format&fit=crop&w=800&q=70', 500, 1),
  ('p2',  's2', 'cat-blocks',   'MED', 'طوب أحمر 20×20×40',                 1.2,   'حبة', 4.8, 312,  'أكثر طلباً',         'https://images.unsplash.com/photo-1590725175842-00d0f2e24e16?auto=format&fit=crop&w=800&q=70', 50000, 1),
  ('p3',  's3', 'cat-rebar',    'DAM', 'حديد تسليح مضلع ١٢مم',              3750,  'طن',  4.9, 826,  'معتمد SASO',        'https://images.unsplash.com/photo-1565372195458-9de0b320ef04?auto=format&fit=crop&w=800&q=70', 200, 1),
  ('p4',  's4', 'cat-equipment','RUH', 'حفّارة هيدروليكية CAT 320',          2400,  'يوم', 4.7, 209,  'تأجير يومي',         'https://images.unsplash.com/photo-1581094794329-c8112a89af12?auto=format&fit=crop&w=800&q=70', 8, 1),
  ('p5',  's5', 'cat-wood',     'JED', 'ألواح خشب الزان للديكور',           420,   'م²',  4.6, 140,  'خشب طبيعي',          'https://images.unsplash.com/photo-1591193686104-fddba4d0e4ff?auto=format&fit=crop&w=800&q=70', 300, 1),
  ('p6',  's6', 'cat-doors',    'RUH', 'باب داخلي خشب MDF',                 950,   'باب', 4.5,  98,  'تركيب مجاني',        'https://images.unsplash.com/photo-1558618666-fcd25c85cd64?auto=format&fit=crop&w=800&q=70', 80, 1),
  ('p7',  's7', 'cat-cement',   'RUH', 'أسمنت بورتلاندي ٥٠ كجم',             16,   'كيس', 4.8, 427,  'جملة',              'https://images.unsplash.com/photo-1599707367072-cd6ada2bc375?auto=format&fit=crop&w=800&q=70', 10000, 10),
  ('p8',  's8', 'cat-tiles',    'JED', 'بلاط بورسلين 60×60',                 45,   'م²',  4.7, 256,  'تشكيلة جديدة',       'https://images.unsplash.com/photo-1620626011761-996317b8d101?auto=format&fit=crop&w=800&q=70', 5000, 5),
  ('p9',  's9', 'cat-paint',    'RUH', 'دهان داخلي إيكونوميك أبيض 18 لتر',  180,  'علبة', 4.8, 198,  'تغطية ممتازة',       'https://images.unsplash.com/photo-1562259949-e8e7689d7828?auto=format&fit=crop&w=800&q=70', 1500, 1),
  ('p10', 's10','cat-paint',    'RUH', 'جوتن لاديوكس ماجيك ١٨ لتر',          640, 'علبة', 4.9, 532,  'صديق للبيئة',         'https://images.unsplash.com/photo-1589939705384-5185137a7f0f?auto=format&fit=crop&w=800&q=70', 800, 1),
  ('p11', 's3', 'cat-rebar',    'DAM', 'حديد تسليح مضلع ١٦مم',              3800, 'طن',  4.9, 412,  'معتمد SASO',         'https://images.unsplash.com/photo-1518709268805-4e9042af9f23?auto=format&fit=crop&w=800&q=70', 150, 1),
  ('p12', 's7', 'cat-cement',   'DAM', 'أسمنت مقاوم للأملاح ٥٠ كجم',         22, 'كيس',  4.7, 189,  'مقاوم',               'https://images.unsplash.com/photo-1503387762-592deb58ef4e?auto=format&fit=crop&w=800&q=70', 6000, 10);

-- Tier pricing for some products
insert into product_tiers (product_id, quantity_label, min_quantity, max_quantity, price, sort_order) values
  ('p1', '1-9 م³',     1, 9,    220, 1),
  ('p1', '10-49 م³',   10, 49,  210, 2),
  ('p1', '50-99 م³',   50, 99,  200, 3),
  ('p1', '100+ م³',    100, null,185, 4),
  ('p3', '1-4 طن',     1, 4,    3750, 1),
  ('p3', '5-19 طن',    5, 19,   3650, 2),
  ('p3', '20-49 طن',   20, 49,  3550, 3),
  ('p3', '50+ طن',     50, null,3450, 4),
  ('p7', '10-99 كيس',  10, 99,  16, 1),
  ('p7', '100-499',    100, 499,15, 2),
  ('p7', '500+',       500, null,14, 3);

-- Sample specs
insert into product_specs (product_id, spec_key, spec_value, sort_order) values
  ('p1', 'قوة الكسر',    '35 MPa',       1),
  ('p1', 'الفئة',        'مسلحة',         2),
  ('p1', 'الكثافة',      '2400 كجم/م³',  3),
  ('p1', 'زمن الصب',     '90 دقيقة',      4),
  ('p1', 'الإضافات',     'ألياف PP',      5),
  ('p1', 'الشهادة',      'SASO 9001-2025',6),
  ('p3', 'القطر',        '12 مم',         1),
  ('p3', 'الطول',        '12 متر',        2),
  ('p3', 'حد الخضوع',    '420 ميجاباسكال',3),
  ('p3', 'الشد',         '500 ميجاباسكال',4),
  ('p3', 'الشهادة',      'SASO 14 / B500B',5);

-- ============================================================================
-- END OF SCHEMA
-- ============================================================================
