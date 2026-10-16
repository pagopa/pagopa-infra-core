import { Box, Container, Stack, Typography } from '@mui/material';
import type { ReactNode } from 'react';

interface Props {
  id: string;
  overline: string;
  title: string;
  subtitle?: string;
  /**
   * Paper band instead of the page ground. Reserved for sections made of
   * plain text: a section full of cards needs the ground to stay darker than
   * the cards, or the cards lose their edge.
   */
  tinted?: boolean;
  children: ReactNode;
}

export function Section({ id, overline, title, subtitle, tinted = false, children }: Props) {
  return (
    <Box
      component="section"
      id={id}
      aria-labelledby={`${id}-title`}
      sx={{
        bgcolor: tinted ? 'background.paper' : 'background.default',
        py: { xs: 4, md: 7 },
        // Clears the sticky header when a nav anchor jumps here.
        scrollMarginTop: { xs: 0, md: '112px' },
      }}
    >
      <Container maxWidth="lg">
        <Stack spacing={1} sx={{ mb: { xs: 3, md: 4 } }}>
          <Typography variant="overline" color="primary.main">
            {overline}
          </Typography>
          <Typography id={`${id}-title`} variant="h4" component="h2" fontWeight={700}>
            {title}
          </Typography>
          {subtitle && (
            <Typography variant="body1" color="text.secondary" sx={{ maxWidth: '75ch' }}>
              {subtitle}
            </Typography>
          )}
        </Stack>
        {children}
      </Container>
    </Box>
  );
}
