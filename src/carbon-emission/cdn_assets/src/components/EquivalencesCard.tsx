import { Card, CardContent, Grid, Link, Stack, Typography } from '@mui/material';
import { cardSx } from '../theme';
import type { Equivalences } from '../types';
import { formatCount, formatMass } from '../lib/format';

interface Props {
  equivalences: Equivalences;
  kg: number;
  caption: string;
}

/**
 * Emissions equivalents, gated on `verified`.
 *
 * The Azure portal derives its own equivalents from the EPA calculator, so the
 * approach is sound — but shipping unverified coefficients in a page whose
 * whole purpose is to be believed is not. Until someone checks them against the
 * current EPA calculator and flips the flag, the card shows why it is empty.
 */
export function EquivalencesCard({ equivalences, kg, caption }: Props) {
  const { verified, items, source, note } = equivalences;

  return (
    <Card elevation={0} sx={{ ...cardSx, height: 'auto' }}>
      <CardContent sx={{ p: { xs: 2, md: 3 } }}>
        <Typography variant="h6" component="h2" gutterBottom>
          Equivalenze
        </Typography>

        {verified ? (
          <>
            <Typography variant="body2" color="text.secondary" mb={2}>
              {caption} ({formatMass(kg)}) equivalgono a:
            </Typography>
            <Grid container spacing={2}>
              {items.map((item) => (
                <Grid item xs={12} sm={4} key={item.id}>
                  <Stack spacing={0.5}>
                    <Typography variant="h5" component="p" fontWeight={700}>
                      {item.kgCO2ePerUnit > 0 ? formatCount(kg / item.kgCO2ePerUnit) : '—'}
                    </Typography>
                    <Typography variant="caption" color="text.secondary">
                      {item.label}
                    </Typography>
                  </Stack>
                </Grid>
              ))}
            </Grid>
          </>
        ) : (
          <Typography variant="body2" color="text.secondary">
            {note ?? 'Coefficienti di equivalenza non ancora verificati.'}
          </Typography>
        )}

        <Typography variant="caption" color="text.secondary" component="p" sx={{ mt: 2 }}>
          Fonte dei coefficienti:{' '}
          <Link href={source} target="_blank" rel="noopener noreferrer">
            EPA Greenhouse Gas Equivalencies Calculator
          </Link>
        </Typography>
      </CardContent>
    </Card>
  );
}
