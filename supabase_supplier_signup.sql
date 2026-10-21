-- Applied to project bena on 2026-10-21 (migration supplier_applications_cr_number_optional).
-- Supplier signup no longer asks for the CR number, address, email or documents;
-- the team collects them when they contact the supplier to finish registration.
-- Older applications keep their values (and their files in the supplier-docs bucket).
alter table public.supplier_applications alter column cr_number drop not null;
