/**
 * kiss-notify — Supabase Edge Function
 *
 * Receives a kiss request from the app and forwards a Telegram notification
 * to Andrew. Andrew then opens the admin panel to manually credit kisses.
 *
 * ─── Required environment variables ──────────────────────────────────────────
 *   TELEGRAM_TOKEN    Bot token from BotFather  (e.g. 123456:ABC-…)
 *   TELEGRAM_CHAT_ID  Your personal chat ID      (use @userinfobot to find it)
 */

import { serve } from "https://deno.land/std@0.177.0/http/server.ts";

const TELEGRAM_TOKEN   = Deno.env.get("TELEGRAM_TOKEN")!;
const TELEGRAM_CHAT_ID = Deno.env.get("TELEGRAM_CHAT_ID")!;

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

async function tg(method: string, body: Record<string, unknown>) {
  const res = await fetch(`https://api.telegram.org/bot${TELEGRAM_TOKEN}/${method}`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
  return res.json();
}

serve(async (req) => {
  // CORS preflight
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: CORS });
  }

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return new Response(JSON.stringify({ error: "invalid json" }), {
      status: 400,
      headers: { ...CORS, "Content-Type": "application/json" },
    });
  }

  if (body.type === "kiss_request") {
    const amount = Number(body.amount) || 1;

    await tg("sendMessage", {
      chat_id: TELEGRAM_CHAT_ID,
      text:
        `💋 Ainu is asking for ${amount} kiss${amount !== 1 ? "es" : ""}!\n\n` +
        `Open the admin panel to add them to her balance.`,
    });

    return new Response(JSON.stringify({ ok: true }), {
      headers: { ...CORS, "Content-Type": "application/json" },
    });
  }

  return new Response(JSON.stringify({ error: "unrecognised request" }), {
    status: 400,
    headers: { ...CORS, "Content-Type": "application/json" },
  });
});
