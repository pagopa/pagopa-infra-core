import type {
  CarbonMonthlyRecord,
  CarbonReport,
  Manifest,
  ManifestSubscription,
} from '../types';

export const ALL_SUBSCRIPTIONS = '__all__';

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
   * value still says nothing about platform traffic; only ratios are published
   * (README §1.3).
   */
  usage: number;
}

export interface ChartPoint extends MonthPoint {
  emissionsIndex: number;
  usageIndex: number;
  intensityIndex: number;
  /** Emissions had intensity stayed at the baseline month's level. */
  counterfactual: number;
}

export interface Metrics {
  points: ChartPoint[];
  first: MonthPoint;
  last: MonthPoint;
  totalEmissions: number;
  counterfactualTotal: number;
  avoided: number;
  avoidedRatio: number;
  /** Ratios over the whole window, first month → last month. */
  emissionsChange: number;
  usageChange: number;
  intensityChange: number;
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
    });
  }

  return [...byDate.values()].sort((a, b) => a.date.localeCompare(b.date));
}

/**
 * Combine several subscriptions into one series.
 *
 * Emissions and usage are summed; intensity is recomputed as
 * `totalEmissions / totalUsage`. Averaging intensities would simply be wrong.
 *
 * Only months present in *every* series are kept, so a subscription with a
 * shorter history can never make a month look artificially low.
 */
export function aggregate(series: MonthPoint[][]): MonthPoint[] {
  const nonEmpty = series.filter((s) => s.length > 0);
  if (nonEmpty.length === 0) return [];
  if (nonEmpty.length === 1) return nonEmpty[0];

  const [head, ...rest] = nonEmpty;
  const sharedDates = head
    .map((p) => p.date)
    .filter((date) => rest.every((s) => s.some((p) => p.date === date)));

  return sharedDates.map((date) => {
    let emissions = 0;
    let usage = 0;
    for (const s of nonEmpty) {
      const point = s.find((p) => p.date === date)!;
      emissions += point.emissions;
      usage += point.usage;
    }
    return { date, emissions, usage, intensity: usage > 0 ? emissions / usage : 0 };
  });
}

/** Index a value against a baseline, guarding the degenerate baseline. */
const index = (value: number, base: number): number => (base > 0 ? (value / base) * 100 : 100);

/** Relative change as a ratio; flat when the baseline cannot support one. */
const change = (from: number, to: number): number => (from > 0 ? to / from - 1 : 0);

export function computeMetrics(points: MonthPoint[]): Metrics | null {
  if (points.length === 0) return null;

  const first = points[0];
  const last = points[points.length - 1];
  const baselineIntensity = first.intensity;

  const chartPoints: ChartPoint[] = points.map((p) => ({
    ...p,
    emissionsIndex: index(p.emissions, first.emissions),
    usageIndex: index(p.usage, first.usage),
    intensityIndex: index(p.intensity, baselineIntensity),
    counterfactual: p.usage * baselineIntensity,
  }));

  const totalEmissions = points.reduce((sum, p) => sum + p.emissions, 0);
  const counterfactualTotal = chartPoints.reduce((sum, p) => sum + p.counterfactual, 0);
  const avoided = counterfactualTotal - totalEmissions;

  return {
    points: chartPoints,
    first,
    last,
    totalEmissions,
    counterfactualTotal,
    avoided,
    avoidedRatio: counterfactualTotal > 0 ? avoided / counterfactualTotal : 0,
    emissionsChange: change(first.emissions, last.emissions),
    usageChange: change(first.usage, last.usage),
    intensityChange: change(first.intensity, last.intensity),
  };
}

// --- loading ---------------------------------------------------------------
// Relative URLs throughout: the site and its data share an origin, which is
// what keeps CORS and SAS tokens out of this codebase entirely (README §2.1).

const DATA_ROOT = 'data/';

async function fetchJson<T>(path: string): Promise<T> {
  const res = await fetch(`${DATA_ROOT}${path}`, { cache: 'no-cache' });
  if (!res.ok) throw new Error(`${path}: HTTP ${res.status}`);
  return (await res.json()) as T;
}

export const loadManifest = (): Promise<Manifest> => fetchJson<Manifest>('index.json');

export async function loadSeries(
  subscriptions: ManifestSubscription[],
): Promise<Record<string, MonthPoint[]>> {
  const entries = await Promise.all(
    subscriptions.map(async (sub) => {
      try {
        return [sub.slug, parseReport(await fetchJson<CarbonReport>(sub.file))] as const;
      } catch {
        // One unreachable subscription must not blank the whole dashboard.
        return [sub.slug, [] as MonthPoint[]] as const;
      }
    }),
  );
  return Object.fromEntries(entries);
}
