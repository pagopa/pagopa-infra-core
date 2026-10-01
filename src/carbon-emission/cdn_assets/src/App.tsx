import { useCallback, useEffect, useMemo, useState } from 'react';
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
  ALL_SUBSCRIPTIONS,
  aggregate,
  computeMetrics,
  loadManifest,
  loadSeries,
  type MonthPoint,
} from './lib/carbon';
import { formatMass, formatMonthLong, formatPercent } from './lib/format';
import { chartPalette, muiTheme, type ColorMode } from './theme';
import { ChartFrame } from './components/ChartFrame';
import { CounterfactualChart, EmissionsChart, IndexedChart } from './components/charts';
import { DataTable } from './components/DataTable';
import { EquivalencesCard } from './components/EquivalencesCard';
import { KpiRow } from './components/KpiRow';
import { Glossary } from './components/Glossary';
import { Section } from './components/Section';
import { SiteFooter } from './components/SiteFooter';
import { SiteHeader, type NavItem } from './components/SiteHeader';
import { SiteHero } from './components/SiteHero';
import { SubscriptionSelector } from './components/SubscriptionSelector';

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

/** Subscription selection lives in the URL, so a view is a shareable link. */
function initialSlug(): string {
  return new URLSearchParams(window.location.search).get('sub') ?? ALL_SUBSCRIPTIONS;
}

