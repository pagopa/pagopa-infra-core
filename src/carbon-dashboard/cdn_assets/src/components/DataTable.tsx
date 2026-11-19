import {
  Accordion,
  Box,
  AccordionDetails,
  AccordionSummary,
  Table,
  TableBody,
  TableCell,
  TableContainer,
  TableHead,
  TableRow,
  Typography,
} from '@mui/material';
import ExpandMoreIcon from '@mui/icons-material/ExpandMore';
import type { ChartPoint } from '../lib/carbon';
import { cardSx } from '../theme';
import {
  formatDateTime,
  formatIndex,
  formatMass,
  formatMonth,
  formatMonthLong,
  formatPercent,
  toMonth,
} from '../lib/format';

/**
 * The numbers behind the charts. Required, not optional: it is what keeps
 * series identity and value from ever depending on colour alone.
 */
export function DataTable({
  points,
  unit,
  baseDate,
}: {
  points: ChartPoint[];
  unit: string;
  /** Reference month of the index columns (value 100). */
  baseDate: string;
}) {
  // The parenthesis never wraps, so the month is never split from its year.
  const base = (
    <Box component="span" sx={{ whiteSpace: 'nowrap' }}>
      (base 100 = {formatMonth(baseDate)})
    </Box>
  );
  return (
    <Accordion
      elevation={0}
      defaultExpanded
      sx={{ ...cardSx, height: 'auto', '&:before': { display: 'none' } }}
    >
      <AccordionSummary expandIcon={<ExpandMoreIcon />}>
        <Typography variant="subtitle2">Tabella dei dati ({points.length} mesi)</Typography>
      </AccordionSummary>
      <AccordionDetails sx={{ p: 0 }}>
        <Typography
          variant="body2"
          color="text.secondary"
          component="p"
          sx={{ px: 2, pb: 2, maxWidth: '75ch' }}
        >
          La variazione sul mese precedente si riferisce alle emissioni. Ore di utilizzo e
          intensità di carbonio sono espresse come indice: il mese di riferimento,{' '}
          {formatMonthLong(baseDate)}, vale 100 e gli altri mesi sono in proporzione (120 vuol dire
          +20% rispetto {toMonth(formatMonthLong(baseDate))}, 80 vuol dire -20%).
        </Typography>
        {/* Tables are the one element allowed to scroll horizontally. */}
        <TableContainer sx={{ overflowX: 'auto' }}>
          <Table size="small">
            <TableHead>
              <TableRow>
                <TableCell>Mese</TableCell>
                <TableCell align="center">Emissioni ({unit})</TableCell>
                <TableCell align="center">Emissioni, var. sul mese precedente</TableCell>
                <TableCell align="center">Ore di utilizzo {base}</TableCell>
                <TableCell align="center">Intensità di carbonio {base}</TableCell>
                <TableCell align="center">Aggiornato da Azure il</TableCell>
              </TableRow>
            </TableHead>
            <TableBody>
              {points.map((p, i) => {
                // Recomputed here too — never read back from the API's own
                // month-over-month fields.
                const prev = i > 0 ? points[i - 1].emissions : null;
                const mom = prev && prev > 0 ? p.emissions / prev - 1 : null;
                return (
                  <TableRow key={p.date} hover>
                    <TableCell sx={{ whiteSpace: 'nowrap' }}>{formatMonthLong(p.date)}</TableCell>
                    <TableCell align="center">{formatMass(p.emissions)}</TableCell>
                    <TableCell align="center">{mom === null ? '—' : formatPercent(mom)}</TableCell>
                    <TableCell align="center">{formatIndex(p.usageIndex)}</TableCell>
                    <TableCell align="center">{formatIndex(p.intensityIndex)}</TableCell>
                    <TableCell align="center" sx={{ whiteSpace: 'nowrap' }}>
                      {p.retrievedAt ? formatDateTime(p.retrievedAt) : '—'}
                    </TableCell>
                  </TableRow>
                );
              })}
            </TableBody>
          </Table>
        </TableContainer>
      </AccordionDetails>
    </Accordion>
  );
}
