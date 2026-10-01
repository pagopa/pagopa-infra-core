const LOCALE = 'it-IT';

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
  return `${label.replace('.', '')} ${y}`;
}

/** "luglio 2025" */
export function formatMonthLong(iso: string): string {
  const [y, m] = iso.split('-');
  const label = new Date(Number(y), Number(m) - 1, 1).toLocaleDateString(LOCALE, {
    month: 'long',
  });
  return `${label} ${y}`;
}

/**
 * Mass with the unit that keeps the number readable. The API speaks kilograms;
 * above a tonne we say tonnes, because "8697 kg" reads as noise (README §1.2).
 */
export function formatMass(kg: number): string {
  if (!Number.isFinite(kg)) return '—';
  const abs = Math.abs(kg);
  if (abs >= 1000) return `${one.format(kg / 1000)} t`;
  if (abs >= 100) return `${int.format(kg)} kg`;
  return `${one.format(kg)} kg`;
}

/** Unit-suffixed value for axis ticks, where space is tight. */
export function formatMassCompact(kg: number): string {
  if (!Number.isFinite(kg)) return '';
  return Math.abs(kg) >= 1000 ? `${one.format(kg / 1000)} t` : `${int.format(kg)}`;
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

export function formatCount(value: number): string {
  if (!Number.isFinite(value)) return '—';
  return value >= 1000 ? int.format(Math.round(value)) : one.format(value);
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
