// ForwardInbox — one Durable Object per user forwarding token. Stores the
// ticket candidates parsed from emails forwarded to that token's address until
// the app fetches and acknowledges them.

import { DurableObject } from "cloudflare:workers";
import type { DetectedCandidate } from "./parser";

interface StoredRow {
  id: string;
  team_mlb_id: number;
  opponent_mlb_id: number | null;
  candidate_dates: string;
  source: string;
  subject: string;
  section: string;
  row: string;
  seat: string;
  confirmation: string | null;
  received_at: number;
  acked: number;
}

export class ForwardInbox extends DurableObject {
  constructor(ctx: DurableObjectState, env: unknown) {
    super(ctx, env);
    this.ctx.storage.sql.exec(`
      CREATE TABLE IF NOT EXISTS candidates (
        id TEXT PRIMARY KEY,
        team_mlb_id INTEGER NOT NULL,
        opponent_mlb_id INTEGER,
        candidate_dates TEXT NOT NULL,
        source TEXT NOT NULL,
        subject TEXT NOT NULL,
        section TEXT NOT NULL DEFAULT '',
        row TEXT NOT NULL DEFAULT '',
        seat TEXT NOT NULL DEFAULT '',
        confirmation TEXT,
        received_at INTEGER NOT NULL,
        acked INTEGER NOT NULL DEFAULT 0
      )
    `);
  }

  override async fetch(request: Request): Promise<Response> {
    const url = new URL(request.url);
    const path = url.pathname;

    if (path === "/add" && request.method === "POST") {
      const candidate = (await request.json()) as DetectedCandidate;
      this.add(candidate);
      return Response.json({ ok: true });
    }

    if (path === "/pending" && request.method === "GET") {
      return Response.json({ candidates: this.pending() });
    }

    if (path === "/ack" && request.method === "POST") {
      const body = (await request.json()) as { ids: string[] };
      this.ack(body.ids ?? []);
      return Response.json({ ok: true });
    }

    return new Response("not found", { status: 404 });
  }

  private add(candidate: DetectedCandidate): void {
    this.ctx.storage.sql.exec(
      `INSERT OR REPLACE INTO candidates
       (id, team_mlb_id, opponent_mlb_id, candidate_dates, source, subject, section, row, seat, confirmation, received_at, acked)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0)`,
      candidate.id,
      candidate.teamMlbId,
      candidate.opponentMlbId,
      JSON.stringify(candidate.candidateDates),
      candidate.source,
      candidate.subject,
      candidate.section ?? "",
      candidate.row ?? "",
      candidate.seat ?? "",
      candidate.confirmation ?? null,
      Date.now(),
    );
  }

  private pending(): DetectedCandidate[] {
    return this.ctx.storage.sql
      .exec<StoredRow>(
        "SELECT * FROM candidates WHERE acked = 0 ORDER BY received_at DESC LIMIT 200",
      )
      .toArray()
      .map((r) => ({
        id: r.id,
        teamMlbId: r.team_mlb_id,
        opponentMlbId: r.opponent_mlb_id,
        candidateDates: JSON.parse(r.candidate_dates) as string[],
        source: r.source,
        subject: r.subject,
        section: r.section ?? "",
        row: r.row ?? "",
        seat: r.seat ?? "",
        confirmation: r.confirmation ?? null,
      }));
  }

  private ack(ids: string[]): void {
    for (const id of ids) {
      this.ctx.storage.sql.exec("UPDATE candidates SET acked = 1 WHERE id = ?", id);
    }
  }
}
