import { useEffect, useMemo, useState } from 'react';
import {
  Alert,
  Box,
  Container,
  CssBaseline,
  Grid,
  LinearProgress,
  Stack,
  ThemeProvider,
  Typography,
} from '@mui/material';

import type { Manifest } from './types';
import {
  computeMetrics,
  loadManifest,
  loadSeries,
  type MonthPoint,
} from './lib/carbon';
import { formatBase, formatKg, formatMonthLong, formatPercent, toMonth } from './lib/format';
import { chartPalette, muiTheme, type ColorMode } from './theme';
import { ChartFrame } from './components/ChartFrame';
import { CounterfactualChart, EmissionsChart, IndexedChart } from './components/charts';
import { DataTable } from './components/DataTable';
import { KpiRow } from './components/KpiRow';
import { Glossary } from './components/Glossary';
import { Section } from './components/Section';
import { SiteFooter } from './components/SiteFooter';
import { SiteHeader, type NavItem } from './components/SiteHeader';
import { SiteHero } from './components/SiteHero';

const COLOR_MODE_KEY = 'carbon-dashboard-color-mode';

/** Section nav in the product bar. Every id here is rendered unconditionally. */
const NAV: NavItem[] = [
  { id: 'panoramica', label: 'Panoramica' },
  { id: 'andamento', label: 'Andamento' },
  { id: 'dettaglio', label: 'Dettaglio' },
  { id: 'dati', label: 'Dati' },
  { id: 'metodologia', label: 'Metodologia' },
];

function initialColorMode(): ColorMode {
  try {
    const stored = localStorage.getItem(COLOR_MODE_KEY);
    if (stored === 'light' || stored === 'dark') return stored;
  } catch {
    // Private browsing, blocked storage — fall through to the OS preference.
  }
  return window.matchMedia?.('(prefers-color-scheme: dark)').matches ? 'dark' : 'light';
}

