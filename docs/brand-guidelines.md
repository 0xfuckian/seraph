# Seraph Protocol — Brand Guidelines

## 1. Visual Theme

**Core aesthetic:** Black-on-white precision with a full-spectrum palette — inspired by itsua.com's restrained monochrome base with one vibrant accent color per section. A gallery where the walls are stark white/black, but each exhibit is framed in its own functional color.

**The rainbow is functional, not decorative.** Each color maps to a specific protocol layer or module. No gradients, no random color pops. One accent per block.

## 2. Color Palette

### Monochrome Base

| Role | Hex | CSS Variable | Usage |
|------|-----|-------------|-------|
| **Seraph Ink** | `#0e1012` | `--color-ink` | Primary text, headings, deck brand labels |
| **Pure White** | `#ffffff` | `--color-white` | Page background, card surfaces |
| **Seraph Paper** | `#f5f5f3` | `--color-paper` | Soft surface tint (inner content) |
| **Sub Text** | `#60636a` | `--color-sub` | Secondary text, descriptions, `meta` labels |
| **Line** | `#d9dadd` | `--color-line` | Borders, dividers, deck card borders |

### Functional Accent Colors (the full spectrum)

Each color has three variants: **Soft** (background wash for cards/blocks), **Solid** (text on white, link on gray), **Bright** (highlights, active states).

| Layer / Module | Soft (bg) | Solid (text) | Bright | CSS Variable |
|----------------|-----------|-------------|--------|-------------|
| **Base Layer** | `#fdecec` | `#a21caf` | — | `--color-red-soft`, `--text-magenta` |
| **Bridge** | `#fff2e5` | `#b45309` | — | `--color-orange-soft`, `--color-orange` |
| **Stablecoin** | `#fcfdec` | `#0e1012` | — | `--color-yellow-soft`, `--color-ink` |
| **AI Payments** | `#e6f7f1` | `#047857` | `#34d399` | `--color-green-soft`, `--color-green`, `--color-green-bright` |
| **Messaging** | `#fbeefc` | `#a21caf` | — | `--color-magenta-soft`, `--color-magenta` |
| **Private Compute** | `#eef1ff` | `#2f4cff` | — | `--color-blue-soft`, `--color-accent` |
| **Governance** | `#f5f5f3` | `#0e1012` | — | `--color-paper`, `--color-ink` |
| **Explorer** | `#eeeef0` | `#0e1012` | — | `--color-ink-soft`, `--color-ink` |

### Shadow System (shadow-as-border philosophy)

itsua.com replaces CSS borders with `box-shadow`:
- **Line shadow:** `rgba(217, 218, 221, 1) 0px 0px 0px 1px` — replaces `border: 1px solid`
- **Card shadow:** `rgba(0,0,0,0.08) 0px 0px 0px 1px, rgba(0,0,0,0.04) 0px 2px 2px, #f5f5f3 0px 0px 0px 1px`
- **Hover intensify:** `rgba(0,0,0,0.10) 0px 0px 0px 1px, rgba(0,0,0,0.06) 0px 4px 8px, #f5f5f3 0px 0px 0px 1px`

## 3. Typography

### Font Family

| Role | Font | Source |
|------|------|--------|
| **Headings & Body** | **Space Grotesk** (400, 500, 600, 700) | Google Fonts / local woff2 |
| **Monospace** | **JetBrains Mono** (400, 500, 600, 700) | Google Fonts / local woff2 |

Fallback chain: Space Grotesk → system UI sans-serif. JetBrains Mono → Monaco → monospace.

```html
<link href="https://fonts.googleapis.com/css2?family=Space+Grotesk:wght@400;500;600;700&family=JetBrains+Mono:wght@400;500;600;700&display=swap" rel="stylesheet">
```

### Font Pairing

Space Grotesk handles all prose (headlines, body, stats). JetBrains Mono handles all structural elements: section labels (`§ 00`), tech tags, nav, specs.

The itsua.com `meta` class is the typographic anchor: `font-mono, 11px, 500 weight, uppercase, letter-spacing +0.02em, color: var(--color-sub)`.

### Hierarchy

| Role | Size (px) | Size (desktop) | Weight | Line Height | Letter-Spacing | Font | Usage |
|------|-----------|----------------|--------|-------------|----------------|------|-------|
| Display | 48–120 | 500 | 0.94 | -0.04em | Space Grotesk | Hero headlines (48px mobile → 120px desktop) |
| H1 | 44–72 | 500 | 0.95 | -0.03em | Space Grotesk | Section titles (44px mobile → 72px desktop) |
| H2 | 28 | 48 | 500 | 1.0 | -0.02em | Space Grotesk | Subsection headings |
| H3 | 18 | 24 | 500 | 1.15 | -0.01em | Space Grotesk | Card titles |
| Body | 16 | 20 | 400 | 1.6–1.7 | normal | Space Grotesk | Paragraphs |
| Meta / Spec label | 11–12 | 11–12 | 500 | 1.0 | +0.02em | JetBrains Mono | `§ 00` labels, spec tags |
| Tech tag | 10–11 | 11 | 600 | — | +0.02em | JetBrains Mono | Stack badges (uppercase) |
| Caption | 10–12 | 12 | — | 1.35 | normal | Space Grotesk | Descriptions |
| Stat number | 32–80 | 56–80 | 500 | 0.92–0.96 | -0.02em | Space Grotesk | Big numbers in stats grid (32px mobile → 56px tablet → 56px desktop) |

