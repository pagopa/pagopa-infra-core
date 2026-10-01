import { Box, Container, Typography } from '@mui/material';
import { ButtonNaked, FooterLegal, LogoPagoPACompany } from '@pagopa/mui-italia';
import type { ColorMode } from '../theme';

const legalInfo = (
  <Typography variant="caption" component="span">
    <strong>PagoPA S.p.A.</strong> — società per azioni - capitale sociale di euro 1,000,000
    interamente versato - sede legale in Roma, Piazza Colonna 370, CAP 00187 - n. di iscrizione a
    Registro Imprese di Roma, CF e P.IVA 15376371009
  </Typography>
);

/**
 * The institutional footer reduced to its two fixed parts: the company mark and
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
        </Container>
      </Box>
      <FooterLegal content={legalInfo} />
    </Box>
  );
}
