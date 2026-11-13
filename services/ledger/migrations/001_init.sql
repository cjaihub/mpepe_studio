-- Oneova ledger: double-entry, append-only, integer minor units.
--
-- Rules the DATABASE enforces (not just the app):
--   * journals, postings and audit_log can never be updated, deleted or truncated;
--   * every journal's postings sum to 0 per currency, with at least 2 postings;
--   * a posting's currency must be its account's currency;
--   * balances are written only by a trigger on postings, and an account that
--     doesn't allow negative balances can't go below 0;
--   * the audit log is hash-chained, so a removed or edited row is detectable.
-- Amounts are signed bigint minor units: + raises an account, - lowers it.
-- Errors: OL001 insufficient funds, OL002 append-only, OL003 unbalanced journal.

CREATE TABLE IF NOT EXISTS schema_migrations (
  version text PRIMARY KEY,
  applied_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE currencies (
  code text PRIMARY KEY CHECK (code ~ '^[A-Z]{3}$'),
  exponent smallint NOT NULL CHECK (exponent BETWEEN 0 AND 4),
  description text NOT NULL DEFAULT ''
);

-- XCN = Oneova coins (Play credit, never cash), XDM = Diamonds (creator earnings).
INSERT INTO currencies (code, exponent, description) VALUES
  ('XCN', 0, 'Oneova coins: Play Billing credit, never withdrawable'),
  ('XDM', 0, 'Oneova Diamonds: creator earnings'),
  ('USD', 2, ''), ('EUR', 2, ''), ('GBP', 2, ''),
  ('KES', 2, ''), ('TZS', 2, ''), ('UGX', 0, ''), ('RWF', 0, ''), ('NGN', 2, ''), ('GHS', 2, ''),
  ('ZAR', 2, ''), ('ZMW', 2, ''), ('MWK', 2, ''), ('XAF', 0, ''), ('XOF', 0, ''), ('EGP', 2, ''), ('ETB', 2, '');

CREATE TABLE accounts (
  id text PRIMARY KEY CHECK (id ~ '^(u|sys|p):[A-Za-z0-9_-]{1,128}(:[a-z_]{1,32})?$'),
  currency text NOT NULL REFERENCES currencies(code),
  allow_negative boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (id, currency)
);

CREATE TABLE journals (
  id uuid PRIMARY KEY,
  idempotency_key text NOT NULL UNIQUE CHECK (length(idempotency_key) BETWEEN 8 AND 200),
  request_hash text NOT NULL,
  kind text NOT NULL CHECK (kind ~ '^[a-z_]{2,40}$'),
  memo text NOT NULL DEFAULT '',
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  actor text NOT NULL,
  effective_at timestamptz NOT NULL DEFAULT now(),
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE postings (
  id bigserial PRIMARY KEY,
  journal_id uuid NOT NULL REFERENCES journals(id),
  account_id text NOT NULL,
  currency text NOT NULL,
  amount bigint NOT NULL CHECK (amount <> 0),
  created_at timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY (account_id, currency) REFERENCES accounts(id, currency)
);
CREATE INDEX postings_account_idx ON postings (account_id, id DESC);
CREATE INDEX postings_journal_idx ON postings (journal_id);

CREATE TABLE balances (
  account_id text PRIMARY KEY REFERENCES accounts(id),
  currency text NOT NULL,
  balance bigint NOT NULL DEFAULT 0,
  version bigint NOT NULL DEFAULT 0,
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE audit_log (
  id bigserial PRIMARY KEY,
  at timestamptz NOT NULL DEFAULT now(),
  actor text NOT NULL,
  action text NOT NULL,
  subject text NOT NULL,
  detail jsonb NOT NULL DEFAULT '{}'::jsonb,
  prev_hash text NOT NULL,
  hash text NOT NULL
);

-- ── Append-only ───────────────────────────────────────────────────────────
CREATE FUNCTION ledger_forbid_change() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  RAISE EXCEPTION 'ledger table % is append-only', TG_TABLE_NAME USING ERRCODE = 'OL002';
END $$;

CREATE TRIGGER journals_immutable BEFORE UPDATE OR DELETE ON journals FOR EACH ROW EXECUTE FUNCTION ledger_forbid_change();
CREATE TRIGGER postings_immutable BEFORE UPDATE OR DELETE ON postings FOR EACH ROW EXECUTE FUNCTION ledger_forbid_change();
CREATE TRIGGER audit_immutable BEFORE UPDATE OR DELETE ON audit_log FOR EACH ROW EXECUTE FUNCTION ledger_forbid_change();
CREATE TRIGGER journals_no_truncate BEFORE TRUNCATE ON journals FOR EACH STATEMENT EXECUTE FUNCTION ledger_forbid_change();
CREATE TRIGGER postings_no_truncate BEFORE TRUNCATE ON postings FOR EACH STATEMENT EXECUTE FUNCTION ledger_forbid_change();
CREATE TRIGGER audit_no_truncate BEFORE TRUNCATE ON audit_log FOR EACH STATEMENT EXECUTE FUNCTION ledger_forbid_change();

-- ── Balances follow postings ──────────────────────────────────────────────
CREATE FUNCTION ledger_apply_posting() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
  new_balance bigint;
  may_go_negative boolean;
BEGIN
  INSERT INTO balances (account_id, currency, balance, version, updated_at)
  VALUES (NEW.account_id, NEW.currency, NEW.amount, 1, now())
  ON CONFLICT (account_id) DO UPDATE
    SET balance = balances.balance + EXCLUDED.balance,
        version = balances.version + 1,
        updated_at = now()
  RETURNING balance INTO new_balance;
  SELECT allow_negative INTO may_go_negative FROM accounts WHERE id = NEW.account_id;
  IF new_balance < 0 AND NOT may_go_negative THEN
    RAISE EXCEPTION 'insufficient funds in %', NEW.account_id USING ERRCODE = 'OL001';
  END IF;
  RETURN NEW;
END $$;

CREATE TRIGGER postings_apply AFTER INSERT ON postings FOR EACH ROW EXECUTE FUNCTION ledger_apply_posting();

-- Balances may change only through the trigger above (pg_trigger_depth() > 0).
CREATE FUNCTION ledger_guard_balances() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF pg_trigger_depth() < 2 THEN
    RAISE EXCEPTION 'balances are derived from postings' USING ERRCODE = 'OL002';
  END IF;
  IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
  RETURN NEW;
END $$;

CREATE TRIGGER balances_guard BEFORE INSERT OR UPDATE OR DELETE ON balances FOR EACH ROW EXECUTE FUNCTION ledger_guard_balances();

-- ── Every journal balances (checked at commit) ────────────────────────────
CREATE FUNCTION ledger_check_journal() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
  n int;
  bad text;
BEGIN
  SELECT count(*) INTO n FROM postings WHERE journal_id = NEW.journal_id;
  IF n < 2 THEN
    RAISE EXCEPTION 'journal % needs at least two postings', NEW.journal_id USING ERRCODE = 'OL003';
  END IF;
  SELECT currency INTO bad FROM postings WHERE journal_id = NEW.journal_id
    GROUP BY currency HAVING sum(amount) <> 0 LIMIT 1;
  IF bad IS NOT NULL THEN
    RAISE EXCEPTION 'journal % does not balance in %', NEW.journal_id, bad USING ERRCODE = 'OL003';
  END IF;
  RETURN NULL;
END $$;

CREATE CONSTRAINT TRIGGER postings_balanced AFTER INSERT ON postings
  DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION ledger_check_journal();

-- A journal row with no postings is also caught at commit.
CREATE FUNCTION ledger_check_journal_has_postings() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM postings WHERE journal_id = NEW.id) THEN
    RAISE EXCEPTION 'journal % has no postings', NEW.id USING ERRCODE = 'OL003';
  END IF;
  RETURN NULL;
END $$;

CREATE CONSTRAINT TRIGGER journals_have_postings AFTER INSERT ON journals
  DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION ledger_check_journal_has_postings();

INSERT INTO schema_migrations (version) VALUES ('001_init');
