import { Box, Button, Container, Grid, Stack, Typography } from '@mui/material';
import ArrowForwardIcon from '@mui/icons-material/ArrowForwardRounded';
import type { Metrics } from '../lib/carbon';
import { formatMonthLong, formatPercent, toMonth } from '../lib/format';
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
 * The full-bleed brand band that opens every PagoPA page. Both its gradients
 * are dark enough for white text, so the ink is fixed to white rather than read
 * from the palette; only the band itself follows the colour mode.
 */
export function SiteHero({ metrics }: Props) {
  return (
    <Box
      component="section"
      sx={{
        background: (t) => (t.palette.mode === 'dark' ? brand.heroGradientDark : brand.heroGradient),
        color: 'common.white',
        py: { xs: 5, md: 8 },
      }}
    >
      <Container maxWidth="lg">
        <Grid container spacing={{ xs: 4, md: 6 }} alignItems="center">
          <Grid item xs={12} md={7}>
            <Typography variant="overline" color="inherit" sx={{ opacity: 0.85 }}>
              Emissioni della piattaforma
            </Typography>
            <Typography
              variant="h2"
              component="h1"
              color="inherit"
              fontWeight={700}
              sx={{ mt: 1, fontSize: { xs: '2rem', md: '3rem' } }}
            >
              Le emissioni di gas serra (CO₂e) della piattaforma pagoPA
            </Typography>
            <Typography variant="body1" color="inherit" sx={{ mt: 2, maxWidth: '62ch', opacity: 0.92 }}>
              Andamento mensile delle emissioni di gas serra (CO₂e) della piattaforma pagoPA su Azure, così come
              pubblicate da Azure Carbon Optimization. Il confronto è fra le ore di utilizzo del
              cloud, le emissioni che ci vengono allocate e l’intensità di carbonio, cioè il
              rapporto fra le due.
            </Typography>

            <Stack direction={{ xs: 'column', sm: 'row' }} spacing={2} sx={{ mt: 4 }}>
              <Button
                component="a"
                href="#panoramica"
                variant="contained"
                color="inherit"
                endIcon={<ArrowForwardIcon />}
                sx={{
                  bgcolor: 'common.white',
                  color: brand.blue,
                  // mui-italia paints contained buttons #0055AA on hover with a
                  // more specific selector: blue on the blue band, text lost.
                  '&.MuiButton-contained:hover': { bgcolor: '#E7ECFC', color: brand.blue },
                }}
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
                  {formatMonthLong(metrics.base.date)} → {formatMonthLong(metrics.last.date)}
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
                    caption={`cloud, rispetto ${toMonth(formatMonthLong(metrics.base.date))}`}
                  />
                  <HeroFigure
                    label="Emissioni"
                    value={formatPercent(metrics.emissionsChange)}
                    caption={`rispetto ${toMonth(formatMonthLong(metrics.base.date))}`}
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