export default function App() {
  const [manifest, setManifest] = useState<Manifest | null>(null);
  const [series, setSeries] = useState<Record<string, MonthPoint[]>>({});
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const [slug, setSlug] = useState<string>(initialSlug);
  const [mode, setMode] = useState<ColorMode>(initialColorMode);

  useEffect(() => {
    let cancelled = false;
    (async () => {
      try {
        const loaded = await loadManifest();
        const data = await loadSeries(loaded.subscriptions);
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

  const selectSlug = useCallback((next: string) => {
    setSlug(next);
    const url = new URL(window.location.href);
    if (next === ALL_SUBSCRIPTIONS) url.searchParams.delete('sub');
    else url.searchParams.set('sub', next);
    window.history.replaceState(null, '', url);
  }, []);

  const subscriptions = manifest?.subscriptions ?? [];
  // A stale or hand-edited ?sub= must not produce an empty dashboard.
  const known = subscriptions.some((s) => s.slug === slug);
  const activeSlug = known ? slug : ALL_SUBSCRIPTIONS;

  const points = useMemo(() => {
    if (activeSlug === ALL_SUBSCRIPTIONS) {
      return aggregate(subscriptions.map((s) => series[s.slug] ?? []));
    }
    return series[activeSlug] ?? [];
  }, [activeSlug, series, subscriptions]);

  const metrics = useMemo(() => computeMetrics(points), [points]);

  const isSynthetic =
    activeSlug === ALL_SUBSCRIPTIONS
      ? subscriptions.some((s) => s.synthetic && (series[s.slug]?.length ?? 0) > 0)
      : (subscriptions.find((s) => s.slug === activeSlug)?.synthetic ?? false);

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

          {/* Filter bar, in the band immediately under the hero: the selection
              applies to every section below it. */}
          {manifest && (
            <Box sx={{ bgcolor: 'background.paper', borderBottom: 1, borderColor: 'divider' }}>
              <Container maxWidth="lg" sx={{ py: 2 }}>
                <SubscriptionSelector
                  subscriptions={subscriptions}
                  value={activeSlug}
                  onChange={selectSlug}
                  dataThrough={metrics ? formatMonthLong(metrics.last.date) : undefined}
                />
              </Container>
            </Box>
          )}

          {(error || isSynthetic || (!loading && !error && !metrics)) && (
            <Container maxWidth="lg" sx={{ pt: 3 }}>
              <Stack spacing={2}>
                {error && (
                  <Alert severity="error">
                    Impossibile caricare i dati: {error}. Verifica che <code>data/index.json</code>{' '}
                    sia raggiungibile.
                  </Alert>
                )}
                {isSynthetic && (
                  <Alert severity="warning">
                    La selezione include dati di esempio generati, non export reali di Azure. I
                    numeri mostrati non sono utilizzabili per comunicazioni esterne.
                  </Alert>
                )}
                {!loading && !error && !metrics && (
                  <Alert severity="info">
                    Nessun dato mensile disponibile per la selezione corrente.
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
                subtitle="Le grandezze chiave della selezione corrente, calcolate sul primo e sull'ultimo mese disponibili."
              >
                <KpiRow metrics={metrics} unit={unit} />
              </Section>

              <Section
                id="andamento"
                overline="Andamento"
                title="Utilizzo, emissioni e intensità a confronto"
                subtitle={`Numeri indice, base 100 a ${formatMonthLong(metrics.first.date)}.`}
              >
                <ChartFrame
                  title="Disaccoppiamento fra crescita ed emissioni"
                  subtitle={`Base 100 a ${formatMonthLong(metrics.first.date)}`}
                  height={340}
                  footnote={
                    'Le tre grandezze hanno unità di misura diverse e sono quindi riportate a un indice comune su un solo asse. Le serie non sono indipendenti: le ore di utilizzo sono ricavate come emissioni ÷ intensità, quindi la distanza fra la linea delle ore di utilizzo e quella delle emissioni è esattamente il calo dell’intensità di carbonio.'
                  }
                >
                  <IndexedChart points={metrics.points} palette={palette} />
                </ChartFrame>
              </Section>

              <Section
                id="dettaglio"
                overline="Dettaglio"
                title="Valori assoluti ed emissioni evitate"
                subtitle="A sinistra i chilogrammi restituiti da Azure; a destra il confronto con uno scenario a intensità di carbonio costante."
              >
                <Grid container spacing={3}>
                  <Grid item xs={12} md={6}>
                    <ChartFrame
                      title={`Emissioni mensili (${unit})`}
                      subtitle="Valori assoluti, così come restituiti da Azure"
                      footnote="Azure rivede retroattivamente i mesi già pubblicati: le variazioni sono ricalcolate dalla serie, non lette dai campi dell'API."
                    >
                      <EmissionsChart points={metrics.points} palette={palette} />
                    </ChartFrame>
                  </Grid>
                  <Grid item xs={12} md={6}>
                    <ChartFrame
                      title="Emissioni evitate"
                      subtitle={`${formatMass(metrics.avoided)} in meno rispetto allo scenario a intensità costante (${formatPercent(-metrics.avoidedRatio)})`}
                      footnote="Scenario teorico: stessi volumi di utilizzo con l'intensità di carbonio del primo mese. Metrica di supporto — poggia su un denominatore che Microsoft non definisce."
                    >
                      <CounterfactualChart points={metrics.points} palette={palette} />
                    </ChartFrame>
                  </Grid>
                </Grid>

                {manifest.equivalences && (
                  <Box sx={{ mt: 3 }}>
                    <EquivalencesCard
                      equivalences={manifest.equivalences}
                      kg={metrics.totalEmissions}
                      caption="Le emissioni totali del periodo"
                    />
                  </Box>
                )}
              </Section>

              <Section
                id="dati"
                overline="Dati"
                title="La serie mensile completa"
                subtitle="Ogni riga è un mese così come pubblicato da Azure Carbon Optimization."
              >
                <DataTable points={metrics.points} unit={unit} />
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
                      I dati provengono da Azure Carbon Optimization
                      (<code>az carbon get-emission-report</code>), nella forma{' '}
                      <code>MonthlySummaryReport</code>: un record per mese e per sottoscrizione. Le
                      emissioni sono espresse in <strong>{unit}</strong> e sono la quota delle
                      emissioni del cloud Microsoft allocata a noi in base al nostro utilizzo — non
                      emissioni misurate sulle nostre piattaforme.
                      {manifest.carbonScope && ` Scope considerato: ${manifest.carbonScope}.`}
                    </Typography>
                    <Typography variant="body1" color="text.secondary">
                      L&apos;API restituisce due grandezze per mese: le emissioni e l&apos;intensità
                      di carbonio. Le <strong>ore di utilizzo cloud</strong> non sono restituite: le
                      ricaviamo dividendo le prime per la seconda, perché Microsoft definisce
                      l&apos;intensità proprio come emissioni allocate ÷ ore di utilizzo. Ne segue
                      che le tre serie del grafico a indice non sono indipendenti — la distanza fra
                      utilizzo ed emissioni è il calo dell&apos;intensità, vista da un&apos;altra
                      angolazione.
                    </Typography>
                    <Typography variant="body1" color="text.secondary">
                      Quelle ore sommano calcolo, archiviazione e trasferimento dati, e Microsoft
                      avverte che possono non coincidere con l&apos;utilizzo ai fini di
                      fatturazione. Non sono quindi una misura del traffico sulle piattaforme: per
                      quello servono le metriche di volume dei singoli prodotti. Il loro valore
                      assoluto non viene mai pubblicato qui, solo indici e variazioni.
                    </Typography>
                    <Typography variant="caption" color="text.secondary">
                      I dati del mese precedente sono pubblicati da Microsoft entro il giorno 19 del
                      mese corrente. Azure rivede retroattivamente i mesi già pubblicati, quindi
                      ogni variazione mostrata è ricalcolata dalla serie. Ultimo aggiornamento dei
                      dati: {formatMonthLong(metrics.last.date)}.
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
