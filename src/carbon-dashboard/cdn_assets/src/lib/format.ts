const LOCALE = 'it-IT';

/** Month and year never wrap apart: "agosto 2025" stays on one line. */
const NBSP = '\u00a0';

const decimal = (min: number, max: number) =>
  new Intl.NumberFormat(LOCALE, { minimumFractionDigits: min, maximumFractionDigits: max });

const int = decimal(0, 0);
const one = decimal(1, 1);
const two = decimal(2, 2);

/** "lug 2025" */
export function formatMonth(iso: string): string {
  const [y, m] = iso.split('-');
  const label = new Date(Number(y), Number(m) - 1, 1).toLocaleDateString(LOCALE, {
    month: 'short',
  });
  return `${label.replace('.', '')}${NBSP}${y}`;
}

/** "luglio 2025" */
export function formatMonthLong(iso: string): string {
  const [y, m] = iso.split('-');
  const label = new Date(Number(y), Number(m) - 1, 1).toLocaleDateString(LOCALE, {
    month: 'long',
  });
  return `${label}${NBSP}${y}`;
}

/** The preposition "a", euphonic before a vowel: "ad agosto 2025", "a luglio 2025". */
export function toMonth(label: string): string {
  return `${/^a/i.test(label) ? 'ad' : 'a'} ${label}`;
}

/**
 * What the reference month is, for captions: "agosto 2025 (stesso mese
 * dell'anno precedente)". Falls back honestly when the history is shorter.
 */
export function formatBase(iso: string, yearOverYear: boolean): string {
  return `${formatMonthLong(iso)} (${yearOverYear ? 'stesso mese dell’anno precedente' : 'primo mese disponibile'})`;
}

/**
 * Mass with the unit that keeps the number readable. The API speaks kilograms;
 * above a tonne we say tonnes, because "8697 kg" reads as noise.
 */
export function formatMass(kg: number): string {
  if (!Number.isFinite(kg)) return '—';
  const abs = Math.abs(kg);
  if (abs >= 1000) return `${one.format(kg / 1000)} t`;
  if (abs >= 100) return `${int.format(kg)} kg`;
  return `${one.format(kg)} kg`;
}

/**
 * Axis ticks, always in kilograms: one unit per axis, named in the chart title.
 * Switching to tonnes above 1000 mixed "750" and "1,0 t" on the same axis.
 */
export function formatMassCompact(kg: number): string {
  return Number.isFinite(kg) ? int.format(kg) : '';
}

/** Tooltip values, in kilograms like the axis they sit on: "1.234 kg". */
export function formatKg(kg: number): string {
  return Number.isFinite(kg) ? `${int.format(kg)} kg` : '—';
}

/** Signed percentage from a ratio: 0.413 → "+41,3%". */
export function formatPercent(ratio: number, signed = true): string {
  if (!Number.isFinite(ratio)) return '—';
  const pct = ratio * 100;
  const sign = signed && pct > 0 ? '+' : '';
  return `${sign}${one.format(pct)}%`;
}

/** Index points, baseline 100. */
export function formatIndex(value: number): string {
  return Number.isFinite(value) ? one.format(value) : '—';
}

export function formatIntensity(value: number): string {
  return Number.isFinite(value) ? two.format(value * 1000) : '—';
}

export function formatDateTime(iso: string): string {
  const d = new Date(iso);
  return Number.isNaN(d.getTime())
    ? '—'
    : d.toLocaleDateString(LOCALE, { day: 'numeric', month: 'long', year: 'numeric' });
}
