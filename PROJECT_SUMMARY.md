# BENA — Project Handoff Summary

> Paste this whole file into a new Claude chat to continue working on the project.

---

## 1. What this project is

**BENA (بِناء)** is a B2B/B2C marketplace website that connects contractors and individuals in **Saudi Arabia** with suppliers of building materials (steel, concrete, wood, doors, etc.).

- Language: **Arabic (RTL)** — `<html lang="ar" dir="rtl">`
- Market: Saudi Arabia (cities, SAR currency, SASO badges, CR numbers, Hijri-aware UI)
- Role: middleman between **stores/suppliers** and **customers/contractors**

---

## 2. Tech stack

- **Backend:** Node.js (>=22.5) + Express 4
- **Database:** SQLite via the built-in `node:sqlite` module (no `better-sqlite3` install needed)
- **Auth:** `bcryptjs` for passwords, `jsonwebtoken` for sessions, plus a phone OTP flow
- **Frontend:** Plain HTML + CSS + vanilla JS (no framework, no build step)
- **Extras:** `qrcode.js` (CDN) for payment/order QR codes
- **Run:** `npm start` → serves API + static files on `http://localhost:3000`

---

## 3. File layout

```
Build/
├── index.html          # Main SPA-style page (~2,283 lines): home, catalog, product, cart, checkout, auth, dashboard, RFQ
├── materials.html      # Static materials category landing page
├── concrete.html       # Static concrete category landing page
├── styles.css          # Full design system (~1,318 lines): tokens, dark mode, components
├── package.json        # Deps: express, cors, bcryptjs, jsonwebtoken
├── bena.db             # SQLite database (auto-created on first run)
└── server/
    ├── server.js       # Express app + all REST routes
    └── db.js           # Schema + seed data (suppliers, products)
```

---

## 4. Database schema (SQLite, in `server/db.js`)

| Table            | Purpose                                                                |
| ---------------- | ---------------------------------------------------------------------- |
| `users`          | id, name, email, phone, password (bcrypt), role (customer/supplier)    |
| `otps`           | phone OTP codes with expiry                                            |
| `suppliers`      | id, name, cities (JSON), rating, CR number, verified, SASO badge, etc. |
| `products`       | id, name, category, city, supplier_id, price, unit, specs/tiers (JSON) |
| `reviews`        | productId, userId, rating, comment                                     |
| `cart_items`     | userId + productId + qty                                               |
| `wishlist_items` | userId + productId                                                     |
| `orders`         | userId, items (JSON), total, status, address, payment method           |
| `rfqs`           | request-for-quote submissions (guest or logged-in)                     |

`db.js` seeds suppliers + products on first run.

---

## 5. REST API (in `server/server.js`)

**Auth**
- `POST /api/auth/signup` — name, email/phone, password
- `POST /api/auth/login` — returns JWT
- `POST /api/auth/otp/send` — phone
- `POST /api/auth/otp/verify` — phone + code → JWT
- `GET  /api/auth/me` (auth) — current user

**Catalog (public)**
- `GET /api/suppliers`, `GET /api/suppliers/:id`
- `GET /api/products?category=&city=&q=&min=&max=`
- `GET /api/products/:id`
- `GET /api/reviews/:productId`
- `POST /api/reviews` (auth)

**Cart / Wishlist (auth)**
- `GET/POST/PUT/DELETE /api/cart` and `/api/cart/:productId`
- `GET/POST/DELETE /api/wishlist`

**Orders & RFQ**
- `POST /api/orders` (auth optional — guest checkout allowed)
- `GET  /api/orders` (auth)
- `POST /api/rfq` (auth optional)

**Misc**
- `GET /api/health`, `GET /api/meta` (categories, cities)
- SPA fallback: any non-`/api` route serves `index.html`

JWT secret env var: `JWT_SECRET` (defaults to a dev secret — **change for production**).
DB path env var: `BENA_DB`.

---

## 6. Frontend pages (inside `index.html`)

`index.html` is a single-page app that swaps between view sections:

- `view-home` — hero search, featured categories, top suppliers, CTA band
- `view-catalog` — product list with category/city/price filters + search
- `view-product` — product detail, gallery, specs, tiered pricing, reviews
- `view-cart`, `view-checkout` — cart + payment (cash/card/Mada/Apple Pay UI)
- `view-auth` — login/signup + OTP
- `view-dashboard` — orders, wishlist, profile
- `view-rfq` — request-for-quote form
- `view-suppliers` / supplier detail

Has a **dark mode toggle** (`toggleTheme()`), Arabic RTL throughout, and CSS design tokens in `:root` + `[data-theme="dark"]`.

---

## 7. How to run locally

```bash
cd Build
npm install
npm start
# open http://localhost:3000
```

Node 22.5+ required (uses built-in `node:sqlite`).

---

## 8. Open work / things you might want next

These are likely follow-ups — pick whichever you want to tackle in the next session:

1. **Supplier dashboard** — let suppliers log in, manage their own products/orders (role = `supplier` already exists in DB but no UI yet).
2. **Real payment integration** — currently the checkout UI is mock. Hook up Mada/HyperPay/Tap/Moyasser.
3. **Image uploads** — products use placeholder image URLs; add file upload + storage.
4. **Search improvements** — Arabic-aware fuzzy search, sort by rating/price/distance.
5. **Order tracking** — driver/delivery status updates beyond the current `status` enum.
6. **Email/SMS** — OTP currently logs to console; integrate Unifonic/Twilio for real SMS.
7. **Admin panel** — approve suppliers, moderate reviews, see platform-wide orders.
8. **i18n toggle** — add English alongside Arabic (structure is RTL-only right now).
9. **Move static `materials.html` and `concrete.html`** into the SPA, or vice versa, for consistency.
10. **Tests** — no test suite exists yet.

---

## 9. Conventions / things to keep in mind

- All UI copy is in **Arabic**. Keep it Arabic when adding features unless adding i18n.
- Currency is **SAR (ر.س)**, prices are per unit (per ton, per m³, per sheet, etc.).
- Cities used in seed data: Riyadh, Jeddah, Dammam, Mecca, Medina, etc. — follow the same list when adding products.
- Suppliers carry a **CR (Commercial Registration) number** and optional **SASO** badge — these are Saudi-specific trust signals; keep them visible in supplier cards.
- The frontend uses **CSS custom properties** for theming — add new colors as tokens, not hardcoded hex.
- JWT is stored in `localStorage` on the client (`bena_token`). API calls send it as `Authorization: Bearer <token>`.

---

## 10. Quick prompt to paste into a new Claude chat

> I'm continuing work on **BENA**, an Arabic-language Saudi construction materials marketplace. It's a Node.js + Express + SQLite app with a vanilla HTML/CSS/JS frontend (`index.html` SPA + `materials.html`, `concrete.html`). The backend is in `server/server.js` with SQLite schema in `server/db.js`. Auth uses JWT + bcrypt + phone OTP. Read `PROJECT_SUMMARY.md` in the project folder for full context, then help me with: **[describe the next task here]**.
