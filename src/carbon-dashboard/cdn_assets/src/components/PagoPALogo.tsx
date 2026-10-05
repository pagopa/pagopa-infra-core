import { Box } from '@mui/material';
import logoUrl from '../assets/pagopa-logo.png';
import type { ColorMode } from '../theme';

/**
 * The pagoPA platform mark (public domain, Wikimedia Commons). It ships in
 * brand blue only, so on a dark surface it is rendered as a white silhouette.
 */
export function PagoPALogo({ mode, height = 32 }: { mode: ColorMode; height?: number }) {
  return (
    <Box
      component="img"
      src={logoUrl}
      alt="pagoPA"
      sx={{
        display: 'block',
        height,
        width: 'auto',
        filter: mode === 'dark' ? 'brightness(0) invert(1)' : 'none',
      }}
    />
  );
}
