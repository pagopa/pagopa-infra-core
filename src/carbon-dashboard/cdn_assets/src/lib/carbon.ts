import type {
  CarbonMonthlyRecord,
  CarbonReport,
  Manifest,
  ManifestSeries,
} from '../types';

/** One month, after derivation. `usage` is dimensionless-by-construction. */
export interface MonthPoint {
  date: string;
  emissions: number;
  intensity: number;
  /**
   * Cloud usage hours, derived as `emissions / intensity`.
   *
   * The REST reference only says "per unit of normalized usage", but the Azure
   * emissions terminology page defines the denominator: the company's cloud
   * usage hours, summing compute, storage and data transfer — and warns they
   * need not match billed usage. So the quantity has a name, but its absolute
   * value still says nothing about platform traffic; only ratios are published.
   */
  usage: number;
  /** Day this month was last refreshed from Azure, when the data says so. */
  retrievedAt?: string;
}

export interface ChartPoint extends MonthPoint {
  emissionsIndex: number;
  usageIndex: number;
  intensityIndex: number;
  /** Emissions had intensity stayed at the baseline month's level. */
  counterfactual: number;
}

/** Length of the comparison window: last month against the same month a year earlier. */
export const WINDOW_MONTHS = 12;

export interface Metrics {
  /** The whole published history, indexed against `base`. */
  points: ChartPoint[];
  /** `points` from `base` to `last`: the comparison window. */
  windowPoints: ChartPoint[];
  /** Oldest month in the history. */
  seriesStart: MonthPoint;
  /**
   * Reference month (base 100): the same month a year before `last`. When the
   * history does not reach that far, or that month is missing, the oldest month
   * after it — and `yearOverYear` is false.
   */
  base: MonthPoint;
  last: MonthPoint;
  yearOverYear: boolean;
  /** Months summed in `totalEmissions`: the 12 months ending at `last`. */
  periodMonths: number;
  periodStart: MonthPoint;
  totalEmissions: number;
  counterfactualTotal: number;
  /** Actual minus counterfactual: positive when actual emissions exceed the scenario. */
  counterfactualGap: number;
  counterfactualGapRatio: number;
  /** Ratios over the window, base month → last month. */
  emissionsChange: number;
  usageChange: number;
  intensityChange: number;
  /** Months between first and last with no usable record, as YYYY-MM-01. */
  missingMonths: string[];
}

const isFiniteNumber = (v: unknown): v is number =>
  typeof v === 'number' && Number.isFinite(v);

/**
 * Parse one raw report into a clean, sorted, de-duplicated month series.
 * Records that cannot yield a usable point are dropped rather than rendered as
 * zeroes — a missing month should look missing, not look like a good month.
 */
export function parseReport(report: CarbonReport | null | undefined): MonthPoint[] {
  const records: CarbonMonthlyRecord[] = Array.isArray(report?.value) ? report!.value : [];
  const byDate = new Map<string, MonthPoint>();

  for (const r of records) {
    if (r?.dataType !== 'MonthlySummaryData') continue;
    if (typeof r.date !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(r.date)) continue;
    if (!isFiniteNumber(r.latestMonthEmissions) || !isFiniteNumber(r.carbonIntensity)) continue;
    // A zero or negative intensity would make the derived usage explode.
    if (r.carbonIntensity <= 0 || r.latestMonthEmissions < 0) continue;

    byDate.set(r.date, {
      date: r.date,
      emissions: r.latestMonthEmissions,
      intensity: r.carbonIntensity,
      usage: r.latestMonthEmissions / r.carbonIntensity,
      ...(typeof r.retrievedAt === 'string' ? { retrievedAt: r.retrievedAt } : {}),
    });
  }

  return [...byDate.values()].sort((a, b) => a.date.localeCompare(b.date));
}

/** Index a value against a baseline, guarding the degenerate baseline. */
const index = (value: number, base: number): number => (base > 0 ? (value / base) * 100 : 100);

