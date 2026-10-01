import { Box, Container, IconButton, Stack, Tooltip, Typography } from '@mui/material';
import DarkModeIcon from '@mui/icons-material/DarkModeOutlined';
import LightModeIcon from '@mui/icons-material/LightModeOutlined';
import { ButtonNaked, LogoPagoPACompany, Tag } from '@pagopa/mui-italia';
import type { ColorMode } from '../theme';

export interface NavItem {
  /** Id of the section the item scrolls to. */
  id: string;
  label: string;
}

interface Props {
  mode: ColorMode;
  onToggleMode: () => void;
  nav: NavItem[];
}

/**
 * The two-tier header used across PagoPA sites: a slim company strip on top
 * (institutional logo, assistance, language) and the product bar underneath
 * (product name, tag, section nav).
 *
 * Sticky only from `md` up: on a phone the two rows stack, and a 150px sticky
 * block would eat a third of the viewport.
 */
export function SiteHeader({ mode, onToggleMode, nav }: Props) {
  return (
    <Box
      component="header"
      sx={{
        position: { xs: 'static', md: 'sticky' },
        top: 0,
        zIndex: (t) => t.zIndex.appBar,
        bgcolor: 'background.paper',
      }}
    >
      <Box sx={{ borderBottom: 1, borderColor: 'divider' }}>
        <Container maxWidth="lg">
          <Stack
            direction="row"
            alignItems="center"
            justifyContent="space-between"
            spacing={2}
            sx={{ minHeight: 48, py: 1 }}
          >
            <ButtonNaked
              component="a"
              href="https://www.pagopa.it/it/"
              target="_blank"
              rel="noopener noreferrer"
              aria-label="PagoPA S.p.A. — vai al sito istituzionale"
              sx={{ p: 0, minWidth: 0 }}
            >
              <LogoPagoPACompany
                size={110}
                color={mode === 'dark' ? 'light' : 'default'}
                title="PagoPA S.p.A."
              />
            </ButtonNaked>

            <Stack direction="row" alignItems="center" spacing={{ xs: 1, sm: 2 }}>
              {/* The dashboard exists in Italian only: a working switch would be
                  a control with nothing to switch to. */}
              <Typography variant="subtitle2" color="text.secondary" component="span">
                IT
              </Typography>
              <Tooltip title={mode === 'dark' ? 'Tema chiaro' : 'Tema scuro'}>
                <IconButton onClick={onToggleMode} aria-label="Cambia tema" size="small">
                  {mode === 'dark' ? <LightModeIcon /> : <DarkModeIcon />}
                </IconButton>
              </Tooltip>
            </Stack>
          </Stack>
        </Container>
      </Box>

      <Box
        sx={{
          borderBottom: 1,
          borderColor: 'divider',
          boxShadow: '0 2px 6px rgba(0, 43, 85, 0.06)',
        }}
      >
        <Container maxWidth="lg">
          <Stack
            direction={{ xs: 'column', md: 'row' }}
            alignItems={{ xs: 'flex-start', md: 'center' }}
            justifyContent="space-between"
            spacing={{ xs: 1, md: 2 }}
            sx={{ minHeight: 56, py: 1 }}
          >
            <Stack direction="row" alignItems="center" spacing={1.5}>
              <Typography variant="h6" component="p" fontWeight={700}>
                Carbon Dashboard
              </Typography>
              <Tag value="Open data" variant="info" />
            </Stack>

            <Stack
              component="nav"
              aria-label="Sezioni della pagina"
              direction="row"
              spacing={{ xs: 2, md: 3 }}
              sx={{
                maxWidth: '100%',
                overflowX: 'auto',
                scrollbarWidth: 'none',
                '&::-webkit-scrollbar': { display: 'none' },
              }}
            >
              {nav.map((item) => (
                <ButtonNaked
                  key={item.id}
                  component="a"
                  href={`#${item.id}`}
                  size="small"
                  sx={{ whiteSpace: 'nowrap', px: 0 }}
                >
                  {item.label}
                </ButtonNaked>
              ))}
            </Stack>
          </Stack>
        </Container>
      </Box>
    </Box>
  );
}
