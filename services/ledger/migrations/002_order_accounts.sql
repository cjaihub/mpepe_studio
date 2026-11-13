-- Per-order accounts (o:{orderId}:escrow_{cur}) for Oneova Pay escrow, so the
-- database itself refuses to release more than an order received.
ALTER TABLE accounts DROP CONSTRAINT IF EXISTS accounts_id_check;
ALTER TABLE accounts ADD CONSTRAINT accounts_id_check
  CHECK (id ~ '^(u|sys|p|o):[A-Za-z0-9_-]{1,128}(:[a-z_]{1,32})?$');
INSERT INTO schema_migrations (version) VALUES ('002_order_accounts');
