/**
 * Smoke-check a data drop before it goes to the storage account.
 *
 * Runs the real parsing/metric code over `public/data`, prints what each
 * subscription will show, and asserts the invariants that matter: the total is
 * the sum of the monthly emissions, usage is emissions / intensity, and
 * degenerate input yields no data instead of fake data.
 * Exits non-zero on the first broken invariant.
 *
 *   npm run verify        (Node >= 22.6)
 */
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

import { parseReport, computeMetrics, findMissingMonths, type MonthPoint } from '../src/lib/carbon.ts';
import type { Manifest } from '../src/types.ts';

const DATA_DIR = fileURLToPath(new URL('../public/data/', import.meta.url));

const read = <T,>(p: string): T => JSON.parse(readFileSync(`${DATA_DIR}${p}`, 'utf8')) as T;
const manifest = read<Manifest>('index.json');
assert.ok(manifest.series?.length > 0, 'index.json lists no series');

const series: Record<string, MonthPoint[]> = {};
for (const sub of manifest.series) {
  series[sub.slug] = parseReport(read(sub.file));
  assert.ok(series[sub.slug].length > 0, `${sub.file}: no usable monthly records`);
}

const pct = (r: number) => `${(r * 100).toFixed(1)}%`;

const show = (name: string, points: MonthPoint[]) => {
  const m = computeMetrics(points);
  if (!m) return console.log(`${name.padEnd(22)} NO DATA`);
  console.log(
    `${name.padEnd(22)} ${String(m.points.length).padStart(2)}m  ` +
      `${m.base.date}->${m.last.date}${m.yearOverYear ? '' : ' (no yoy)'}  tot${m.periodMonths}m=${m.totalEmissions.toFixed(0)}kg  ` +
      `usage=${pct(m.usageChange).padStart(7)}  emis=${pct(m.emissionsChange).padStart(7)}  ` +
      `inten=${pct(m.intensityChange).padStart(7)}  gap=${m.counterfactualGap.toFixed(0)}kg (${pct(m.counterfactualGapRatio)})`,
  );
  const last = m.points[m.points.length - 1];
  console.log(
    `${' '.repeat(22)} indices@last: usage=${last.usageIndex.toFixed(1)} ` +
      `emis=${last.emissionsIndex.toFixed(1)} inten=${last.intensityIndex.toFixed(1)}`,
  );
};

for (const sub of manifest.series) {
  const points = series[sub.slug];
  show(sub.name, points);
  const m = computeMetrics(points)!;

  const sum = m.points.filter((p) => p.date >= m.periodStart.date).reduce((acc, p) => acc + p.emissions, 0);
  assert.ok(Math.abs(sum - m.totalEmissions) < 1e-9 * Math.max(1, sum), `${sub.slug}: total != sum of the period's months`);
  assert.ok(m.periodMonths <= 12, `${sub.slug}: period longer than 12 months`);

  for (const p of points) {
    assert.ok(Math.abs(p.usage * p.intensity - p.emissions) < 1e-9 * Math.max(1, p.emissions), `${sub.slug} ${p.date}: usage * intensity != emissions`);
  }
  assert.ok(
    points.every((p, i) => i === 0 || points[i - 1].date < p.date),
    `${sub.slug}: months are not strictly increasing`,
  );
  if (m.missingMonths.length > 0) console.warn(`${' '.repeat(22)} WARN missing months: ${m.missingMonths.join(', ')}`);
}

// Degenerate inputs must not crash or fabricate data.
const record = (date: string, carbonIntensity: number) => ({
  dataType: 'MonthlySummaryData',
  date,
  carbonIntensity,
  latestMonthEmissions: 10,
});
assert.equal(computeMetrics(parseReport({ value: [] })), null, 'empty report must yield no metrics');
assert.equal(computeMetrics(parseReport(null)), null, 'null report must yield no metrics');
assert.equal(
  parseReport({ value: [record('2025-01-01', 0)] }).length,
  0,
  'zero-intensity rows must be dropped',
);

assert.deepEqual(
  findMissingMonths(parseReport({ value: [record('2025-11-01', 1), record('2026-02-01', 1)] })),
  ['2025-12-01', '2026-01-01'],
  'gaps across a year boundary must be reported',
);

// The comparison window: same month a year earlier, total over the 12 months after it.
const series14 = parseReport({
  value: Array.from({ length: 14 }, (_, i) => record(`${2025 + Math.floor((6 + i) / 12)}-${String(((6 + i) % 12) + 1).padStart(2, '0')}-01`, 1)),
});
const m14 = computeMetrics(series14)!;
assert.equal(m14.base.date, '2025-08-01', 'base must be the same month a year before the last');
assert.equal(m14.last.date, '2026-08-01');
assert.ok(m14.yearOverYear);
assert.equal(m14.periodMonths, 12, 'total must cover exactly 12 months');
assert.equal(m14.points.length, 14, 'history before the window must stay in the charts');
const m6 = computeMetrics(series14.slice(0, 6))!;
assert.equal(m6.base.date, '2025-07-01', 'short history falls back to its first month');
assert.equal(m6.yearOverYear, false);

console.log('\nOK: all invariants hold.');
