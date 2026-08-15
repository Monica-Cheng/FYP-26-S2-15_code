export function normalizeWeekLabel(value: string) {
  const trimmed = value.trim();
  if (!trimmed) return "";

  const compact = trimmed.replace(/\s+/g, "").toUpperCase();
  const weekMatch = compact.match(/^WEEK(\d+)$/);

  if (weekMatch) {
    return `WEEK ${Number(weekMatch[1])}`;
  }

  return trimmed.replace(/\s+/g, " ").toUpperCase();
}

