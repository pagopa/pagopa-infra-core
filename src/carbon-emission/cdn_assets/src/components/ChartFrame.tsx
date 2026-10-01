import { Box, Card, CardContent, Stack, Typography } from '@mui/material';
import type { ReactNode } from 'react';
import { cardSx } from '../theme';

interface Props {
  title: string;
  subtitle?: string;
  footnote?: ReactNode;
  /** Plot height in px. The card grows to fit the axis band beneath it. */
  height?: number;
  children: ReactNode;
}

export function ChartFrame({ title, subtitle, footnote, height = 300, children }: Props) {
  return (
    <Card elevation={0} sx={cardSx}>
      <CardContent sx={{ p: { xs: 2, md: 3 } }}>
        <Stack spacing={0.5} mb={2}>
          <Typography variant="h6" component="h2">
            {title}
          </Typography>
          {subtitle && (
            <Typography variant="body2" color="text.secondary">
              {subtitle}
            </Typography>
          )}
        </Stack>
        {/* Height lives on this box, not on the card, so x-axis labels are
            inside the card rather than causing a nested scrollbar. */}
        <Box sx={{ width: '100%', height }}>{children}</Box>
        {footnote && (
          <Typography variant="caption" color="text.secondary" component="p" sx={{ mt: 2 }}>
            {footnote}
          </Typography>
        )}
      </CardContent>
    </Card>
  );
}
