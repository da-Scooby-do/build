# مداد — Midad

Saudi B2B construction-materials brokerage. Contractors send a request; the
owner negotiates with suppliers and returns one complete quote. **Launch:
1 November 2026.**

Arabic-first, RTL. The audience is Saudi contractors, often on mobile data.

---

## Stack

| | |
|---|---|
| Frontend | **One file**: `index.html` (~560 KB, ~13k lines). All CSS and JS inline. No build step. |
| Backend | Supabase — project `bena`, ref `vpvgvmmbmacfufdooahv`, ap-northeast-2 |
| Hosting | Vercel, auto-deploys from `main` |
| Repo | `github.com/da-Scooby-do/build` (private) |
| Domain | `www.midad-ksa.com` (GoDaddy DNS → Vercel) |

Edge Functions: `send-receipt`, `verify-turnstile`.

---

## Working rules

**Give git commands; don't run them.** The owner commits and pushes himself.
Do the file edits, then hand over `git add / commit / push`.

**Never invent claims.** This site publishes to a Saudi audience and the owner
is personally liable for false statements. A previous pass removed a fabricated
VAT number, a false ZATCA certification, SASO badges, and 384 supplier names and
phone numbers. Do not reintroduce anything of that shape: no "certified", no
"verified suppliers", no invented figures, no real brand names in marketing
copy, no named national projects implying partnership. When copy needs a number
that isn't confirmed, write "قيد الإصدار" or leave it out.

**Verify, don't assert.** Every claim about behaviour in this repo should come
from a run: `node --check` on the extracted script blocks, a Playwright pass
over the routes, a SQL read against the live DB. Several bugs here were found
only after instrumenting; speculation missed them.

**Test after every edit.** The site is one file — a syntax error takes down
everything. Extract the four inline `<script>` blocks and `node --check` each.

---

## Gotchas learned the hard way

- **supabase-js resolves with `{ error }`; it does not throw.** A `try/catch`
  around a Supabase call catches nothing. Destructure and check `error`.
- **`INSERT … RETURNING` under RLS without a matching SELECT policy fails with
  42501 and rolls back the whole statement.** Guests therefore use a plain
  INSERT with no `.select()`. Do not "tidy" that back.
- **`\d` in JS does not match Arabic-Indic digits (٠-٩).** This silently zeroed
  the whole admin dashboard.
- **`left: -9999px` in an RTL document widens the page by 10,000 px.** Use the
  clip-path visually-hidden pattern instead.
- **Bare `auth.uid()` in an RLS policy is re-evaluated per row.** All 21
  policies are wrapped as `(select auth.uid())`.
- Two folders were once both called `Build`. The live one is
  `Desktop\Projects\Build`.

---

## Conventions

- Arabic numerals via `arabicDigits()` / `Intl.NumberFormat('ar-SA')`
- Brand: navy `#1D3E63` · amber `#E08A2E`. Marks: `logo.svg`, `icon.svg`, plus
  `-dark.svg` variants for navy surfaces.
- Support number lives once, in `MEDAD_WA`. `syncWhatsAppLinks()` rewrites the
  static hrefs at boot.
- Hero video loads only above 900 px on an unmetered connection; phones get a
  Ken Burns poster. All motion respects `prefers-reduced-motion`.
- Bot guard fails **open**: a broken check must never block a real customer.

---

## Open before launch

1. Delete the four test orders — `docs/CLEANUP_TEST_ORDERS.sql`, run by hand
2. Supabase → Authentication → enable **leaked password protection**
3. SPF mismatch: DNS says `secureserver.net`, MX says Outlook
4. Confirm `info@midad-ksa.com` actually receives mail
5. One unified phone number (the current one is a placeholder)
6. Search Console + Bing Webmaster submission
7. Bot protection layer 3 — revoke anonymous INSERT **only after** a verified
   server-side insert path exists, or guest orders are silently lost again

Deferred on purpose: 85 overlapping RLS policies, 34 unused indexes (review
after a month of real traffic), the dead `checkout()` region.

---

## Docs

`docs/BOT_PROTECTION.md` · `docs/CLEANUP_TEST_ORDERS.sql` · `AUDIT_REPORT.md`