/** Relative change as a ratio; flat when the baseline cannot support one. */
const change = (from: number, to: number): number => (from > 0 ? to / from - 1 : 0);

const addMonths = (iso: string, months: number): string => {
  const [y, m] = iso.split('-').map(Number);
  const total = y * 12 + (m - 1) + months;
  return `${Math.floor(total / 12)}-${String((total % 12) + 1).padStart(2, '0')}-01`;
};

const nextMonth = (iso: string): string => addMonths(iso, 1);

/**
 * Calendar months absent from the series. The charts use a category axis, so a
 * hole would otherwise be drawn as two adjacent months.
 */
export function findMissingMonths(points: MonthPoint[]): string[] {
  const present = new Set(points.map((p) => p.date));
  const missing: string[] = [];
  for (let i = 1; i < points.length; i++) {
    for (let d = nextMonth(points[i - 1].date); d < points[i].date; d = nextMonth(d)) {
      if (!present.has(d)) missing.push(d);
    }
  }
  return missing;
}

export function computeMetrics(points: MonthPoint[]): Metrics | null {
  if (points.length === 0) return null;

  const last = points[points.length - 1];
  const target = addMonths(last.date, -WINDOW_MONTHS);
  // Always found: `last` itself satisfies the predicate.
  const base = points.find((p) => p.date >= target)!;
  const baselineIntensity = base.intensity;

  const chartPoints: ChartPoint[] = points.map((p) => ({
    ...p,
    emissionsIndex: index(p.emissions, base.emissions),
    usageIndex: index(p.usage, base.usage),
    intensityIndex: index(p.intensity, baselineIntensity),
    counterfactual: p.usage * baselineIntensity,
  }));
  const windowPoints = chartPoints.filter((p) => p.date >= base.date);
  // The base month closes the previous year, so it is not summed — unless the
  // history is too short to have one.
  const period = chartPoints.filter((p) => p.date > target);

  const totalEmissions = period.reduce((sum, p) => sum + p.emissions, 0);
  const counterfactualTotal = period.reduce((sum, p) => sum + p.counterfactual, 0);
  const counterfactualGap = totalEmissions - counterfactualTotal;

  return {
    points: chartPoints,
    windowPoints,
    seriesStart: points[0],
    base,
    last,
    yearOverYear: base.date === target,
    periodMonths: period.length,
    periodStart: period[0],
    totalEmissions,
    counterfactualTotal,
    counterfactualGap,
    counterfactualGapRatio: counterfactualTotal > 0 ? counterfactualGap / counterfactualTotal : 0,
    emissionsChange: change(base.emissions, last.emissions),
    usageChange: change(base.usage, last.usage),
    intensityChange: change(base.intensity, last.intensity),
    missingMonths: findMissingMonths(points),
  };
}

// --- loading ---------------------------------------------------------------
// Relative URLs throughout: the site and its data share an origin, which is
// what keeps CORS and SAS tokens out of this codebase entirely.

const DATA_ROOT = 'data/';

async function fetchJson<T>(path: string): Promise<T> {
  const res = await fetch(`${DATA_ROOT}${path}`, { cache: 'no-cache' });
  if (!res.ok) throw new Error(`${path}: HTTP ${res.status}`);
  return (await res.json()) as T;
}

export async function loadManifest(): Promise<Manifest> {
  // `subscriptions` is the field's former name: still read, so a manifest
  // written before the rename keeps working until the next data refresh.
  const raw = await fetchJson<Manifest & { subscriptions?: ManifestSeries[] }>('index.json');
  return { ...raw, series: raw.series ?? raw.subscriptions ?? [] };
}

export async function loadSeries(
  series: ManifestSeries[],
): Promise<Record<string, MonthPoint[]>> {
  const entries = await Promise.all(
    series.map(async (s) => {
      try {
        return [s.slug, parseReport(await fetchJson<CarbonReport>(s.file))] as const;
      } catch {
        // One unreachable series must not blank the whole dashboard.
        return [s.slug, [] as MonthPoint[]] as const;
      }
    }),
  );
  return Object.fromEntries(entries);
}
