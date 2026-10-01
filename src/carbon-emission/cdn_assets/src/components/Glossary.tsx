import { Box, Card, CardContent, Grid, Link, Stack, Typography } from '@mui/material';
import { cardSx } from '../theme';

const SOURCE = 'https://learn.microsoft.com/en-us/azure/carbon-optimization/emissions-terminology';

interface Term {
  term: string;
  /** Microsoft's definition, translated but not reinterpreted. */
  definition: string;
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
    term: 'Emissioni di carbonio',
    definition:
      'La quota delle emissioni di carbonio del cloud Microsoft allocata alla tua azienda, in base al tuo utilizzo del cloud. Comprende gli Scope (1, 2 e/o 3) indicati e filtrati.',
    here: 'Non sono emissioni misurate sulle nostre piattaforme: sono la nostra quota di quelle di Microsoft, allocata in base a quanto cloud consumiamo.',
  },
  {
    term: 'Scope 1, 2 e 3',
    definition:
      'Categorizzazione di alto livello delle emissioni di gas serra in base all’attività che le ha prodotte. Scope 1: emissioni dirette da combustione in loco (generatori, flotta aziendale). Scope 2: emissioni indirette, per esempio quelle del fornitore di energia elettrica. Scope 3: altre emissioni indirette lungo la catena del valore.',
  },
  {
    term: 'Intensità di carbonio',
    definition:
      'La quota di emissioni Microsoft allocata alla tua azienda divisa per le ore di utilizzo cloud della tua azienda nel periodo selezionato. Le ore di utilizzo sono la somma di calcolo, archiviazione e trasferimento dati nel cloud Microsoft. L’utilizzo usato per il calcolo delle emissioni può non coincidere con l’utilizzo ai fini di fatturazione.',
    here: 'Il denominatore è quindi definito: ore di utilizzo cloud. Restano una grandezza composita — ore di calcolo, di archiviazione e di trasferimento sommate fra loro — e non sono l’utilizzo fatturato.',
  },
  {
    term: 'Riduzioni (o risparmi) di emissioni',
    definition:
      'Il volume di emissioni ridotte. Non include le compensazioni (carbon offset). Microsoft usa «riduzioni» e «risparmi» come sinonimi: entrambi descrivono il livello di emissioni dopo un’azione, quando quel livello è inferiore a quello proiettato in assenza dell’azione.',
    here: 'È la definizione a cui risponde la card «Emissioni evitate»: un confronto con uno scenario proiettato, non emissioni compensate.',
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
            Le definizioni sono di Microsoft, tradotte: sono loro a stabilire che cosa questi numeri
            possono affermare.
          </Typography>
        </Stack>

        <Grid container spacing={3} component="dl" sx={{ m: 0 }}>
          {TERMS.map(({ term, definition, here }) => (
            <Grid item xs={12} md={6} key={term}>
              <Typography variant="subtitle2" component="dt" fontWeight={700}>
                {term}
              </Typography>
              <Box component="dd" sx={{ m: 0, mt: 0.5 }}>
                <Typography variant="body2" color="text.secondary">
                  {definition}
                </Typography>
                {here && (
                  <Typography variant="caption" color="text.secondary" component="p" sx={{ mt: 1 }}>
                    <strong>Qui:</strong> {here}
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
          (Microsoft Learn, aggiornata al 7 ottobre 2025).
        </Typography>
      </CardContent>
    </Card>
  );
}
