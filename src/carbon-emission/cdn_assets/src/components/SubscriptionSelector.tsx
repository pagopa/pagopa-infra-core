import { MenuItem, Stack, TextField, Typography } from '@mui/material';
import type { ManifestSubscription } from '../types';
import { ALL_SUBSCRIPTIONS } from '../lib/carbon';

interface Props {
  subscriptions: ManifestSubscription[];
  value: string;
  onChange: (slug: string) => void;
  dataThrough?: string;
}

export function SubscriptionSelector({ subscriptions, value, onChange, dataThrough }: Props) {
  return (
    <Stack
      direction={{ xs: 'column', sm: 'row' }}
      spacing={2}
      alignItems={{ xs: 'stretch', sm: 'center' }}
      justifyContent="space-between"
    >
      <TextField
        select
        size="small"
        label="Sottoscrizione"
        value={value}
        onChange={(e) => onChange(e.target.value)}
        sx={{ minWidth: 280 }}
      >
        <MenuItem value={ALL_SUBSCRIPTIONS}>Tutte le sottoscrizioni</MenuItem>
        {subscriptions.map((sub) => (
          <MenuItem key={sub.slug} value={sub.slug}>
            {sub.name}
          </MenuItem>
        ))}
      </TextField>

      {/* Emissions data lands only after the 19th of each month; saying so
          stops the newest month's absence from looking like a bug. */}
      {dataThrough && (
        <Typography variant="body2" color="text.secondary">
          Dati aggiornati a <strong>{dataThrough}</strong>
        </Typography>
      )}
    </Stack>
  );
}
