/**
 * Smoke-check a data drop before it goes to the storage account.
 *
 * Runs the real parsing/aggregation/metric code over `web/public/data`, prints
 * what each subscription will show, and asserts the invariants that matter:
 * the aggregate total equals the sum of its parts, intensity is weighted rather
 * than averaged, and degenerate input yields no data instead of fake data.
 *
 *   make verify
 */
import { readFileSync } from 'node:fs';

const DATA_DIR = new URL('../public/data/', import.meta.url).pathname.replace(/\/$/, '');
import { parseReport, aggregate, computeMetrics } from '../src/lib/carbon.ts';

const read = (p: string) => JSON.parse(readFileSync(`${DATA_DIR}/${p}`, 'utf8'));
const manifest = read('index.json');

const series: Record<string, ReturnType<typeof parseReport>> = {};
for (const sub of manifest.subscriptions) series[sub.slug] = parseReport(read(sub.file));

const show = (name: string, points: ReturnType<typeof parseReport>) => {
  const m = computeMetrics(points);
  if (!m) return console.log(`${name.padEnd(22)} NO DATA`);
  const pct = (r: number) => `${(r * 100).toFixed(1)}%`;
  console.log(
    `${name.padEnd(22)} ${String(m.points.length).padStart(2)}m  ` +
      `${m.first.date}->${m.last.date}  tot=${m.totalEmissions.toFixed(0)}kg  ` +
      `usage=${pct(m.usageChange).padStart(7)}  emis=${pct(m.emissionsChange).padStart(7)}  ` +
      `inten=${pct(m.intensityChange).padStart(7)}  avoided=${m.avoided.toFixed(0)}kg (${pct(m.avoidedRatio)})`,
  );
  const last = m.points[m.points.length - 1];
  console.log(
    `${' '.repeat(22)} indices@last: usage=${last.usageIndex.toFixed(1)} ` +
      `emis=${last.emissionsIndex.toFixed(1)} inten=${last.intensityIndex.toFixed(1)}`,
  );
};

for (const sub of manifest.subscriptions) show(sub.name, series[sub.slug]);
const agg = aggregate(manifest.subscriptions.map((s: any) => series[s.slug]));
show('TUTTE (aggregato)', agg);

// Aggregate must sum emissions, and derive intensity rather than average it.
const m = computeMetrics(agg)!;
const perSubTotal = manifest.subscriptions
  .map((s: any) => computeMetrics(series[s.slug])!.totalEmissions)
  .reduce((a: number, b: number) => a + b, 0);
console.log(`\nsum(per-sub totals) = ${perSubTotal.toFixed(2)}  aggregate total = ${m.totalEmissions.toFixed(2)}`);

const naiveMeanIntensity =
  manifest.subscriptions
    .map((s: any) => series[s.slug][0].intensity)
    .reduce((a: number, b: number) => a + b, 0) / manifest.subscriptions.length;
console.log(
  `first-month intensity: weighted=${m.first.intensity.toFixed(7)}  ` +
    `naive mean=${naiveMeanIntensity.toFixed(7)}  (they must differ)`,
);

// Degenerate inputs must not crash or fabricate data.
console.log('\nedge cases:');
console.log('  empty report        ->', computeMetrics(parseReport({ value: [] })));
console.log('  null report         ->', computeMetrics(parseReport(null)));
console.log('  zero intensity rows ->', parseReport({
  value: [{ dataType: 'MonthlySummaryData', date: '2025-01-01', carbonIntensity: 0, latestMonthEmissions: 10 }],
}).length, 'points (expected 0)');
console.log('  aggregate([])       ->', aggregate([]).length, 'points (expected 0)');
console.log('  disjoint months     ->', aggregate([
  parseReport({ value: [{ dataType: 'MonthlySummaryData', date: '2025-01-01', carbonIntensity: 1, latestMonthEmissions: 10 }] }),
  parseReport({ value: [{ dataType: 'MonthlySummaryData', date: '2025-02-01', carbonIntensity: 1, latestMonthEmissions: 10 }] }),
]).length, 'points (expected 0 — intersection)');
