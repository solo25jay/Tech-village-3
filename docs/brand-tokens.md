# Tech Village brand tokens

Sampled from the supplied logo. Tokens live in `src/style.css` as CSS variables and are mapped in `tailwind.config.ts`.

| Token | Light | Dark | Use |
|---|---|---|---|
| navy | #0B1D5B | #E8EEFF | Wordmark, headings accents |
| brand | #1F5BFF | #5B8CFF | Primary buttons, links |
| cyan | #22D3EE | #22D3EE | Decorative only on light; text via cyan-text |
| cyan-text | #077A9E | #22D3EE | Text/icons on light surfaces |
| mint | #34E3A0 | #34E3A0 | Success accents, decorative |
| mint-text | #067A55 | #34E3A0 | Text on light surfaces |
| violet | #6A2EE0 | #9B7BFF | Secondary accent |
| surface | #F6F8FD | #070D1F | Page background |
| raised | #FFFFFF | #0E1730 | Cards, panels |

## Contrast (WCAG 2.x)

| Pair | Ratio | Result |
|---|---|---|
| brand #1F5BFF on white | 5.25 | AA |
| navy #0B1D5B on white | 15.66 | AAA |
| violet #6A2EE0 on white | 6.82 | AA |
| cyan-text #077A9E on white | 4.90 | AA |
| mint-text #067A55 on white | 5.35 | AA |
| muted #5B6B95 on surface #F6F8FD | 4.96 | AA |
| ink #E8EEFF on dark surface | 16.67 | AAA |
| brand #5B8CFF on dark surface | 6.11 | AA |
| muted #93A3CF on dark surface | 7.71 | AAA |

The raw logo cyan (#0A8FB8-ish) and green (#0B8F63-ish) fail 4.5:1 as text on white, which is why the darker `-text` variants exist. Use the bright versions for fills, dots and icons only.

## Logo notes
- `logo-on-white.jpeg` and `logo-on-black.jpeg` are the supplied raster files. On black, the navy "TECH" and the tagline are nearly invisible, so the app uses the house mark only (`mark-on-white.png`, `mark-on-black.png`) beside live text in the brand fonts.
- Ask the designer for an SVG with a transparent background and a light-text variant. Swap them into `BrandLogo.vue` when available.
