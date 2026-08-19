# مداد — Security & Quality Audit Report
**Date:** 3 July 2026 · **Scope:** index.html (frontend), Supabase project `bena`, Vercel deployment
**Status:** critical issues fixed and committed in `14ee5fc` — push to deploy.

---

## 1. Critical bugs — FOUND & FIXED ✅

### 🔴 P0 — Guest RFQ submissions were silently lost
The single most important flow on the site (a visitor sends a price request) only worked for signed-in users. Row-Level Security on `orders` and `rfqs` required `auth.uid() = user_id`, so every submission from a visitor without an account was **rejected by the database while the UI showed "تم إرسال طلب عرض السعر" success**. Confirmed by reproducing the insert as the `anon` role — it failed with an RLS violation. Since most first-time customers won't have accounts at launch, this would have dropped the majority of real leads on November 1.
**Fix shipped:** new `guest order insert` / `guest rfq insert` / `guest order_items insert` policies (guest rows have `user_id = null` and remain readable only by the admin), the frontend no longer requests `RETURNING` for guests (which RLS also blocked), and if saving ever fails the customer now sees an honest error and is bounced to WhatsApp with their request pre-filled instead of a fake success message.

### 🟠 P1 — Unescaped HTML sinks (XSS hardening)
Five `innerHTML` interpolations rendered database values or error messages without escaping: the product-editor category/supplier/city `<select>` builders, the address city selector, and three error-message renderers. Risk was low (values are admin-controlled or Supabase error strings) but these are exactly the sinks that bite later. All now flow through `escapeHtml()`.

### 🟡 Fixed during this session's build
The splash overlay's `display:flex` overrode the `hidden` attribute (would have flashed on every deep link) — caught and fixed before commit.

---

## 2. Security hardening — SHIPPED ✅

- **HTTP security headers** via new `vercel.json`: Content-Security-Policy (scripts/styles limited to self + the three pinned CDNs, connections limited to Supabase/Nominatim/fonts), `X-Content-Type-Options: nosniff`, `X-Frame-Options: DENY` + `frame-ancestors 'none'` (clickjacking), `Referrer-Policy`, `Permissions-Policy` (camera/mic/payment blocked, geolocation self-only). Note: CSP keeps `'unsafe-inline'` because the whole app is one inline script — removing it requires splitting JS into files (see §4).
- **Postgres function hardening:** pinned `search_path = public` on all 8 flagged functions (blocks search-path hijacking); revoked API-level `EXECUTE` on the three trigger functions (`trg_create_profile`, `trg_set_updated_at`, `recalculate_product_rating`) that anonymous visitors could previously call via `/rest/v1/rpc/`.
- Already good (kept): Supabase JS + QRCode pinned with SRI hashes, no passwords in localStorage, supplier documents in a **private** bucket readable only via admin-signed URLs, RLS enabled on all 19 tables.

---

## 3. Remaining risks — YOUR ACTION NEEDED

1. **Enable leaked-password protection** — Supabase Dashboard → Authentication → Passwords → "Prevent use of compromised passwords". One toggle, I can't do it via API.
2. **Spam on public forms** — the RFQ and supplier-registration endpoints accept anonymous writes by design, so bots can flood them. Before launch add Cloudflare Turnstile (free, invisible CAPTCHA) or at least a honeypot field + client throttle. Same applies to the docs bucket (anonymous uploads capped at 5 MB, PDF/image only — but unlimited count).
3. **`hello@bena.sa` in the footer** — old-brand email leftover. Tell me the real address and I'll swap it.
4. **Admin approval doesn't auto-create the supplier** — approving an application marks it ✅ only; you then add the supplier via "الموردون". Fine at low volume; can automate later.
5. **Database performance advisors** (not urgent at current scale): ~15 unindexed foreign keys, `auth.uid()` re-evaluated per row in ~21 policies (wrap as `(select auth.uid())`), duplicate permissive policies. Worth one cleanup migration before real traffic.

---

## 4. Pro recommendations (priority order)

1. **Custom domain** — `medad.sa` / `medadbuild.com` instead of `build-omega-sand.vercel.app`. Biggest single credibility upgrade for ads, WhatsApp links, and SEO. (~15 min in Vercel.)
2. **Analytics** — you're flying blind on conversion. Vercel Analytics (one click) or Plausible; track RFQ submissions and supplier signups as events.
3. **SEO basics** — `og:` and PWA meta shipped today; still missing `robots.txt`, `sitemap.xml`, and JSON-LD `LocalBusiness` structured data. Half a day of work, big payoff for "موردي مواد بناء" searches.
4. **Phone OTP verification** — wire Supabase Auth SMS (Twilio/Msg91) so supplier phone numbers are verified at signup, as your spec wanted.
5. **Split the monolith** — index.html is now ~510 KB inline. Move CSS/JS to separate cached files: faster repeat visits, removes `'unsafe-inline'` from CSP, enables real tooling. Do it gradually after launch; add `package.json` + CI (`npm audit`, HTML validation) at the same time.
6. **Verified phone numbers** — 41 of 44 Medina directory entries are "تواصل معنا" placeholders. Directory value = real numbers.
7. **Uptime + error monitoring** — free UptimeRobot ping + Sentry's free tier for JS errors; right now nobody knows if the site breaks at 2 AM.

---

## 5. Mobile-pro upgrades

**Shipped today:** installable PWA (manifest + branded icons — "Add to Home Screen" now shows the gold-towers icon and opens fullscreen standalone), `theme-color` tinting the browser chrome cream/navy per theme, Apple status-bar styling, WhatsApp/Twitter share cards. Already solid from before: bottom tab bar with safe-area insets, 16 px inputs (no iOS zoom), reduced-motion support, passive scroll listeners.

**Next, in impact order:**
1. **Image optimization** — the 64 Unsplash URLs should carry `?w=640&q=70&auto=format` params and `loading="lazy"`; on 4G this is the difference between a 2 s and 6 s first load.
2. **Service worker** — cache the app shell for instant repeat opens + a friendly offline page; also unlocks Chrome's install prompt.
3. **Font loading** — the Google Fonts `@import` inside `<style>` blocks first paint; switch to `<link rel="preload">` with `font-display: swap` (already set) to kill the Arabic-text flash.
4. **Skeleton loaders** — directory and order tracker show "جارٍ التحميل…" text; shimmer placeholders feel dramatically faster.
5. **One-thumb polish** — sticky "اطلب" CTA already exists; consider a floating WhatsApp bubble on the RFQ page and `navigator.vibrate(10)` haptic on the confetti moments.

---

*Verification performed: all 4 inline scripts syntax-checked, every onclick/onchange handler resolved to a defined function, no duplicate element IDs, RLS policies exercised live as the `anon` role (guest insert ✅, guest read ❌ as intended, docs bucket upload ✅ / read ❌), Supabase security + performance advisors reviewed.*
