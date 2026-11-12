import { Box, Container, Typography } from '@mui/material';
import { ButtonNaked, FooterLegal } from '@pagopa/mui-italia';
import type { ColorMode } from '../theme';
import { PagoPALogo } from './PagoPALogo';

const legalInfo = (
  <Typography variant="caption" component="span">
    <strong>PagoPA S.p.A.</strong> — società per azioni - capitale sociale di euro 1,000,000
    interamente versato - sede legale in Roma, Piazza Colonna 370, CAP 00187 - n. di iscrizione a
    Registro Imprese di Roma, CF e P.IVA 15376371009
  </Typography>
);

/**
 * The institutional footer reduced to its two fixed parts: the pagoPA mark and
 * the legal strip. The design system's link columns are deliberately absent —
 * this is one page, not an entry point into the product catalogue.
 */
export function SiteFooter({ mode }: { mode: ColorMode }) {
  return (
    <Box component="footer">
      <Box sx={{ bgcolor: 'background.paper', py: { xs: 3, md: 4 } }}>
        <Container maxWidth="lg">
          <ButtonNaked
            component="a"
            href="https://www.pagopa.gov.it/"
            target="_blank"
            rel="noopener noreferrer"
            aria-label="pagoPA — vai al sito della piattaforma"
            sx={{ p: 0, minWidth: 0 }}
          >
            <PagoPALogo mode={mode} />
          </ButtonNaked>
        </Container>
      </Box>
      <FooterLegal content={legalInfo} />
    </Box>
  );
}
