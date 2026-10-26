

export function localCalendarDate(instant: Date, timeZoneId: string): string {
  if (!Number.isFinite(instant.getTime()) || !timeZoneId.trim()) {
    throw new RangeError("Invalid date or time zone.");
  }
  let parts: Intl.DateTimeFormatPart[];
  try {
    parts = new Intl.DateTimeFormat("en-US", {
      timeZone: timeZoneId,
      year: "numeric",
      month: "2-digit",
      day: "2-digit",
    }).formatToParts(instant);
  } catch {
    throw new RangeError("Invalid source time zone.");
  }
  const field = (name: string) =>
    parts.find((part) => part.type === name)?.value;
  return `${field("year")}-${field("month")}-${field("day")}`;
}

export function centerDateStatus(validFrom: string, validUntil: string,
  localDate: string): "upcoming" | "date-listed" | "expired" {
  if (!validDay(validFrom) || !validDay(validUntil) ||
    !validDay(localDate) || validFrom > validUntil) {
    throw new RangeError("Invalid cooling-center date range.");
  }
  if (localDate < validFrom) return "upcoming";
  if (localDate > validUntil) return "expired";
  return "date-listed";
}

function validDay(value: string): boolean {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(value)) return false;
  const date = new Date(`${value}T00:00:00Z`);
  return Number.isFinite(date.getTime()) &&
    date.toISOString().slice(0, 10) === value;
}
