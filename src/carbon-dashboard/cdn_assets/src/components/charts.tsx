import {
  Area,
  Bar,
  BarChart,
  CartesianGrid,
  ComposedChart,
  Legend,
  Line,
  LineChart,
  ReferenceLine,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from 'recharts';
import type { ChartPoint } from '../lib/carbon';
import type { ChartPalette } from '../theme';
import { formatIndex, formatKg, formatMassCompact, formatMonth } from '../lib/format';
import { ChartTooltip } from './ChartTooltip';

/** Shared axis/grid chrome: solid hairlines, one shade off the surface. */
const axisProps = (palette: ChartPalette) => ({
  tickLine: false,
  axisLine: { stroke: palette.axis },
  tick: { fill: palette.textSecondary, fontSize: 12 },
});

const gridProps = (palette: ChartPalette) => ({
  // No strokeDasharray: a dashed grid reads as a threshold it isn't.
  stroke: palette.grid,
  vertical: false,
});

interface EndpointLabelProps {
  x?: number;
  y?: number;
  value?: number;
  index?: number;
}

/**
 * Direct-label only the final point of a line. A value on every point is
 * unreadable; the endpoint is the one a reader actually wants.
 */
const endpointLabel =
  (color: string, lastIndex: number) =>
  ({ x, y, value, index }: EndpointLabelProps) => {
    // Recharts' label renderer must always return an element, never null.
    if (index !== lastIndex || x == null || y == null || value == null) return <g />;
    return (
      <text x={x + 8} y={y} dy={4} fill={color} fontSize={12} fontWeight={600}>
        {formatIndex(value)}
      </text>
    );
  };

const legendProps = { wrapperStyle: { fontSize: 12, paddingTop: 8 } };

// --- 1. Monthly emissions --------------------------------------------------

export function EmissionsChart({
  points,
  palette,
}: {
  points: ChartPoint[];
  palette: ChartPalette;
}) {
  return (
    <ResponsiveContainer width="100%" height="100%">
      <BarChart data={points} margin={{ top: 8, right: 8, bottom: 0, left: 0 }} barCategoryGap="22%">
        <CartesianGrid {...gridProps(palette)} />
        <XAxis dataKey="date" tickFormatter={formatMonth} minTickGap={12} {...axisProps(palette)} />
        <YAxis tickFormatter={formatMassCompact} width={56} {...axisProps(palette)} />
        <Tooltip
          cursor={{ fill: palette.grid, fillOpacity: 0.4 }}
          content={<ChartTooltip format={(_, v) => formatKg(v)} />}
        />
        {/* Single series: the title names it, so no legend box. */}
        <Bar
          dataKey="emissions"
          name="Emissioni"
          fill={palette.emissions}
          radius={[4, 4, 0, 0]}
          maxBarSize={44}
        />
      </BarChart>
    </ResponsiveContainer>
  );
}

// --- 2. The story chart: everything indexed to a common base ---------------

export function IndexedChart({
  points,
  palette,
}: {
  points: ChartPoint[];
  palette: ChartPalette;
}) {
  const last = points.length - 1;
  const line = (dataKey: string, name: string, color: string) => (
    <Line
      key={dataKey}
      type="monotone"
      dataKey={dataKey}
      name={name}
      stroke={color}
      strokeWidth={2}
      dot={false}
      // 2px surface ring keeps overlapping markers separable.
      activeDot={{ r: 5, strokeWidth: 2, stroke: palette.surface }}
      label={endpointLabel(color, last)}
    />
  );

  return (
    <ResponsiveContainer width="100%" height="100%">
      {/* Right margin reserves room for the endpoint labels. */}
      <LineChart data={points} margin={{ top: 8, right: 52, bottom: 0, left: 0 }}>
        <CartesianGrid {...gridProps(palette)} />
        <XAxis dataKey="date" tickFormatter={formatMonth} minTickGap={12} {...axisProps(palette)} />
        <YAxis tickFormatter={formatIndex} width={56} {...axisProps(palette)} />
        <ReferenceLine y={100} stroke={palette.axis} />
        <Tooltip content={<ChartTooltip format={(_, v) => formatIndex(v)} />} />
        <Legend {...legendProps} />
        {line('usageIndex', 'Ore di utilizzo', palette.usage)}
        {line('emissionsIndex', 'Emissioni', palette.emissions)}
        {line('intensityIndex', 'Intensità di carbonio', palette.intensity)}
      </LineChart>
    </ResponsiveContainer>
  );
}

// --- 3. Counterfactual: what the baseline intensity would have cost --------

export function CounterfactualChart({
  points,
  palette,
}: {
  points: ChartPoint[];
  palette: ChartPalette;
}) {
  return (
    <ResponsiveContainer width="100%" height="100%">
      <ComposedChart data={points} margin={{ top: 8, right: 8, bottom: 0, left: 0 }}>
        <CartesianGrid {...gridProps(palette)} />
        <XAxis dataKey="date" tickFormatter={formatMonth} minTickGap={12} {...axisProps(palette)} />
        <YAxis tickFormatter={formatMassCompact} width={56} {...axisProps(palette)} />
        <Tooltip content={<ChartTooltip format={(_, v) => formatKg(v)} />} />
        <Legend {...legendProps} />
        {/* Drawn first so the actual series sits on top; the exposed band
            between the two is the gap to the scenario, in either direction. Dashing marks the scenario
            as hypothetical. */}
        <Area
          type="monotone"
          dataKey="counterfactual"
          name="Scenario a intensità costante"
          stroke={palette.usage}
          strokeWidth={2}
          strokeDasharray="6 4"
          fill={palette.usage}
          fillOpacity={0.12}
          activeDot={{ r: 5, strokeWidth: 2, stroke: palette.surface }}
        />
        <Area
          type="monotone"
          dataKey="emissions"
          name="Emissioni effettive"
          stroke={palette.emissions}
          strokeWidth={2}
          fill={palette.emissions}
          fillOpacity={0.22}
          activeDot={{ r: 5, strokeWidth: 2, stroke: palette.surface }}
        />
      </ComposedChart>
    </ResponsiveContainer>
  );
}
