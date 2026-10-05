import { Box, Card, CardContent, Grid, Stack, Typography } from '@mui/material';
import type { Metrics } from '../lib/carbon';
import { brand, cardSx } from '../theme';
import { formatBase, formatMass, formatMonthLong, formatPercent, toMonth } from '../lib/format';

/**
 * The headline sentence.
 *
 * The data is refreshed monthly by an external job, so the direction of any
 * change is unknown when this is written. The sentence only states the three
 * variations, with their sign, and never qualifies them.
 */
function periodNote({ base, last, usageChange, emissionsChange, intensityChange }: Metrics): string {
  return `Fra ${formatMonthLong(base.date)} e ${formatMonthLong(last.date)} le ore di utilizzo del cloud sono variate di ${formatPercent(usageChange)}, le emissioni di ${formatPercent(emissionsChange)} e l’intensità di carbonio di ${formatPercent(intensityChange)}.`;
}

interface KpiProps {
  label: string;
  value: string;
  caption: string;
}

function Kpi({ label, value, caption }: KpiProps) {
  return (
    <Card elevation={0} sx={cardSx}>
      <CardContent>
        <Stack spacing={0.5}>
          <Typography variant="caption" color="text.secondary" textTransform="uppercase">
            {label}
          </Typography>
          {/* Sans-serif, theme ink — a hero figure is not decoration. */}
          <Typography variant="h4" component="p" fontWeight={700} color="text.primary">
            {value}
          </Typography>
          <Typography variant="caption" color="text.secondary">
            {caption}
          </Typography>
        </Stack>
      </CardContent>
    </Card>
  );
}

export function KpiRow({ metrics, unit }: { metrics: Metrics; unit: string }) {
  const { base, last, periodStart, periodMonths, yearOverYear } = metrics;
  const window = yearOverYear
    ? `${formatMonthLong(last.date)} rispetto allo stesso mese dell’anno precedente`
    : `${formatMonthLong(base.date)} → ${formatMonthLong(last.date)}`;

  return (
    <Stack spacing={2}>
      {/* The headline sentence carries a brand accent bar, the way a pull
          quote does on pagopa.it. */}
      <Card
        elevation={0}
        sx={{ ...cardSx, height: 'auto', borderLeft: 4, borderLeftColor: brand.blueItalia }}
      >
        <CardContent sx={{ p: { xs: 2, md: 3 } }}>
          <Typography variant="overline" color="text.secondary">
            {window}
          </Typography>
          <Typography variant="h5" component="p" sx={{ mt: 1, maxWidth: '62ch' }}>
            {periodNote(metrics)}
          </Typography>
        </CardContent>
      </Card>

      {/* Wrapped: Stack zeroes its children's margins, which would cancel the
          grid's negative gutter and push the cards off the right edge. */}
      <Box>
        <Grid container spacing={2}>
          <Grid item xs={12} sm={6} md={3}>
            <Kpi
              label="Ore di utilizzo"
              value={formatPercent(metrics.usageChange)}
              caption={`calcolo, archiviazione e trasferimento dati, rispetto ${toMonth(formatBase(base.date, yearOverYear))}`}
            />
          </Grid>
          <Grid item xs={12} sm={6} md={3}>
            <Kpi
              label="Emissioni"
              value={formatPercent(metrics.emissionsChange)}
              caption={`variazione rispetto ${toMonth(formatBase(base.date, yearOverYear))}`}
            />
          </Grid>
          <Grid item xs={12} sm={6} md={3}>
            <Kpi
              label={periodMonths === 12 ? 'Ultimi 12 mesi' : `Ultimi ${periodMonths} mesi`}
              value={formatMass(metrics.totalEmissions)}
              caption={`emissioni cumulate da ${formatMonthLong(periodStart.date)} ${toMonth(formatMonthLong(last.date))} (CO2e)`}
            />
          </Grid>
          <Grid item xs={12} sm={6} md={3}>
            <Kpi
              label="Intensità di carbonio"
              value={formatPercent(metrics.intensityChange)}
              caption={`variazione dei ${unit} per ora di utilizzo cloud, rispetto ${toMonth(formatBase(base.date, yearOverYear))}`}
            />
          </Grid>
        </Grid>
      </Box>

      <Box>
        <Typography variant="caption" color="text.secondary">
          L&apos;andamento dell&apos;intensità di carbonio dipende in larga parte dal mix
          energetico della rete elettrica e dagli acquisti di energia rinnovabile di Microsoft,
          non soltanto dalle scelte sulle nostre piattaforme.
        </Typography>
      </Box>
    </Stack>
  );
}
