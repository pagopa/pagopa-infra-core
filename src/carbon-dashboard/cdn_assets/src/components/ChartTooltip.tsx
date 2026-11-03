import { Box, Divider, Stack, Typography } from '@mui/material';
import { formatMonthLong } from '../lib/format';

export interface TooltipRow {
  dataKey: string;
  name: string;
  color: string;
  value: number;
}

interface RechartsTooltipProps {
  active?: boolean;
  label?: string | number;
  payload?: Array<{ dataKey?: string | number; name?: string; color?: string; value?: number }>;
  /** Per-series value formatting, keyed by dataKey. */
  format: (dataKey: string, value: number) => string;
}

export function ChartTooltip({ active, label, payload, format }: RechartsTooltipProps) {
  if (!active || !payload?.length || typeof label !== 'string') return null;

  const rows = payload.filter(
    (p): p is { dataKey: string; name: string; color: string; value: number } =>
      typeof p.value === 'number' && Number.isFinite(p.value) && typeof p.dataKey === 'string',
  );
  if (rows.length === 0) return null;

  return (
    <Box
      sx={{
        bgcolor: 'background.paper',
        border: 1,
        borderColor: 'divider',
        borderRadius: 1,
        boxShadow: 3,
        px: 1.5,
        py: 1,
        minWidth: 180,
      }}
    >
      <Typography variant="caption" fontWeight={600} color="text.primary">
        {formatMonthLong(label)}
      </Typography>
      <Divider sx={{ my: 0.75 }} />
      <Stack spacing={0.5}>
        {rows.map((row) => (
          <Stack key={row.dataKey} direction="row" alignItems="center" spacing={1}>
            <Box
              sx={{
                width: 10,
                height: 10,
                borderRadius: '2px',
                bgcolor: row.color,
                flexShrink: 0,
              }}
            />
            {/* Labels and values wear text tokens; the swatch carries identity. */}
            <Typography variant="caption" color="text.secondary" sx={{ flexGrow: 1 }}>
              {row.name}
            </Typography>
            <Typography variant="caption" color="text.primary" fontWeight={600}>
              {format(row.dataKey, row.value)}
            </Typography>
          </Stack>
        ))}
      </Stack>
    </Box>
  );
}
