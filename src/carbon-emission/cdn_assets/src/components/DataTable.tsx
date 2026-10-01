import {
  Accordion,
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
import { formatIndex, formatMass, formatMonthLong, formatPercent } from '../lib/format';

/**
 * The numbers behind the charts. Required, not optional: it is what keeps
 * series identity and value from ever depending on colour alone.
 */
export function DataTable({ points, unit }: { points: ChartPoint[]; unit: string }) {
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
        {/* Tables are the one element allowed to scroll horizontally. */}
        <TableContainer sx={{ overflowX: 'auto' }}>
          <Table size="small">
            <TableHead>
              <TableRow>
                <TableCell>Mese</TableCell>
                <TableCell align="right">Emissioni ({unit})</TableCell>
                <TableCell align="right">Var. mese su mese</TableCell>
                <TableCell align="right">Ore di utilizzo (indice)</TableCell>
                <TableCell align="right">Intensità (indice)</TableCell>
              </TableRow>
            </TableHead>
            <TableBody>
              {points.map((p, i) => {
                // Recomputed here too — never read back from the API's own
                // month-over-month fields (README §1.6).
                const prev = i > 0 ? points[i - 1].emissions : null;
                const mom = prev && prev > 0 ? p.emissions / prev - 1 : null;
                return (
                  <TableRow key={p.date} hover>
                    <TableCell>{formatMonthLong(p.date)}</TableCell>
                    <TableCell align="right">{formatMass(p.emissions)}</TableCell>
                    <TableCell align="right">{mom === null ? '—' : formatPercent(mom)}</TableCell>
                    <TableCell align="right">{formatIndex(p.usageIndex)}</TableCell>
                    <TableCell align="right">{formatIndex(p.intensityIndex)}</TableCell>
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
