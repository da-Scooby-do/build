# Supabase Setup Guide for BENA / بِناء

Step-by-step guide to set up the backend for your building materials marketplace.

---

## Step 1: Create a Supabase project

1. Go to https://supabase.com and sign up (you can sign in with GitHub).
2. Click **New project**.
3. Fill in:
   - **Name**: `bena` (or whatever you want)
   - **Database password**: create a strong password and **save it somewhere safe** — you'll need it
   - **Region**: choose **Middle East (Bahrain)** — closest to Saudi Arabia, lowest latency
   - **Plan**: Free is fine to start
4. Click **Create new project**. Wait 2–3 minutes for it to provision.

---

## Step 2: Run the schema

1. Once the project is ready, click **SQL Editor** in the left sidebar.
2. Click **New query**.
3. Open `supabase_schema.sql` from this folder in a text editor.
4. Copy the entire contents and paste it into the SQL Editor.
5. Click **Run** (or `Ctrl+Enter`).
6. You should see "Success. No rows returned." — that means all tables, indexes, triggers, RLS policies, and seed data have been created.

If you get an error, copy the error message and ask me to fix it.

---

## Step 3: Verify the tables

1. Click **Table Editor** in the left sidebar.
2. You should see all these tables in the list:
   - profiles, suppliers, products, product_images, product_specs, product_tiers
   - categories, cities
   - addresses, cart_items, wishlist
   - orders, order_items, reviews
   - rfqs, rfq_items, rfq_responses
   - zatca_invoices
3. Click on `cities` — you should see 10 Saudi cities pre-loaded.
4. Click on `products` — you should see 12 products from your site.

---

## Step 4: Create storage buckets

For storing product images, supplier logos, and user avatars.

1. Click **Storage** in the left sidebar.
2. Click **New bucket**.
3. Create these four buckets one by one:

| Bucket name | Public? | Purpose |
|---|---|---|
| `product-images` | Yes | Photos of products |
| `supplier-logos` | Yes | Supplier branding |
| `user-avatars` | Yes | Customer profile photos |
| `invoices` | No | Generated ZATCA PDFs |

For each public bucket, leave the policies as default (anyone can read). For `invoices`, leave it private.

---

## Step 5: Configure Auth (phone OTP)

1. Click **Authentication** → **Providers** in the sidebar.
2. Enable **Phone** provider.
3. You'll need an SMS provider. Cheapest options for Saudi:
   - **Twilio** — easy setup, but needs sender registration in KSA
   - **Unifonic** — Saudi-based SMS provider, has Arabic templates
   - **Vonage** — works in Saudi
4. Get API credentials from your chosen provider and paste them into Supabase.
5. Also enable **Email** provider so people can sign up with email as a fallback.

---

## Step 6: Get your API keys

1. Click **Project Settings** (gear icon) → **API**.
2. Copy these two values — you'll need them in your `index.html`:
   - **Project URL** (e.g. `https://abcdefghijk.supabase.co`)
   - **anon / public key** (a long JWT string)

**NEVER commit the `service_role` key to GitHub.** It bypasses RLS and has full admin access.

---

## Step 7: Connect your site to Supabase

In your `index.html`, add this near the top of the `<script>` block:

```js
// Load Supabase client from CDN
const SUPABASE_URL = 'https://YOUR-PROJECT.supabase.co';
const SUPABASE_ANON_KEY = 'YOUR-ANON-KEY-HERE';

// In <head>, add this before your existing scripts:
// <script src="https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2"></script>

const supabase = window.supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY);

// Example: fetch all products
async function loadProducts() {
  const { data, error } = await supabase
    .from('products')
    .select(`
      *,
      supplier:suppliers(name_ar, rating),
      images:product_images(url),
      specs:product_specs(spec_key, spec_value),
      tiers:product_tiers(quantity_label, price)
    `)
    .eq('is_active', true);

  if (error) { console.error(error); return []; }
  return data;
}

// Example: sign up with phone
async function signUpWithPhone(phone) {
  const { data, error } = await supabase.auth.signInWithOtp({ phone });
  return { data, error };
}

// Example: place an order
async function placeOrder(items, addressId, paymentMethod) {
  const { data: order, error } = await supabase
    .from('orders')
    .insert({
      order_number: await supabase.rpc('generate_order_number'),
      subtotal: 0,            // calculate from items
      vat_amount: 0,
      total: 0,
      payment_method: paymentMethod,
      delivery_address_id: addressId,
    })
    .select()
    .single();
  // then insert order_items rows
  return order;
}
```

---

## Important security notes

1. **RLS is on for every table.** That means an anonymous user can only see public data (catalogs, suppliers, products). Logged-in users can only see/modify their own data.

2. **The anon key is safe to put in your frontend.** Even though it's "public", RLS rules prevent abuse.

3. **The service_role key is NEVER safe in the frontend.** Only use it in serverless functions or Edge Functions if you absolutely need to bypass RLS.

4. **For admin tasks** (like adding new products or managing suppliers), build a separate admin panel that uses authenticated requests, not the service_role key.

---

## Schema overview

Here's what each table is for:

**Catalog (public read):**
- `cities` — Saudi cities
- `categories` — product categories (concrete, blocks, doors, etc.)
- `suppliers` — vendor accounts
- `products` — items for sale
- `product_images` — multiple photos per product
- `product_specs` — flexible key/value specs (e.g. "Strength: 35 MPa")
- `product_tiers` — volume discount tiers (1–9 → 220 SAR, 10–49 → 210 SAR)

**Customer-owned data (RLS: only owner can see/edit):**
- `profiles` — extends auth.users
- `addresses` — Saudi National Address format (building #, street, district, city, postal code, additional #)
- `cart_items`, `wishlist`
- `orders`, `order_items`

**Reviews:** only verified buyers (delivered orders) can post.

**RFQ system:** customers post quote requests, suppliers in their city can respond.

**ZATCA invoices:** auto-generated for Saudi tax compliance.

---

## What to do next

1. Run the schema above ✓
2. Get your project URL and anon key
3. Replace the hardcoded `SUPPLIERS` and `PRODUCTS` arrays in your `index.html` with calls to Supabase
4. Set up phone auth with an SMS provider
5. Integrate a payment gateway (Moyasar is easiest for KSA — it has REST API + JS SDK)

When you're ready for step 3 or 4, tell me and I'll write the JavaScript that hooks your existing UI up to the database.

---

## Common gotchas

- **"new row violates row-level security policy"** — you're trying to write to a table from an anonymous session. Either sign in first, or check that your RLS policy allows the operation.
- **"function gen_random_uuid() does not exist"** — make sure the `pgcrypto` extension at the top of the SQL ran successfully.
- **Slow queries** — the schema has indexes on common lookup columns, but if you're filtering by something not indexed, add an index.
- **Arabic text showing as `???`** — make sure your database connection uses UTF-8 (Supabase does by default).
