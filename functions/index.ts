// Ballpark Diary backend — TripIt-style ticket forwarding.
//
// Users forward (or auto-forward) ticket-receipt emails to a personal address
// like `<token>@<INBOUND_EMAIL_DOMAIN>`. An inbound email provider (SendGrid
// Inbound Parse, Mailgun Routes, Postmark, CloudMailin, etc.) POSTs the email
// to /inbound. We parse it for an MLB matchup and stash a candidate in the
// per-token ForwardInbox Durable Object. The app polls /pending, confirms each
// candidate against the real MLB schedule on-device, then calls /ack.

import { detectCandidate, type DetectedCandidate } from "./parser";

export { ForwardInbox } from "./forward-inbox";

type Env = {
  DO: Fetcher;
  INBOUND_EMAIL_DOMAIN?: string;
};

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type, Authorization",
};

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, "Content-Type": "application/json" },
  });
}

/** Only allow tokens that are safe as an email local-part and DO id. */
function isValidToken(token: string): boolean {
  return /^[a-z0-9]{8,40}$/.test(token);
}

function inbox(env: Env, token: string, path: string, init?: RequestInit): Promise<Response> {
  const req = new Request(`https://do/${path}`, init);
  req.headers.set("X-Rork-DO-Class", "ForwardInbox");
  req.headers.set("X-Rork-DO-Id", token);
  return env.DO.fetch(req);
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    if (request.method === "OPTIONS") return new Response(null, { status: 204, headers: CORS });

    const url = new URL(request.url);
    const path = url.pathname;

    if (path === "/ping") return json({ ok: true, now: new Date().toISOString() });

    // Tell the app which forwarding domain to display.
    if (path === "/config" && request.method === "GET") {
      const domain = env.INBOUND_EMAIL_DOMAIN ?? "";
      return json({ domain, configured: domain.length > 0 });
    }

    // The app builds its address as `<token>@<domain>`; this just echoes it back
    // so the UI can show a confirmed value and we can validate the token early.
    if (path === "/register" && request.method === "GET") {
      const token = url.searchParams.get("token") ?? "";
      if (!isValidToken(token)) return json({ error: "invalid token" }, 400);
      const domain = env.INBOUND_EMAIL_DOMAIN ?? "";
      return json({
        configured: domain.length > 0,
        address: domain.length > 0 ? `${token}@${domain}` : null,
      });
    }

    // App polls for parsed candidates.
    if (path === "/pending" && request.method === "GET") {
      const token = url.searchParams.get("token") ?? "";
      if (!isValidToken(token)) return json({ error: "invalid token" }, 400);
      const res = await inbox(env, token, "pending", { method: "GET" });
      return json(await res.json());
    }

    // App acknowledges candidates it has imported.
    if (path === "/ack" && request.method === "POST") {
      const token = url.searchParams.get("token") ?? "";
      if (!isValidToken(token)) return json({ error: "invalid token" }, 400);
      const body = (await request.json().catch(() => ({}))) as { ids?: string[] };
      await inbox(env, token, "ack", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ ids: body.ids ?? [] }),
      });
      return json({ ok: true });
    }

    // Inbound email webhook from the mail provider.
    if (path === "/inbound" && request.method === "POST") {
      return handleInbound(request, env);
    }

    return json({ error: "not found" }, 404);
  },
} satisfies ExportedHandler<Env>;

/** Normalize the many inbound-email webhook shapes into one envelope. */
async function parseInbound(request: Request): Promise<{
  to: string;
  from: string;
  subject: string;
  text: string;
} | null> {
  const contentType = request.headers.get("content-type") ?? "";
  const pick = (obj: Record<string, unknown>, keys: string[]): string => {
    for (const k of keys) {
      const v = obj[k];
      if (typeof v === "string" && v.length > 0) return v;
    }
    return "";
  };

  if (contentType.includes("application/json")) {
    const body = (await request.json().catch(() => ({}))) as Record<string, unknown>;
    return {
      to: pick(body, ["to", "To", "recipient", "OriginalRecipient"]),
      from: pick(body, ["from", "From", "sender"]),
      subject: pick(body, ["subject", "Subject"]),
      text: pick(body, ["text", "TextBody", "body-plain", "plain", "html", "HtmlBody"]),
    };
  }

  // SendGrid Inbound Parse / Mailgun Routes post form data.
  if (contentType.includes("multipart/form-data") || contentType.includes("application/x-www-form-urlencoded")) {
    const form = await request.formData();
    const obj: Record<string, unknown> = {};
    for (const [k, v] of form.entries()) obj[k] = typeof v === "string" ? v : "";
    return {
      to: pick(obj, ["to", "recipient", "envelope"]),
      from: pick(obj, ["from", "sender"]),
      subject: pick(obj, ["subject"]),
      text: pick(obj, ["text", "body-plain", "stripped-text", "html", "body-html"]),
    };
  }

  return null;
}

/** Extract the forwarding token from an address string. */
function tokenFromAddress(raw: string): string | null {
  // Pull the first email out of e.g. `Diary <abc123@in.example.com>` or a JSON
  // envelope like `{"to":["abc123@in.example.com"]}`.
  const match = raw.match(/([a-zA-Z0-9._%+-]+)@[a-zA-Z0-9.-]+/);
  if (!match) return null;
  const local = match[1].toLowerCase().split("+")[0];
  return isValidToken(local) ? local : null;
}

async function handleInbound(request: Request, env: Env): Promise<Response> {
  const envelope = await parseInbound(request);
  if (!envelope) return json({ error: "unsupported payload" }, 415);

  const token = tokenFromAddress(envelope.to);
  if (!token) {
    console.warn("inbound: could not resolve token from recipient", envelope.to);
    return json({ ok: true, ignored: "no token" });
  }

  const candidate: DetectedCandidate | null = detectCandidate({
    subject: envelope.subject,
    from: envelope.from,
    text: envelope.text,
    receivedAt: new Date(),
  });

  if (!candidate) {
    console.log("inbound: no MLB matchup detected", { token, subject: envelope.subject });
    return json({ ok: true, detected: false });
  }

  await inbox(env, token, "add", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(candidate),
  });
  console.log("inbound: stored candidate", { token, team: candidate.teamMlbId });
  return json({ ok: true, detected: true });
}
