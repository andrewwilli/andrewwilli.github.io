-- ─────────────────────────────────────────────────────────────────
-- Love Coupons — Supabase Schema
-- Run this in the Supabase SQL Editor (Dashboard → SQL Editor → New query)
-- ─────────────────────────────────────────────────────────────────

-- ── app_state ────────────────────────────────────────────────────
-- Single row (id = 1) that holds the kiss balance.
-- Updated by the app on spend/credit and by the Edge Function on remote approval.
CREATE TABLE IF NOT EXISTS app_state (
  id         INT PRIMARY KEY DEFAULT 1,
  kisses     INT NOT NULL DEFAULT 0,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT single_row CHECK (id = 1)
);

-- Seed the one row
INSERT INTO app_state (id, kisses) VALUES (1, 0)
ON CONFLICT (id) DO NOTHING;

-- Automatically bump updated_at on every write
CREATE OR REPLACE FUNCTION touch_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN NEW.updated_at = NOW(); RETURN NEW; END;
$$;

CREATE OR REPLACE TRIGGER app_state_updated_at
BEFORE UPDATE ON app_state
FOR EACH ROW EXECUTE FUNCTION touch_updated_at();

-- ── coupon_inputs ─────────────────────────────────────────────────
-- Stores the in-progress form selections per coupon (pre-redemption draft).
-- One row per coupon_id; upserted on every field change.
CREATE TABLE IF NOT EXISTS coupon_inputs (
  id         BIGSERIAL PRIMARY KEY,
  coupon_id  TEXT NOT NULL UNIQUE,
  inputs     JSONB NOT NULL DEFAULT '{}',
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE OR REPLACE TRIGGER coupon_inputs_updated_at
BEFORE UPDATE ON coupon_inputs
FOR EACH ROW EXECUTE FUNCTION touch_updated_at();

-- ── redemptions ───────────────────────────────────────────────────
-- One row per redemption event.
CREATE TABLE IF NOT EXISTS redemptions (
  id            BIGSERIAL PRIMARY KEY,
  coupon_id     TEXT NOT NULL,
  redeemed_date TEXT NOT NULL,           -- formatted, e.g. "8 April 2026"
  ts            BIGINT NOT NULL,         -- unix ms
  inputs        JSONB NOT NULL DEFAULT '{}',
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS redemptions_coupon_id_idx ON redemptions (coupon_id);
CREATE INDEX IF NOT EXISTS redemptions_ts_idx        ON redemptions (ts DESC);

-- ── activity_log ─────────────────────────────────────────────────
-- Append-only ledger of every credit and spend.
CREATE TABLE IF NOT EXISTS activity_log (
  id         BIGSERIAL PRIMARY KEY,
  type       TEXT NOT NULL CHECK (type IN ('credit', 'redeem')),
  amount     INT NOT NULL,
  note       TEXT,
  coupon_id  TEXT,
  ts         BIGINT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS activity_log_ts_idx ON activity_log (ts DESC);

-- ─────────────────────────────────────────────────────────────────
-- Row Level Security
-- The app uses the anon key (no Supabase auth), so we grant anon
-- full access to all four tables.  The PIN in the frontend is the
-- only access control layer.
-- ─────────────────────────────────────────────────────────────────
ALTER TABLE app_state     ENABLE ROW LEVEL SECURITY;
ALTER TABLE coupon_inputs ENABLE ROW LEVEL SECURITY;
ALTER TABLE redemptions   ENABLE ROW LEVEL SECURITY;
ALTER TABLE activity_log  ENABLE ROW LEVEL SECURITY;

-- app_state: anon may read and update (but not insert/delete —
-- the seed INSERT above creates the only row)
CREATE POLICY "anon read app_state"
  ON app_state FOR SELECT TO anon USING (true);
CREATE POLICY "anon update app_state"
  ON app_state FOR UPDATE TO anon USING (true) WITH CHECK (true);

-- coupon_inputs: anon full CRUD
CREATE POLICY "anon all coupon_inputs"
  ON coupon_inputs FOR ALL TO anon USING (true) WITH CHECK (true);

-- redemptions: anon full CRUD
CREATE POLICY "anon all redemptions"
  ON redemptions FOR ALL TO anon USING (true) WITH CHECK (true);

-- activity_log: anon full CRUD
CREATE POLICY "anon all activity_log"
  ON activity_log FOR ALL TO anon USING (true) WITH CHECK (true);

-- ─────────────────────────────────────────────────────────────────
-- Enable Realtime on app_state so the app gets live balance updates
-- (Dashboard → Database → Replication → toggle app_state)
-- Or run:
-- ─────────────────────────────────────────────────────────────────
ALTER PUBLICATION supabase_realtime ADD TABLE app_state;
