// Ticket-email parser — a TypeScript port of the iOS TicketEmailParser. Runs
// server-side on forwarded emails so the app never needs mailbox access.
//
// It scans a forwarded ticket receipt for an MLB matchup and likely game
// date(s). It is intentionally conservative: a candidate is only emitted when
// at least one team can be identified, so the app can confirm it against the
// real MLB schedule downstream.
//
// KEPT IN SYNC with ios/BallparkDiary/Services/TicketEmailParser.swift —
// every logic change must be applied to both files.

export interface DetectedCandidate {
  id: string;
  teamMlbId: number;
  opponentMlbId: number | null;
  /** ISO-8601 strings, newest/most-relevant first. */
  candidateDates: string[];
  source: string;
  subject: string;
  /** Seat location extracted from the ticket text, if any. */
  section: string;
  row: string;
  seat: string;
  /** Order / confirmation number found in the ticket, if any. */
  confirmation: string | null;
}

/** Detect a ticket candidate from a single forwarded email. */
export function detectCandidate(input: {
  subject: string;
  from: string;
  text: string;
  receivedAt: Date;
}): DetectedCandidate | null {
  const haystack = `${input.subject} ${input.text}`;
  const teams = matchedTeams(haystack);
  const primary = teams[0];
  if (primary === undefined) return null;

  // NEVER use input.receivedAt — only dates actually in the ticket text.
  const dates = dedupedByDay(extractDates(haystack));
  if (dates.length === 0) return null;

  const seats = extractSeatInfo(haystack);

  return {
    id: crypto.randomUUID(),
    teamMlbId: primary,
    opponentMlbId: teams.length > 1 ? teams[1] : null,
    candidateDates: dates.map((d) => d.toISOString()),
    source: sourceLabel(`${input.from} ${input.subject}`),
    subject: input.subject.trim().length > 0 ? input.subject.trim() : firstLine(input.text),
    section: seats.section,
    row: seats.row,
    seat: seats.seat,
    confirmation: seats.confirmation,
  };
}

function firstLine(text: string): string {
  const line = text.split(/\r?\n/).map((l) => l.trim()).find((l) => l.length > 0);
  return (line ?? "Forwarded ticket").slice(0, 140);
}

// MARK: - Team detection

