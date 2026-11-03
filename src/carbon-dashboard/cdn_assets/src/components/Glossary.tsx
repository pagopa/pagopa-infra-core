import { Box, Card, CardContent, Grid, Link, Stack, Typography } from '@mui/material';
import { cardSx } from '../theme';

const SOURCE = 'https://learn.microsoft.com/en-us/azure/carbon-optimization/emissions-terminology';

interface Term {
  term: string;
  /** Microsoft's definition, translated but not reinterpreted. */
  definition: string;
  /** Optional breakdown of the definition, rendered as a bullet list. */
  items?: string[];
  /** What that definition implies for the numbers on this page. */
  here?: string;
}

/**
 * Microsoft's own vocabulary, in Italian.
 *
 * Every definition here is a translation of the Azure "Emissions terminology"
 * page, not a restatement: these words decide what the numbers on this page are
 * allowed to claim, so they are quoted rather than paraphrased.
 */
const TERMS: Term[] = [
  {
    term: 'CO2e',
    definition:
      'Equivalenti di anidride carbonica: unità di misura dell’effetto di riscaldamento dei gas serra. I prefissi più comuni sono chilogrammi (kgCO2e) e tonnellate metriche (MTCO2e).',
  },
  {
    term: 'kgCO2e',
    definition: 'La quantità di anidride carbonica equivalente espressa in chilogrammi.',
    here: 'È l’unità in cui Azure restituisce le emissioni e in cui sono calcolati tutti i valori di questa pagina. Sopra la tonnellata li mostriamo in t solo per leggibilità.',
  },
  {
    term: 'Ore di utilizzo cloud',
    definition:
      'Misurano quanto usiamo il cloud Microsoft, mettendo insieme potenza di calcolo, spazio di archiviazione e traffico dati. Questo utilizzo, su cui si basa il calcolo delle emissioni, può non coincidere con quello fatturato.',
    here: 'Azure non le restituisce: le ricaviamo dividendo le emissioni per l’intensità di carbonio. Sono una grandezza composita e non l’utilizzo fatturato, quindi ne pubblichiamo solo l’andamento, mai il valore assoluto.',
  },
  {
    term: 'Emissioni di carbonio',
    definition:
      'La quota delle emissioni di carbonio del cloud Microsoft allocata all’organizzazione, in base al suo utilizzo del cloud. Comprende gli Scope (1, 2 e/o 3) indicati e filtrati.',
    here: 'Non sono emissioni misurate sulle nostre piattaforme: sono la nostra quota di quelle di Microsoft, allocata in base a quanto cloud consumiamo.',
  },
  {
    term: 'Scope 1, 2 e 3',
    definition:
      'Categorizzazione di alto livello delle emissioni di gas serra in base all’attività che le ha prodotte:',
    items: [
      'Scope 1: emissioni dirette da combustione in loco (generatori, flotta aziendale).',
      'Scope 2: emissioni indirette, per esempio quelle del fornitore di energia elettrica.',
      'Scope 3: altre emissioni indirette lungo la catena del valore.',
    ],
    here: 'Nei grafici non sono mostrati separatamente: ogni valore li comprende tutti e tre, sommati.',
  },
  {
    term: 'Intensità di carbonio',
    definition:
      'La quota di emissioni Microsoft allocata all’organizzazione divisa per le sue ore di utilizzo cloud, in ciascun mese.',
    here: 'È restituita da Azure per ogni mese, in kgCO2e per ora di utilizzo cloud.',
  },
];

export function Glossary() {
  return (
    <Card elevation={0} sx={{ ...cardSx, height: 'auto' }}>
      <CardContent sx={{ p: { xs: 2, md: 3 } }}>
        <Stack spacing={0.5} mb={3}>
          <Typography variant="h6" component="h3">
            Glossario
          </Typography>
          <Typography variant="body2" color="text.secondary">
            Le definizioni riprendono la documentazione di Microsoft e stabiliscono che cosa questi
            numeri possono affermare.
          </Typography>
        </Stack>

        {/* Only the <dl>'s default bottom margin is reset: the grid's negative
            top/left gutter must survive, or the terms overflow on the right. */}
        <Grid container spacing={3} component="dl" sx={{ mb: 0 }}>
          {TERMS.map(({ term, definition, items, here }) => (
            <Grid item xs={12} md={6} key={term}>
              <Typography variant="subtitle2" component="dt" fontWeight={700}>
                {term}
              </Typography>
              <Box component="dd" sx={{ m: 0, mt: 0.5 }}>
                <Typography variant="body2" color="text.secondary">
                  {definition}
                </Typography>
                {items && (
                  <Box component="ul" sx={{ m: 0, mt: 0.5, pl: 2.5 }}>
                    {items.map((item) => (
                      <Typography
                        key={item}
                        component="li"
                        variant="body2"
                        color="text.secondary"
                        sx={{ mt: 0.25 }}
                      >
                        {item}
                      </Typography>
                    ))}
                  </Box>
                )}
                {here && (
                  <Typography variant="caption" color="text.secondary" component="p" sx={{ mt: 1 }}>
                    <strong>In questa dashboard:</strong> {here}
                  </Typography>
                )}
              </Box>
            </Grid>
          ))}
        </Grid>

        <Typography variant="caption" color="text.secondary" component="p" sx={{ mt: 3 }}>
          Fonte delle definizioni:{' '}
          <Link href={SOURCE} target="_blank" rel="noopener noreferrer">
            Emissions terminology — Carbon optimization in Azure
          </Link>{' '}
          (Microsoft Learn).
        </Typography>
      </CardContent>
    </Card>
  );
}
