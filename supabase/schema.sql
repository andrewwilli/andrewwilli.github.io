-- ─────────────────────────────────────────────────────────────────
-- Love Coupons — Supabase Schema
-- Run this in the Supabase SQL Editor (Dashboard → SQL Editor → New query)
-- ─────────────────────────────────────────────────────────────────

-- ── app_state ────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS app_state (
  id         INT PRIMARY KEY DEFAULT 1,
  kisses     INT NOT NULL DEFAULT 0,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT single_row CHECK (id = 1)
);

INSERT INTO app_state (id, kisses) VALUES (1, 0)
ON CONFLICT (id) DO NOTHING;

CREATE OR REPLACE FUNCTION touch_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN NEW.updated_at = NOW(); RETURN NEW; END;
$$;

CREATE OR REPLACE TRIGGER app_state_updated_at
BEFORE UPDATE ON app_state
FOR EACH ROW EXECUTE FUNCTION touch_updated_at();

-- ── coupons ───────────────────────────────────────────────────────
-- Stores all coupons (admin-created and user-suggested).
-- status: 'active' = visible to Ainu | 'pending' = awaiting approval | 'rejected' = hidden
CREATE TABLE IF NOT EXISTS coupons (
  id           TEXT PRIMARY KEY,
  emoji        TEXT NOT NULL DEFAULT '💋',
  title        TEXT NOT NULL,
  kisses       INT  NOT NULL DEFAULT 5,
  teaser       TEXT NOT NULL DEFAULT '',
  description  TEXT NOT NULL DEFAULT '',
  note         TEXT,
  inputs       JSONB NOT NULL DEFAULT '[]',
  status       TEXT NOT NULL DEFAULT 'active'
               CHECK (status IN ('active', 'pending', 'rejected')),
  suggested_by TEXT NOT NULL DEFAULT 'admin'
               CHECK (suggested_by IN ('admin', 'user')),
  sort_order   INT  NOT NULL DEFAULT 0,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE OR REPLACE TRIGGER coupons_updated_at
BEFORE UPDATE ON coupons
FOR EACH ROW EXECUTE FUNCTION touch_updated_at();

-- Seed existing coupons (idempotent)
INSERT INTO coupons (id, emoji, title, kisses, teaser, description, note, inputs, sort_order) VALUES
(
  'massage', '💆‍♀️', 'Full Body Massage with Oil', 7,
  'You relax — management does all the work',
  'You can relax/sleep, pick the music (if you like) and management (me) does the work. Duration: until management''s hands are cramped or you fully fall asleep like a cat.',
  'You can tick options and focus, or leave them blank → management (me) will decide for you.',
  '[{"id":"style","type":"pills","label":"Style (choose one)","max":1,"options":["Spicy massage","Relax massage","Mmmh-don''t-know"]},{"id":"focus","type":"pills","label":"Focus — max 2","max":2,"options":["Feet","Hands","Back","Gesäss","Legs","Shoulders"]}]',
  1
),
(
  'tshirt', '👕', 'T-Shirt of Your Choice', 20,
  'Pick any t-shirt — model it immediately',
  'You can choose and pick one shirt. No hoodie, only t-shirt! Recipient must model in it immediately. Preferably without pants — so the focus is on the shirt on your beautiful body.',
  NULL,
  '[]',
  2
),
(
  'compliments', '💌', 'Full Day of Compliments & Love Notes', 7,
  'A whole day of love, notes & compliments',
  'Fill in the date — for the time we are awake, this effect takes place! You cannot say "stop" or eye roll. Notes are going to be hidden during the day and if possible the day before.',
  NULL,
  '[{"id":"date","type":"date","label":"Choose your day","countdown":true}]',
  3
),
(
  'datenight', '🌙', 'Date Night Planner', 30,
  'Management plans & executes a perfect date',
  'Management (me) will plan and execute a date night. The exact date will be discussed. If food is included, chef accepts "fein" and kisses as payment.',
  NULL,
  '[{"id":"date","type":"date","label":"Preferred date (to be confirmed with management)","countdown":true}]',
  4
),
(
  'royalty', '👑', 'Royalty Treatment', 8,
  'You are officially Queen — command at will',
  'You are officially Queen — the crown from the Love Box is needed to take full effect. You can command while the crown is on your head. I will do literally everything that is possible.',
  '→ No crown, no royalty treatment.',
  '[]',
  5
),
(
  'oral', '✨', 'Oral Pleasure Focus', 9,
  '100% focus on you, no distraction, no timer',
  '100% focus on you — no distraction, no timer (unless you want). Just your pleasure! Recipient must provide feedback with moans.',
  NULL,
  '[{"id":"surprise","type":"toggle","label":"Surprise me","hint":"Tick to have more fun — it is your choice."}]',
  6
),
(
  'sensory', '🎭', 'Blindfold, Ear Plugs & Sensory Play', 7,
  'Senses heightened — maximum teasing',
  'Senses are heightened → maximum teasing. You can tick the box you like, but there is no going back. No peeking or there will be consequences. We can have a safe word so you are still in control.',
  NULL,
  '[{"id":"intensity","type":"pills","label":"Intensity","max":1,"options":["Mean","Normal"]},{"id":"safeword","type":"text","label":"Safe word (optional)","placeholder":"Enter your safe word…"}]',
  7
)
ON CONFLICT (id) DO NOTHING;

-- ── coupon_inputs ─────────────────────────────────────────────────
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
CREATE TABLE IF NOT EXISTS redemptions (
  id            BIGSERIAL PRIMARY KEY,
  coupon_id     TEXT NOT NULL,
  redeemed_date TEXT NOT NULL,
  ts            BIGINT NOT NULL,
  inputs        JSONB NOT NULL DEFAULT '{}',
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS redemptions_coupon_id_idx ON redemptions (coupon_id);
CREATE INDEX IF NOT EXISTS redemptions_ts_idx        ON redemptions (ts DESC);

-- ── activity_log ─────────────────────────────────────────────────
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
-- Row Level Security — anon key is the only auth layer (PIN in frontend)
-- ─────────────────────────────────────────────────────────────────
ALTER TABLE app_state     ENABLE ROW LEVEL SECURITY;
ALTER TABLE coupons       ENABLE ROW LEVEL SECURITY;
ALTER TABLE coupon_inputs ENABLE ROW LEVEL SECURITY;
ALTER TABLE redemptions   ENABLE ROW LEVEL SECURITY;
ALTER TABLE activity_log  ENABLE ROW LEVEL SECURITY;

CREATE POLICY "anon read app_state"   ON app_state FOR SELECT TO anon USING (true);
CREATE POLICY "anon update app_state" ON app_state FOR UPDATE TO anon USING (true) WITH CHECK (true);

CREATE POLICY "anon all coupons"       ON coupons       FOR ALL TO anon USING (true) WITH CHECK (true);
CREATE POLICY "anon all coupon_inputs" ON coupon_inputs FOR ALL TO anon USING (true) WITH CHECK (true);
CREATE POLICY "anon all redemptions"   ON redemptions   FOR ALL TO anon USING (true) WITH CHECK (true);
CREATE POLICY "anon all activity_log"  ON activity_log  FOR ALL TO anon USING (true) WITH CHECK (true);

-- ─────────────────────────────────────────────────────────────────
-- Realtime
-- ─────────────────────────────────────────────────────────────────
ALTER PUBLICATION supabase_realtime ADD TABLE app_state;
ALTER PUBLICATION supabase_realtime ADD TABLE coupons;
