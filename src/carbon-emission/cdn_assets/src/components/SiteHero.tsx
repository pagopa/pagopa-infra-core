import { Box, Button, Container, Grid, Stack, Typography } from '@mui/material';
import ArrowForwardIcon from '@mui/icons-material/ArrowForwardRounded';
import type { Metrics } from '../lib/carbon';
import { formatMonthLong, formatPercent } from '../lib/format';
import { brand } from '../theme';

interface Props {
  metrics: Metrics | null;
}

function HeroFigure({ label, value, caption }: { label: string; value: string; caption: string }) {
  return (
    <Stack spacing={0.25}>
      <Typography variant="caption" color="inherit" sx={{ opacity: 0.8, textTransform: 'uppercase' }}>
        {label}
      </Typography>
      <Typography variant="h4" component="p" color="inherit" fontWeight={700}>
        {value}
      </Typography>
      <Typography variant="caption" color="inherit" sx={{ opacity: 0.8 }}>
        {caption}
      </Typography>
    </Stack>
  );
}

/**
 * The full-bleed brand band that opens every PagoPA page. It keeps the deep
 * blue in both colour modes — it is brand chrome, not a themed surface — so the
 * text colour is fixed to white rather than read from the palette.
 */
export function SiteHero({ metrics }: Props) {
  return (
    <Box
      component="section"
      sx={{
        background: brand.heroGradient,
        color: 'common.white',
        py: { xs: 5, md: 8 },
      }}
    >
      <Container maxWidth="lg">
        <Grid container spacing={{ xs: 4, md: 6 }} alignItems="center">
          <Grid item xs={12} md={7}>
            <Typography variant="overline" color="inherit" sx={{ opacity: 0.85 }}>
              Sostenibilità delle piattaforme
            </Typography>
            <Typography
              variant="h2"
              component="h1"
              color="inherit"
              fontWeight={700}
              sx={{ mt: 1, fontSize: { xs: '2rem', md: '3rem' } }}
            >
              Le piattaforme crescono, le emissioni no
            </Typography>
            <Typography variant="body1" color="inherit" sx={{ mt: 2, maxWidth: '62ch', opacity: 0.92 }}>
              Andamento mensile delle emissioni di CO₂ delle sottoscrizioni Azure, così come
              pubblicate da Azure Carbon Optimization. Il confronto è fra le ore di utilizzo del
              cloud e le emissioni che ci vengono allocate: quando le prime crescono più delle
              seconde, l’intensità di carbonio è scesa.
            </Typography>

            <Stack direction={{ xs: 'column', sm: 'row' }} spacing={2} sx={{ mt: 4 }}>
              <Button
                component="a"
                href="#panoramica"
                variant="contained"
                color="inherit"
                endIcon={<ArrowForwardIcon />}
                sx={{ bgcolor: 'common.white', color: brand.blue, '&:hover': { bgcolor: '#E7ECFC' } }}
              >
                Esplora i dati
              </Button>
              <Button
                component="a"
                href="#metodologia"
                variant="outlined"
                color="inherit"
                sx={{ borderColor: 'rgba(255,255,255,0.7)' }}
              >
                Come li misuriamo
              </Button>
            </Stack>
          </Grid>

          {metrics && (
            <Grid item xs={12} md={5}>
              <Box
                sx={{
                  p: { xs: 2.5, md: 3 },
                  borderRadius: 2,
                  border: '1px solid rgba(255,255,255,0.28)',
                  bgcolor: 'rgba(255,255,255,0.10)',
                  backdropFilter: 'blur(2px)',
                }}
              >
                <Typography variant="overline" color="inherit" sx={{ opacity: 0.85 }}>
                  {formatMonthLong(metrics.first.date)} → {formatMonthLong(metrics.last.date)}
                </Typography>
                <Stack
                  direction="row"
                  spacing={3}
                  sx={{ mt: 2 }}
                  divider={
                    <Box sx={{ width: '1px', bgcolor: 'rgba(255,255,255,0.28)', alignSelf: 'stretch' }} />
                  }
                >
                  <HeroFigure
                    label="Ore di utilizzo"
                    value={formatPercent(metrics.usageChange)}
                    caption="cloud, sul primo mese"
                  />
                  <HeroFigure
                    label="Emissioni"
                    value={formatPercent(metrics.emissionsChange)}
                    caption="sul primo mese"
                  />
                </Stack>
              </Box>
            </Grid>
          )}
        </Grid>
      </Container>
    </Box>
  );
}
