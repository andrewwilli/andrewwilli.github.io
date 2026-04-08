/**
 * kiss-notify — Supabase Edge Function
 *
 * Handles two kinds of incoming requests:
 *
 *  1. App request  POST { type: "kiss_request", amount: N }
 *     → Sends a Telegram message to Andrew with Approve / Deny buttons.
 *
 *  2. Telegram webhook  POST { callback_query: { ... } }
 *     → Andrew tapped Approve or Deny on the Telegram message.
 *     → On Approve: credits kisses in Supabase so the app updates live.
 *
 * ─── Required environment variables (set in Supabase Dashboard → Edge Functions → Secrets) ───
 *   TELEGRAM_TOKEN        Bot token from BotFather  (e.g. 123456:ABC-…)
 *   TELEGRAM_CHAT_ID      Your personal chat ID      (use @userinfobot to find it)
 *   TELEGRAM_WEBHOOK_SECRET  Any random string — set the same value when registering the webhook
 *   SUPABASE_URL          Injected automatically by Supabase
 *   SUPABASE_SERVICE_ROLE_KEY  Injected automatically by Supabase
 *
 * ─── One-time webhook registration ────────────────────────────────────────────────────────────
 *   curl "https://api.telegram.org/bot<TOKEN>/setWebhook" \
 *     -d "url=https://<project>.supabase.co/functions/v1/kiss-notify" \
 *     -d "secret_token=<TELEGRAM_WEBHOOK_SECRET>"
 */

import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const TELEGRAM_TOKEN          = Deno.env.get("TELEGRAM_TOKEN")!;
const TELEGRAM_CHAT_ID        = Deno.env.get("TELEGRAM_CHAT_ID")!;
const TELEGRAM_WEBHOOK_SECRET = Deno.env.get("TELEGRAM_WEBHOOK_SECRET") ?? "";
const SUPABASE_URL            = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_KEY    = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

// ── Telegram helper ──────────────────────────────────────────────
async function tg(method: string, body: Record<string, unknown>) {
  const res = await fetch(`https://api.telegram.org/bot${TELEGRAM_TOKEN}/${method}`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
  return res.json();
}

// ── Supabase admin client (bypasses RLS) ────────────────────────
function adminClient() {
  return createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY);
}

// ── Main handler ─────────────────────────────────────────────────
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

  // ── 1. App → kiss request notification ──────────────────────────
  if (body.type === "kiss_request") {
    const amount = Number(body.amount) || 1;

    // Encode amount in callback_data (max 64 bytes, "approve:NNN" is safe)
    await tg("sendMessage", {
      chat_id: TELEGRAM_CHAT_ID,
      text:
        `💋 Ainu is asking for ${amount} kiss${amount !== 1 ? "es" : ""}!\n\n` +
        `Tap ✓ Approve to add them to her balance right now.`,
      reply_markup: {
        inline_keyboard: [[
          {
            text: `✓ Approve ${amount} kiss${amount !== 1 ? "es" : ""}`,
            callback_data: `approve:${amount}`,
          },
          { text: "✗ Deny", callback_data: "deny" },
        ]],
      },
    });

    return new Response(JSON.stringify({ ok: true }), {
      headers: { ...CORS, "Content-Type": "application/json" },
    });
  }

  // ── 2. Telegram → webhook callback ──────────────────────────────
  // Validate the secret token header Telegram sends
  const telegramSecret = req.headers.get("x-telegram-bot-api-secret-token") ?? "";
  if (TELEGRAM_WEBHOOK_SECRET && telegramSecret !== TELEGRAM_WEBHOOK_SECRET) {
    return new Response("unauthorized", { status: 401 });
  }

  if (body.callback_query) {
    const cbq   = body.callback_query as Record<string, unknown>;
    const cbId  = cbq.id as string;
    const data  = cbq.data as string;
    const msg   = cbq.message as Record<string, unknown>;
    const chatId  = (msg.chat as Record<string, unknown>).id as number;
    const msgId   = msg.message_id as number;
    const origText = msg.text as string;

    if (data === "deny") {
      await tg("answerCallbackQuery", { callback_query_id: cbId, text: "Request denied." });
      await tg("editMessageText", {
        chat_id: chatId,
        message_id: msgId,
        text: origText + "\n\n✗ Denied.",
        reply_markup: { inline_keyboard: [] },
      });
    } else if (data.startsWith("approve:")) {
      const amount = parseInt(data.split(":")[1]) || 0;
      const supabase = adminClient();

      // Read current balance, add kisses, write back
      const { data: state } = await supabase
        .from("app_state")
        .select("kisses")
        .eq("id", 1)
        .single();

      const currentKisses = (state as { kisses: number } | null)?.kisses ?? 0;
      const newBalance = currentKisses + amount;

      await supabase
        .from("app_state")
        .update({ kisses: newBalance })
        .eq("id", 1);

      await supabase.from("activity_log").insert({
        type: "credit",
        amount,
        note: "Approved via Telegram 💌",
        ts: Date.now(),
      });

      await tg("answerCallbackQuery", {
        callback_query_id: cbId,
        text: `✓ ${amount} kiss${amount !== 1 ? "es" : ""} added! New balance: ${newBalance} 💋`,
        show_alert: true,
      });

      await tg("editMessageText", {
        chat_id: chatId,
        message_id: msgId,
        text:
          origText +
          `\n\n✓ Approved! Added ${amount} kiss${amount !== 1 ? "es" : ""}.\nNew balance: ${newBalance} 💋`,
        reply_markup: { inline_keyboard: [] },
      });
    }

    return new Response(JSON.stringify({ ok: true }), {
      headers: { ...CORS, "Content-Type": "application/json" },
    });
  }

  return new Response(JSON.stringify({ error: "unrecognised request" }), {
    status: 400,
    headers: { ...CORS, "Content-Type": "application/json" },
  });
});