/** Escape a string for use inside a RegExp literal. */
function escapeRegex(s: string): string {
  return s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

/**
 * Ordered, de-duplicated MLB team ids mentioned in the text.
 * Uses strict word-boundary (`\b`) matching — no substring fallback — so
 * "hundreds" won't match Reds, "helmets" won't match Mets, etc.
 */
function matchedTeams(text: string): number[] {
  const lower = text.toLowerCase().replace(/\s+/g, " ");
  const hits: { index: number; id: number }[] = [];

  for (const [keyword, id] of TEAM_KEYWORDS) {
    const escaped = escapeRegex(keyword);
    const regex = new RegExp(`\\b${escaped}\\b`, "i");
    const match = regex.exec(lower);
    if (match) {
      hits.push({ index: match.index, id });
    }
  }

  hits.sort((a, b) => a.index - b.index);
  const seen = new Set<number>();
  const result: number[] = [];
  for (const hit of hits) {
    if (seen.has(hit.id)) continue;
    seen.add(hit.id);
    result.push(hit.id);
  }
  return result;
}

// MARK: - Date detection

const MONTHS: Record<string, number> = {
  jan: 1, january: 1, feb: 2, february: 2, mar: 3, march: 3, apr: 4, april: 4,
  may: 5, jun: 6, june: 6, jul: 7, july: 7, aug: 8, august: 8, sep: 9, sept: 9,
  september: 9, oct: 10, october: 10, nov: 11, november: 11, dec: 12, december: 12,
};

/** Days in each month (non-leap). Used to validate bare numeric M/D. */
const DAYS_IN_MONTH = [0, 31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];

function extractDates(rawText: string): Date[] {
  // Strip seat/section/row ranges so "Seats 11-12" isn't parsed as Nov 12.
  const text = rawText.replace(
    /(?:Section|Sec|Sect|Row|Seats?|Seat)\s*[:-]?\s*\d+\s*[-/]\s*\d+/gi,
    "",
  );

  const now = Date.now();
  const horizon = now + 1000 * 60 * 60 * 24 * 2; // allow up to 2 days ahead

  interface DateHint {
    y: number;
    m: number;
    d: number;
    hasExplicitYear: boolean;
  }

  const found: DateHint[] = [];
  const seen = new Set<string>();

  const push = (y: number, m: number, d: number, hasExplicitYear: boolean) => {
    if (m < 1 || m > 12 || d < 1 || d > 31 || y < 1980 || y > 2100) return;
    // Validate calendar date
    if (d > (DAYS_IN_MONTH[m] ?? 31)) return;
    const key = `${y}-${m}-${d}`;
    if (seen.has(key)) return;
    seen.add(key);
    const dt = new Date(Date.UTC(y, m - 1, d, 19, 0, 0));
    if (dt.getTime() <= horizon) {
      found.push({ y, m, d, hasExplicitYear });
    }
  };

  // "Month DD, YYYY" / "Mon DD YYYY"
  const monthName = /\b([a-z]{3,9})\.?\s+(\d{1,2})(?:st|nd|rd|th)?,?\s+(\d{4})\b/gi;
  for (const m of text.matchAll(monthName)) {
    const month = MONTHS[m[1].toLowerCase()];
    if (month) push(Number(m[3]), month, Number(m[2]), true);
  }

  // "DD Month YYYY"
  const dayMonth = /\b(\d{1,2})(?:st|nd|rd|th)?\s+([a-z]{3,9})\.?,?\s+(\d{4})\b/gi;
  for (const m of text.matchAll(dayMonth)) {
    const month = MONTHS[m[2].toLowerCase()];
    if (month) push(Number(m[3]), month, Number(m[1]), true);
  }

  // "MM/DD/YYYY" or "MM-DD-YYYY"
  const numeric4 = /\b(\d{1,2})[/\-](\d{1,2})[/\-](\d{2,4})\b/g;
  for (const m of text.matchAll(numeric4)) {
    let year = Number(m[3]);
    if (year < 100) year += 2000;
    push(year, Number(m[1]), Number(m[2]), true);
  }

  // "YYYY-MM-DD"
  const iso = /\b(\d{4})-(\d{1,2})-(\d{1,2})\b/g;
  for (const m of text.matchAll(iso)) {
    push(Number(m[1]), Number(m[2]), Number(m[3]), true);
  }

  // Bare numeric "M/D" or "M-D" — only accepted when no better-qualified
  // date (with explicit year or spelled-out month) exists.
  const hasQualified = found.some((f) => f.hasExplicitYear);
  if (!hasQualified) {
    const thisYear = new Date().getUTCFullYear();
    const bareNumeric = /\b(\d{1,2})[/-](\d{1,2})\b/g;
    for (const m of text.matchAll(bareNumeric)) {
      const month = Number(m[1]);
      const day = Number(m[2]);
      if (month < 1 || month > 12 || day < 1 || day > 31) continue;
      if (day > (DAYS_IN_MONTH[month] ?? 31)) continue;
      // Try current year; if it's in the past, that's the most likely season.
      const dt = new Date(Date.UTC(thisYear, month - 1, day, 19, 0, 0));
      if (dt.getTime() <= now) {
        push(thisYear, month, day, false);
      } else {
        // Try previous year
        push(thisYear - 1, month, day, false);
      }
    }
  }

  return found.map((f) => new Date(Date.UTC(f.y, f.m - 1, f.d, 19, 0, 0)));
}

function dedupedByDay(dates: Date[]): Date[] {
  const seen = new Set<string>();
  const result: Date[] = [];
  for (const d of dates) {
    const key = `${d.getUTCFullYear()}-${d.getUTCMonth()}-${d.getUTCDate()}`;
    if (seen.has(key)) continue;
    seen.add(key);
    result.push(d);
  }
  return result;
}

// MARK: - Seat extraction

interface SeatInfo {
  section: string;
  row: string;
  seat: string;
  confirmation: string | null;
}

/** Pull seat location and confirmation number out of ticket text. */
function extractSeatInfo(text: string): SeatInfo {
  const trimPunct = (s: string): string =>
    s.trim().replace(/^[,\s.;|]+|[,\s.;|]+$/g, "");

  const first = (pattern: RegExp): string => {
    const m = text.match(pattern);
    return m?.[1] ? trimPunct(m[1]) : "";
  };

  // Section: "Section 123", "Sec 123", "Sect 123", "SEC 123"
  // Also area labels without "Section": FIELD BOX 42, GRANDSTAND 5, etc.
  let section = first(/\b(?:Section|Sec|Sect)\s*[:-]?\s*(\S+)/i);
  if (!section) {
    const areaMatch = text.match(
      /\b(FIELD\s*BOX|GRANDSTAND|BLEACHERS?|PAVILION|TERRACE|RESERVE|CLUB\s*LEVEL|UPPER\s*LEVEL|LOWER\s*LEVEL|MEZZANINE|LOGE|UPPER\s*RESERVE)\s*[:-]?\s*(\S+)/i,
    );
    if (areaMatch) {
      section = areaMatch[0].trim();
    }
  }

  const row = first(/\bRow\s*[:-]?\s*(\S+)/i);
  const seat = first(/\bSeats?\s*[:-]?\s*(\S+)/i);
  const confirmation = validatedConfirmation(text);

  return { section, row, seat, confirmation };
}

/**
 * Confirmation / order number extraction with validation:
 * - Must contain at least one digit
 * - 4–20 characters of [A-Za-z0-9-]
 * - Reject plain English words (Total, Summary, Date, Details, etc.)
 */
function validatedConfirmation(text: string): string | null {
  const pattern = /\b(?:Conf(?:irmation)?|Order)\s*(?:#|No\.?|Number:?)?\s*[:-]?\s*([A-Za-z0-9][A-Za-z0-9-]{3,19})\b/i;
  const m = text.match(pattern);
  if (!m?.[1]) return null;

  let raw = m[1].trim();
  raw = raw.replace(/^[,\s.;|]+|[,\s.;|]+$/g, "");

  // Must contain at least one digit
  if (!/\d/.test(raw)) return null;

  // Reject plain English words that appear in ticket headers
  const rejected = new Set([
    "total", "summary", "date", "details", "confirmation", "status", "number",
    "order", "ticket", "event", "section", "row", "seat", "price", "subtotal",
    "tax", "fee", "delivery", "payment", "receipt", "amount", "charge",
  ]);
  if (rejected.has(raw.toLowerCase())) return null;

  return raw;
}

// MARK: - Source detection

const SOURCE_LABELS: [string, string][] = [
  ["ticketmaster", "Ticketmaster"], ["seatgeek", "SeatGeek"], ["stubhub", "StubHub"],
  ["axs", "AXS"], ["vividseats", "Vivid Seats"], ["vivid seats", "Vivid Seats"],
  ["gametime", "Gametime"], ["tickpick", "TickPick"], ["ballpark", "MLB Ballpark"],
  ["mlb.com", "MLB.com"], ["tickets.com", "Tickets.com"],
];

function sourceLabel(blob: string): string {
  const lower = blob.toLowerCase();
  for (const [needle, label] of SOURCE_LABELS) {
    if (lower.includes(needle)) return label;
  }
  return "Forwarded email";
}

// MARK: - Keyword → MLB Stats API team id

const TEAM_KEYWORDS: [string, number][] = [
  ["diamondbacks", 109], ["d-backs", 109], ["dbacks", 109], ["arizona", 109],
  ["braves", 144], ["atlanta", 144],
  ["orioles", 110], ["baltimore", 110], ["camden", 110],
  ["red sox", 111], ["redsox", 111], ["fenway", 111], ["boston", 111],
  ["cubs", 112], ["wrigley", 112],
  ["white sox", 145], ["whitesox", 145],
  ["reds", 113], ["cincinnati", 113],
  ["guardians", 114], ["cleveland", 114], ["progressive field", 114],
  ["rockies", 115], ["colorado", 115], ["coors", 115],
  ["tigers", 116], ["detroit", 116], ["comerica", 116],
  ["astros", 117], ["houston", 117], ["minute maid", 117], ["daikin park", 117],
  ["royals", 118], ["kansas city", 118], ["kauffman", 118],
  ["angels", 108], ["anaheim", 108],
  ["dodgers", 119], ["chavez ravine", 119],
  ["marlins", 146], ["loandepot", 146],
  ["brewers", 158], ["milwaukee", 158],
  ["twins", 142], ["minnesota", 142], ["target field", 142],
  ["mets", 121], ["citi field", 121],
  ["yankees", 147], ["yankee stadium", 147], ["bronx bombers", 147],
  ["athletics", 133], ["oakland", 133],
  ["phillies", 143], ["philadelphia", 143], ["citizens bank", 143],
  ["pirates", 134], ["pittsburgh", 134], ["pnc park", 134],
  ["padres", 135], ["petco", 135], ["san diego", 135],
  ["giants", 137], ["oracle park", 137], ["san francisco", 137],
  ["mariners", 136], ["seattle", 136], ["t-mobile park", 136],
  ["cardinals", 138], ["st. louis", 138], ["st louis", 138], ["busch stadium", 138],
  ["rays", 139], ["tampa", 139], ["tropicana", 139],
  ["rangers", 140], ["globe life", 140], ["arlington", 140],
  ["blue jays", 141], ["bluejays", 141], ["toronto", 141], ["rogers centre", 141],
  ["nationals", 120], ["washington", 120],
];
