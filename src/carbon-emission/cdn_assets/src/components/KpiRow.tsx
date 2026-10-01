import { Box, Card, CardContent, Grid, Stack, Typography } from '@mui/material';
import type { Metrics } from '../lib/carbon';
import { brand, cardSx } from '../theme';
import { formatMass, formatMonthLong, formatPercent } from '../lib/format';

/**
 * The honest headline.
 *
 * Absolute emissions are flat and noisy, so the story is the *gap* between
 * usage growth and emissions growth. The subject is cloud usage hours, which is
 * what Azure's intensity denominator actually counts — not platform traffic.
 * The sentence is generated from the data rather than written once, so it stays
 * true for a subscription whose emissions actually grew (README §1.4).
 */
function decouplingNote(usageChange: number, emissionsChange: number): string {
  const usage = formatPercent(usageChange);
  const emissions = formatPercent(emissionsChange);

  if (usageChange <= 0.02) {
    return `Nel periodo osservato le ore di utilizzo del cloud sono variate di ${usage} e le emissioni di ${emissions}.`;
  }
  if (emissionsChange <= 0.02) {
    return `Le ore di utilizzo del cloud sono cresciute di ${usage}, mentre le emissioni di CO₂ sono rimaste invariate o in calo (${emissions}).`;
  }
  if (emissionsChange < usageChange) {
    return `Le ore di utilizzo del cloud sono cresciute di ${usage}, mentre le emissioni sono cresciute molto meno (${emissions}).`;
  }
  return `Le ore di utilizzo del cloud sono cresciute di ${usage} e le emissioni di ${emissions}: nel periodo osservato non si registra un disaccoppiamento.`;
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
  const { first, last } = metrics;
  const window = `${formatMonthLong(first.date)} → ${formatMonthLong(last.date)}`;

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
            {decouplingNote(metrics.usageChange, metrics.emissionsChange)}
          </Typography>
        </CardContent>
      </Card>

      <Grid container spacing={2}>
        <Grid item xs={12} sm={6} md={3}>
          <Kpi
            label="Ore di utilizzo"
            value={formatPercent(metrics.usageChange)}
            caption="calcolo, archiviazione e trasferimento dati"
          />
        </Grid>
        <Grid item xs={12} sm={6} md={3}>
          <Kpi
            label="Emissioni"
            value={formatPercent(metrics.emissionsChange)}
            caption="variazione sul primo mese"
          />
        </Grid>
        <Grid item xs={12} sm={6} md={3}>
          <Kpi
            label="Totale periodo"
            value={formatMass(metrics.totalEmissions)}
            caption={`emissioni cumulate (${unit})`}
          />
        </Grid>
        <Grid item xs={12} sm={6} md={3}>
          <Kpi
            label="Intensità di carbonio"
            value={formatPercent(metrics.intensityChange)}
            caption={`${unit} per ora di utilizzo cloud`}
          />
        </Grid>
      </Grid>

      <Box>
        <Typography variant="caption" color="text.secondary">
          La riduzione dell&apos;intensità di carbonio dipende in larga parte dalla
          decarbonizzazione della rete elettrica e dagli acquisti di energia rinnovabile di
          Microsoft, non soltanto dalle ottimizzazioni sulle nostre piattaforme.
        </Typography>
      </Box>
    </Stack>
  );
}
