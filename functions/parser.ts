// Ticket-email parser — a TypeScript port of the iOS TicketEmailParser. Runs
// server-side on forwarded emails so the app never needs mailbox access.
//
// It scans a forwarded ticket receipt for an MLB matchup and likely game
// date(s). It is intentionally conservative: a candidate is only emitted when
// at least one team can be identified, so the app can confirm it against the
// real MLB schedule downstream.

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

  const dates = dedupedByDay([...extractDates(haystack), input.receivedAt]);
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

/** Ordered, de-duplicated MLB team ids mentioned in the text. */
function matchedTeams(text: string): number[] {
  const lower = ` ${text.toLowerCase().replace(/\s+/g, " ")} `;
  const hits: { index: number; id: number }[] = [];
  for (const [keyword, id] of TEAM_KEYWORDS) {
    const padded = lower.indexOf(` ${keyword} `);
    if (padded >= 0) {
      hits.push({ index: padded, id });
      continue;
    }
    const loose = lower.indexOf(keyword);
    if (loose >= 0) hits.push({ index: loose, id });
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

function extractDates(text: string): Date[] {
  const now = Date.now();
  const horizon = now + 1000 * 60 * 60 * 24 * 2; // allow up to 2 days ahead
  const found: Date[] = [];
  const push = (y: number, m: number, d: number) => {
    if (m < 1 || m > 12 || d < 1 || d > 31 || y < 1980 || y > 2100) return;
    const dt = new Date(Date.UTC(y, m - 1, d, 19, 0, 0)); // ~game time, UTC-ish
    if (dt.getTime() <= horizon) found.push(dt);
  };

  // "Month DD, YYYY" / "Mon DD YYYY"
  const monthName = /\b([a-z]{3,9})\.?\s+(\d{1,2})(?:st|nd|rd|th)?,?\s+(\d{4})\b/gi;
  for (const m of text.matchAll(monthName)) {
    const month = MONTHS[m[1].toLowerCase()];
    if (month) push(Number(m[3]), month, Number(m[2]));
  }

  // "DD Month YYYY"
  const dayMonth = /\b(\d{1,2})(?:st|nd|rd|th)?\s+([a-z]{3,9})\.?,?\s+(\d{4})\b/gi;
  for (const m of text.matchAll(dayMonth)) {
    const month = MONTHS[m[2].toLowerCase()];
    if (month) push(Number(m[3]), month, Number(m[1]));
  }

  // "MM/DD/YYYY" or "MM-DD-YYYY"
  const numeric = /\b(\d{1,2})[/\-](\d{1,2})[/\-](\d{2,4})\b/g;
  for (const m of text.matchAll(numeric)) {
    let year = Number(m[3]);
    if (year < 100) year += 2000;
    push(year, Number(m[1]), Number(m[2]));
  }

  // "YYYY-MM-DD"
  const iso = /\b(\d{4})-(\d{1,2})-(\d{1,2})\b/g;
  for (const m of text.matchAll(iso)) {
    push(Number(m[1]), Number(m[2]), Number(m[3]));
  }

  return found;
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
  const first = (pattern: RegExp): string => {
    const m = text.match(pattern);
    return m?.[1]?.trim() ?? "";
  };

  const section = first(/\b(?:Section|Sec|Sect)\s*[:-]?\s*(\S+)/i);
  const row = first(/\bRow\s*[:-]?\s*(\S+)/i);
  const seat = first(/\bSeats?\s*[:-]?\s*(\S+)/i);
  const confirmation = first(/\b(?:Conf(?:irmation)?|Order)\s*(?:#|No\.?|Number:?)?\s*[:-]?\s*([A-Za-z0-9][A-Za-z0-9-]{2,20})/i) || null;

  return { section, row, seat, confirmation };
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
