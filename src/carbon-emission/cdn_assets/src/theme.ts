import { createTheme, type Theme } from '@mui/material/styles';
import { theme as lightTheme, darkTheme } from '@pagopa/mui-italia';

export type ColorMode = 'light' | 'dark';

/**
 * Brand chrome, taken from the `mui-italia` colour tokens rather than picked by
 * eye: `blue.500`, `blueitalia.500`, `turquoise.500`. These are constants, not
 * palette slots — the hero band keeps the same deep blue in both colour modes,
 * the way the bands on pagopa.it and developer.pagopa.it do.
 */
export const brand = {
  blue: '#0B3EE3',
  blueItalia: '#0066CC',
  turquoise: '#00C5CA',
  heroGradient: 'linear-gradient(135deg, #0B3EE3 0%, #0066CC 52%, #00C5CA 135%)',
} as const;

/** Card chrome shared by every boxed module, so the page reads as one system. */
export const cardSx = {
  border: 1,
  borderColor: 'divider',
  borderRadius: 2,
  height: '100%',
  boxShadow: '0 4px 12px rgba(0, 43, 85, 0.06)',
} as const;

const siteComponents = {
  MuiCard: { styleOverrides: { root: { borderRadius: 8 } } },
  MuiContainer: { styleOverrides: { root: { paddingLeft: 16, paddingRight: 16 } } },
};

/**
 * `mui-italia`'s `darkTheme` only flips `mode`, `primary` and
 * `background.paper`: because it is built on top of the finished light theme,
 * the explicit light values for text, divider and `background.default` survive
 * the merge, and MUI's dark defaults never kick in. That leaves navy text on a
 * near-black surface. These are the values that band alternation and body copy
 * need in order to be readable at all, so they are set here rather than worked
 * around at each call site.
 */
const DARK_PALETTE = {
  background: { default: '#15161A', paper: '#252525' },
  text: { primary: '#FFFFFF', secondary: '#BBC2D6', disabled: '#99A3C1' },
  divider: 'rgba(255, 255, 255, 0.16)',
  action: {
    active: '#BBC2D6',
    hover: 'rgba(255, 255, 255, 0.08)',
    selected: 'rgba(255, 255, 255, 0.12)',
    disabled: 'rgba(255, 255, 255, 0.3)',
    disabledBackground: 'rgba(255, 255, 255, 0.12)',
    focus: 'rgba(255, 255, 255, 0.12)',
  },
};

/**
 * Same story on the ink side. `mui-italia` sets `typography.allVariants.color`
 * to the light `#17324D`, and MUI spreads `allVariants` into every variant when
 * the theme is built — so by the time we get the theme, each variant carries
 * that literal and `palette.text.primary` no longer reaches any of them. The
 * variants have to be re-inked one by one; a `MuiTypography` style override
 * would win over the `color` prop at call sites, which is worse.
 */
const WHITE_INK = { color: '#FFFFFF' };
const DARK_TYPOGRAPHY = {
  headline: WHITE_INK,
  h1: WHITE_INK,
  h2: WHITE_INK,
  h3: WHITE_INK,
  h4: WHITE_INK,
  h5: WHITE_INK,
  h6: WHITE_INK,
  subtitle1: WHITE_INK,
  subtitle2: WHITE_INK,
  body1: WHITE_INK,
  body2: WHITE_INK,
  caption: WHITE_INK,
  overline: WHITE_INK,
  sidenav: WHITE_INK,
  monospaced: WHITE_INK,
};

const DARK_COMPONENTS = {
  ...siteComponents,
  MuiButton: {
    styleOverrides: {
      root: {
        '&.MuiButton-naked.MuiButton-colorText': {
          color: '#FFFFFF',
          '&:hover': { color: 'rgba(255, 255, 255, 0.8)' },
        },
      },
    },
  },
  // Alerts carry the same literal, on a surface MUI darkens for dark mode.
  MuiAlert: {
    styleOverrides: {
      root: { color: '#FFFFFF' },
      standard: { '& .MuiAlert-icon': { color: '#FFFFFF' } },
    },
  },
};

/**
 * The PagoPA theme with the site-level overrides this dashboard needs. Built
 * once per mode: `createTheme` on every render would throw away the
 * memoisation MUI relies on for its style cache.
 */
const LIGHT = createTheme(lightTheme, { components: siteComponents });
const DARK = createTheme(darkTheme, {
  components: DARK_COMPONENTS,
  palette: DARK_PALETTE,
  typography: DARK_TYPOGRAPHY,
});

export const muiTheme = (mode: ColorMode): Theme => (mode === 'dark' ? DARK : LIGHT);

/**
 * Chart colours.
 *
 * These are the validated default data-viz slots, not the PagoPA brand hues.
 * Brand blue drives the UI chrome through `mui-italia`; data marks use a
 * palette whose colour-vision-deficiency separation has been checked across all
 * pairs. Swapping brand hues in here means re-running the palette validator
 * first (README §3).
 *
 * The dark column is the same three hues re-stepped for a dark surface — it is
 * a selected palette, not an automatic inversion.
 */
export interface ChartPalette {
  /** Actual emissions. The entity keeps this hue in every chart. */
  emissions: string;
  /** Normalized usage, and the counterfactual derived from it. */
  usage: string;
  /** Carbon intensity, always shown as an index. */
  intensity: string;
  grid: string;
  axis: string;
  surface: string;
  textPrimary: string;
  textSecondary: string;
}

const LIGHT_CHART: ChartPalette = {
  emissions: '#2a78d6',
  usage: '#eb6834',
  intensity: '#1baf7a',
  grid: '#e6e5e1',
  axis: '#c8c7c1',
  surface: '#ffffff',
  textPrimary: '#17324d',
  textSecondary: '#5c6f82',
};

const DARK_CHART: ChartPalette = {
  emissions: '#3987e5',
  usage: '#d95926',
  intensity: '#199e70',
  grid: '#33332f',
  axis: '#4a4a45',
  surface: '#252525',
  textPrimary: '#ffffff',
  textSecondary: '#c3c2b7',
};

export const chartPalette = (mode: ColorMode): ChartPalette =>
  mode === 'dark' ? DARK_CHART : LIGHT_CHART;
