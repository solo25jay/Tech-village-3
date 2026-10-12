import type { Config } from 'tailwindcss'

// Colours point at CSS variables (see src/style.css) so light/dark and,
// later, per-tenant white-label branding can swap values without touching components.
const v = (name: string) => `rgb(var(--tv-${name}) / <alpha-value>)`

export default {
  content: ['./index.html', './src/**/*.{vue,ts}'],
  darkMode: 'class',
  theme: {
    extend: {
      colors: {
        // Neutrals with a cool blue undertone, taken from the logo's navy
        surface: v('surface'),
        raised: v('raised'),
        sunken: v('sunken'),
        line: v('line'),
        ink: v('ink'),
        muted: v('muted'),
        // Brand
        navy: v('navy'),
        brand: { DEFAULT: v('brand'), strong: v('brand-strong'), soft: v('brand-soft'), on: v('brand-on') },
        cyan: { DEFAULT: v('cyan'), text: v('cyan-text') },
        mint: { DEFAULT: v('mint'), text: v('mint-text') },
        violet: { DEFAULT: v('violet') },
        // Status
        danger: { DEFAULT: v('danger'), soft: v('danger-soft') },
        warn: { DEFAULT: v('warn'), soft: v('warn-soft') },
      },
      fontFamily: {
        display: ['Sora', 'ui-sans-serif', 'system-ui', 'sans-serif'],
        sans: ['Figtree', 'ui-sans-serif', 'system-ui', 'sans-serif'],
      },
      borderRadius: { control: '0.625rem', panel: '1rem' },
      boxShadow: {
        panel: '0 1px 2px rgb(var(--tv-navy) / 0.06), 0 8px 24px -12px rgb(var(--tv-navy) / 0.18)',
      },
      maxWidth: { prose: '68ch' },
    },
  },
} satisfies Config