export default function App() {
  const [manifest, setManifest] = useState<Manifest | null>(null);
  const [series, setSeries] = useState<Record<string, MonthPoint[]>>({});
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const [mode, setMode] = useState<ColorMode>(initialColorMode);

  useEffect(() => {
    let cancelled = false;
    (async () => {
      try {
        const loaded = await loadManifest();
        const data = await loadSeries(loaded.series);
        if (cancelled) return;
        setManifest(loaded);
        setSeries(data);
      } catch (err) {
        if (!cancelled) setError(err instanceof Error ? err.message : String(err));
      } finally {
        if (!cancelled) setLoading(false);
      }
    })();
    return () => {
      cancelled = true;
    };
  }, []);

  useEffect(() => {
    try {
      localStorage.setItem(COLOR_MODE_KEY, mode);
    } catch {
      // Not being able to remember the preference is not worth an error.
    }
  }, [mode]);

  // The dashboard shows a single subscription: the first one in the manifest.
  const slug = manifest?.series[0]?.slug;
  const metrics = useMemo(
    () => computeMetrics(slug ? (series[slug] ?? []) : []),
    [slug, series],
  );

  const theme = muiTheme(mode);
  const palette = chartPalette(mode);
  const unit = manifest?.emissionsUnit ?? 'kgCO2e';

  return (
    <ThemeProvider theme={theme}>
      <CssBaseline />
      <Box
        sx={{
          minHeight: '100vh',
          display: 'flex',
          flexDirection: 'column',
          bgcolor: 'background.default',
        }}
      >
        <SiteHeader
          mode={mode}
          onToggleMode={() => setMode(mode === 'dark' ? 'light' : 'dark')}
          nav={NAV}
        />
        {loading && <LinearProgress />}

        <Box component="main" sx={{ flexGrow: 1 }}>
          <SiteHero metrics={metrics} />

          {(error || (!loading && !error && !metrics)) && (
            <Container maxWidth="lg" sx={{ pt: 3 }}>
              <Stack spacing={2}>
                {error && (
                  <Alert severity="error">
                    Impossibile caricare i dati: {error}. Verifica che <code>data/index.json</code>{' '}
                    sia raggiungibile.
                  </Alert>
                )}
                {!loading && !error && !metrics && (
                  <Alert severity="info">
                    Nessun dato mensile disponibile.
                  </Alert>
                )}
              </Stack>
            </Container>
          )}

          {metrics && manifest && (
            <>
              <Section
                id="panoramica"
                overline="Panoramica"
                title="Il quadro del periodo"
                subtitle={`Le grandezze chiave della piattaforma pagoPA: variazioni di ${formatMonthLong(metrics.last.date)} rispetto ${toMonth(formatMonthLong(metrics.base.date))}.`}
              >
                <KpiRow metrics={metrics} unit={unit} />
              </Section>

              <Section
                id="andamento"
                overline="Andamento"
                title="Utilizzo, emissioni e intensità a confronto"
                subtitle={`Numeri indice sull’intera serie, base 100 ${toMonth(formatBase(metrics.base.date, metrics.yearOverYear))}.`}
              >
                <ChartFrame
                  title="Ore di utilizzo, emissioni e intensità di carbonio"
                  subtitle={`Base 100 ${toMonth(formatMonthLong(metrics.base.date))}`}
                  height={340}
                  footnote={
                    'Le tre grandezze hanno unità di misura diverse e sono quindi riportate a un indice comune su un solo asse. Le serie non sono indipendenti: le ore di utilizzo sono ricavate dividendo le emissioni per l’intensità, quindi il rapporto fra la linea delle emissioni e quella delle ore di utilizzo è la linea dell’intensità di carbonio.'
                  }
                >
                  <IndexedChart points={metrics.points} palette={palette} />
                </ChartFrame>
              </Section>

              <Section
                id="dettaglio"
                overline="Dettaglio"
                title="Valori assoluti e scenario a intensità costante"
                subtitle="Nel primo grafico i chilogrammi restituiti da Azure; nel secondo il confronto con uno scenario a intensità di carbonio costante."
              >
                <Grid container spacing={3}>
                  <Grid item xs={12} md={6}>
                    <ChartFrame
                      title={`Emissioni mensili (${unit})`}
                      subtitle={`Tutti i mesi pubblicati, da ${formatMonthLong(metrics.seriesStart.date)} ${toMonth(formatMonthLong(metrics.last.date))}`}
                      footnote="Emissioni allocate a pagoPA in ciascun mese, così come restituite da Azure Carbon Optimization e comprensive di Scope 1, 2 e 3. Azure può rivedere i mesi già pubblicati: ogni barra riporta l’ultimo valore scaricato, con la data indicata nella tabella dei dati."
                      fill
                    >
                      <EmissionsChart points={metrics.points} palette={palette} />
                    </ChartFrame>
                  </Grid>
                  <Grid item xs={12} md={6}>
                    <ChartFrame
                      title={`Confronto con lo scenario a intensità costante (${unit})`}
                      subtitle={`Ultimi ${metrics.periodMonths} mesi, differenza fra emissioni effettive e scenario: ${metrics.counterfactualGap > 0 ? '+' : ''}${formatKg(metrics.counterfactualGap)} (${formatPercent(metrics.counterfactualGapRatio)})`}
                      footnote={`Scenario teorico: stessi volumi di utilizzo con l'intensità di carbonio di ${formatMonthLong(metrics.base.date)}, il mese di riferimento. Metrica di supporto: le ore di utilizzo cloud non sono restituite dall’API ma ricavate da emissioni e intensità, e non coincidono con l’utilizzo fatturato.`}
                    >
                      <CounterfactualChart points={metrics.windowPoints} palette={palette} />
                    </ChartFrame>
                  </Grid>
                </Grid>
              </Section>

              <Section
                id="dati"
                overline="Dati"
                title="La serie mensile completa"
                subtitle="Tutti i mesi pubblicati: emissioni restituite da Azure Carbon Optimization e valori calcolati da noi."
              >
                {metrics.missingMonths.length > 0 && (
                  <Alert severity="info" sx={{ mb: 2 }}>
                    Mesi non disponibili nella serie:{' '}
                    {metrics.missingMonths.map(formatMonthLong).join(', ')}. Nei grafici i mesi
                    adiacenti sono mostrati uno accanto all&apos;altro.
                  </Alert>
                )}
                <DataTable points={metrics.points} unit={unit} baseDate={metrics.base.date} />
              </Section>

              <Section
                id="metodologia"
                overline="Metodologia"
                title="Come misuriamo"
                subtitle="Che cosa misura ciascun numero, con le parole di Microsoft."
                tinted
              >
                <Stack spacing={3}>
                  <Stack spacing={2} sx={{ maxWidth: '75ch' }}>
                    <Typography variant="body1" color="text.secondary">
                      I dati provengono dall&apos;API di Azure Carbon Optimization (report{' '}
                      <code>MonthlySummaryReport</code>) e riguardano la sottoscrizione Azure della
                      piattaforma pagoPA, con un valore per ogni mese espresso in{' '}
                      <strong>{unit}</strong>.
                      Comprende tutte le emissioni attribuite a pagoPA: dirette, legate
                      all&apos;energia elettrica e lungo la catena di fornitura (i tre «Scope» del
                      glossario).
                    </Typography>
                    <Typography variant="body1" color="text.secondary">
                      Per ogni mese Azure restituisce emissioni e intensità di carbonio; le ore di
                      utilizzo le ricaviamo dividendo le prime per la seconda. Per questo le tre
                      linee del grafico a indice non sono indipendenti: il rapporto fra emissioni e
                      ore di utilizzo è proprio l&apos;intensità.
                    </Typography>
                    <Typography variant="caption" color="text.secondary">
                      Azure rivede retroattivamente i mesi già pubblicati, quindi
                      ogni variazione mostrata è ricalcolata dalla serie. L&apos;API restituisce
                      solo gli ultimi mesi: quelli più vecchi restano pubblicati con l&apos;ultimo
                      valore scaricato. La data in cui ogni mese è stato scaricato è nella colonna
                      «Aggiornato da Azure il» della tabella («—» se non disponibile). Le variazioni confrontano l&apos;ultimo mese disponibile,{' '}
                      {formatMonthLong(metrics.last.date)}, con lo stesso mese dell&apos;anno
                      precedente, che fa da base 100 nei grafici a indice: ogni mese il confronto
                      si sposta in avanti di un mese. Serie storica disponibile da{' '}
                      {formatMonthLong(metrics.seriesStart.date)}.
                    </Typography>
                  </Stack>

                  <Glossary />
                </Stack>
              </Section>
            </>
          )}
        </Box>

        <SiteFooter mode={mode} />
      </Box>
    </ThemeProvider>
  );
}