### Principles

- **Space Grotesk** is the sole body font — geometric, clean, neutral, highly legible at all sizes
- **JetBrains Mono** exclusively for structural/monospace elements — section numbering, tech stack, key-value specs
- Negative letter-spacing on display/type (down to -0.04em) for tight, impactful headlines
- `meta` labels use monospace + positive tracking to distinguish structure from content

## 4. Layout & Spacing

### Grid
- Max content width: 1200px (desktop), 24px horizontal padding (mobile → 56px desktop)
- Base unit: 4px (spacing increments of 4px)
- Section padding: 80px vertical (desktop), 48–64px (mobile)
- Cards use `box-shadow` instead of CSS `border` (shadow-as-border)

### Section Pattern (matching itsua.com)

```
§ 01 — SECTION TITLE

  [meta label]
  Large heading (H1, 72px desktop)
  Subheading (Body, secondary color)
  [→Action link]

  Content grid...
```

### Stats Grid

```
┌──────┬──────┬──────┬──────┐
│  100M   4     2     ∞   │
│  Max   Levels EVMs  Anonymity │
│  Supply           Set   │
└──────┴──────┴──────┴──────┘
```

Large numbers (56–120px), uppercase labels in monospace at 11px, centered grid.

### Deck Card Pattern (for modules/layers/projects)

Each card is a white-background deck with colored text elements:
- **Brand row:** `SERAPH` label + colored badge dot (magenta for BASE, accent for EVM.01, green for EVM.02)
- **Name:** Layer/module name in Space Grotesk
- **Domain:** Colored per layer — `text-magenta`, `text-accent`, `text-green` — in JetBrains Mono uppercase
- **Tech tags:** Light chips on `color-ink-soft` background
- **Result:** Colored per layer (same color as domain) in Space Grotesk
- Box shadow instead of borders, sharp edges (no border-radius)

### Navigation

```
┌[ SERAPH ] INDEX  ARCHITECTURE  MODULES  DOCS  GOVERNANCE  [ ACCEPTING NEW WORK ]┐
```

- Sticky top bar, `font-mono text-[12px]`
- Left: logo + bracketed section numbers `[ 00 ] INDEX`
- Right: status indicator (green dot + "ACCEPTING NEW WORK")
- Section links use `font-mono` with bracket numbering

### Section Markers

- `§ 00 — TITLE` format, `font-mono, 11px, uppercase, letter-spacing +0.02em, color: var(--color-sub)`
- Each major section starts with this pattern
- Works on both web and docs

## 5. Logo & Marks

### Primary Logo

- Wordmark: "SERAPH" in Space Grotesk Bold, letter-spacing -0.04em
- The dot on "SERAPH." uses `--color-accent` (electric blue `#2f4cff`)
- No tagline at large sizes; tagline "The Privacy Continuum Protocol" only in footer

### Icon

- An abstract "S" formed by two converging strokes — evoking wings (seraphim) and cryptographic proof circuits
- Negative space creates a shield shape (privacy)
- Convergence point highlighted with `--color-accent` (single color, no gradient)

### Clear Space

- Minimum clear space = 1× the height of the logo text
- Never place on colored or busy backgrounds — always on white

## 6. Component Library

### Buttons

- **Primary CTA (split):** Electric blue arrow (`bg-accent`, white `→`) + black label box (`bg-ink`, white text), `font-mono, 12px`
- **Secondary CTA:** White background, `--color-ink` text, `box-shadow: var(--color-line)` as border
- **Color-accent CTA:** `--color-accent` background (`#2f4cff`), white text

### Cards

- White background, NO CSS border (shadow-as-border technique)
- `box-shadow: var(--color-line) 0px 0px 0px 1px, rgba(0,0,0,0.04) 0px 2px 2px, var(--color-paper) 0px 0px 0px 1px`
- Colored text elements per layer (magenta for BASE, accent for EVM.01, green for EVM.02)
- Sharp edges (no border-radius)

### Tags / Badges

- **Tech stack tags:** JetBrains Mono 11px, uppercase, 600 weight, `letter-spacing: +0.02em`, 9999px radius, `bg-ink-soft` background
- **Layer/tags:** Colored by module — soft background wash + solid text color matching the color system
- **Spec labels:** `font-mono, 12px, 500 weight, color: var(--color-sub)`

### Navigation Items

- `font-mono, 12px, tracking +0.02em`
- Bracketed section numbers: `[ 00 ]` then `INDEX`
- Active: uses accent color of the current section
- Status indicator: green dot (`●`) + colored text

## 7. Tone of Voice

| Attribute | Description |
|-----------|-------------|
| **Precise** | Technical accuracy; no fluff |
| **Confident** | We built something that works |
| **Accessible** | Complex ideas explained simply |
| **Aspirational** | Privacy as a right, not a privilege |

### Writing Principles

- Lead with the outcome, not the feature
- Use active voice
- Technical terms are fine, but explain them once
- No corporate jargon ("synergy," "leverage," "holistic")
- Section numbering follows `§ NN — TITLE` pattern throughout docs and site