-- Applied to project bena on 2026-10-21 (migration supplier_applications_cr_number_optional).
-- Supplier signup no longer asks for the CR number, address, email or documents;
-- the team collects them when they contact the supplier to finish registration.
-- Older applications keep their values (and their files in the supplier-docs bucket).
alter table public.supplier_applications alter column cr_number drop not null;

-- Applied 2026-10-21 (migration supplier_applications_insert_pending_only).
-- The approved count is public (joined_supplier_count), so guests must not be
-- able to insert pre-approved rows. Guests: pending only. Admins: any status
-- (used by the admin "إضافة مورد من واتساب" form).
alter policy "anyone can apply" on public.supplier_applications
  with check (
    (status = 'pending' and reviewed_at is null)
    or (select public.is_admin())
  );
