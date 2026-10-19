# Seraph Protocol — Brand Guidelines

## 1. Visual Theme

**Core aesthetic:** Black-on-white precision with a full-spectrum rainbow accent system — inspired by itsua.com's restrained monochrome base with vibrant, purposeful color pops. Think: a gallery where the walls are white, but the frames and labels sing.

## 2. Color Palette

### Monochrome Base
| Role | Hex | Usage |
|------|-----|-------|
| **Seraph Black** | `#111827` | Primary text, headings, section numbers |
| **Pure White** | `#ffffff` | Page background, card surfaces |
| **True White** | `#fafafa` | Subtle surface tint, inner shadow highlight |
| **Warm Gray** | `#6b7280` | Secondary text, descriptions |
| **Cool Gray** | `#9ca3af` | Tertiary text, muted links |
| **Border Gray** | `#e5e7eb` | Shadow-as-border, dividers |
| **Ring Gray** | `#d1d5db` | Input rings, tab borders |

### Rainbow Accents
Instead of a single accent color, Seraph uses a full spectrum — each color maps to a specific function or layer:

| Color | Hex | Layer / Function |
|-------|-----|-----------------|
| **Seraphim Red** | `#ef4444` | Base Layer (value settlement) |
| **Seraphim Orange** | `#f97316` | Bridge (cross-layer movement) |
| **Seraphim Amber** | `#f59e0b` | Stablecoin module |
| **Seraphim Yellow** | `#eab308` | AI Payments module |
| **Seraphim Green** | `#22c55e` | Messaging module |
| **Seraphim Teal** | `#06b6d4` | RWA module (future) |
| **Seraphim Blue** | `#3b82f6` | Governance / voting |
| **Seraphim Indigo** | `#6366f1` | Explorer / scanning |
| **Seraphim Violet** | `#a855f7` | Private Compute / ZK |
| **Seraphim Pink** | `#ec4899` | AI Agent payments |

### Shadow System (shadow-as-border philosophy)
- **Border shadow:** `rgba(0, 0, 0, 0.08) 0px 0px 0px 1px` — replaces traditional CSS borders
- **Card shadow:** `rgba(0,0,0,0.08) 0px 0px 0px 1px, rgba(0,0,0,0.04) 0px 2px 2px, #fafafa 0px 0px 0px 1px`
- **Focus ring:** `2px solid #3b82f6` (Seraphim Blue, WCAG-compliant)

## 3. Typography

### Font Family
- **Headings & Body:** `Inter`, system-ui, -apple-system, BlinkMacSystemFont, sans-serif
- **Monospace (code, tags, addresses):** `JetBrains Mono`, ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace

### Font Pair
```html
<link href="https://fonts.googleapis.com/css2?family=Inter:wght@300;400;500;600;700&family=JetBrains+Mono:wght@400;500;600&display=swap" rel="stylesheet">
```

### Hierarchy
| Role | Size (px) | Weight | Line Height | Letter-Spacing | Usage |
|------|-----------|--------|-------------|----------------|-------|
| Display | 48 | 700 | 1.05 | -1.5px | Hero headlines |
| H1 | 36 | 600 | 1.15 | -0.75px | Page headings |
| H2 | 28 | 600 | 1.2 | -0.5px | Section headings |
| H3 | 22 | 600 | 1.25 | -0.25px | Sub-sections |
| Body Large | 18 | 400 | 1.7 | normal | Intro paragraphs |
| Body | 16 | 400 | 1.6 | normal | Standard text |
| Small | 14 | 400 | 1.5 | normal | Secondary text |
| Caption | 12 | 500 | 1.4 | normal | Metadata, tags |
| Mono Caption | 12 | 600 | 1.0 | normal | Tech stack, uppercase |

### Principles
- Inter's variable font is used for all prose — clean, neutral, highly legible
- JetBrains Mono for all technical labels — ligatures on for `→`, `§`, code operators
- Monospace tags use `text-transform: uppercase` for tech stack labels (matching itsua.com)

## 4. Layout & Spacing

### Grid
- Max content width: 1200px
- Base unit: 8px
- Section padding: 120px vertical (desktop), 64px (mobile)
- Gutters: 32px between columns
- Cards: 3-column grid on desktop, 1-column stacked on mobile

### Section Pattern (inspired by itsua.com)
```
§ 01 — SECTION TITLE

  Large heading (H1)
  Subheading (Body Large)
  [→Action link]

  Content grid...
```

## 5. Logo & Marks

### Primary Logo
- Wordmark: "SERAPH" in Inter Bold, letter-spacing -1.5px
- No tagline at large sizes; tagline "The Privacy Continuum Protocol" only in footer

### Icon
- An abstract "S" formed by two converging strokes — evoking wings and cryptographic proof circuits
- Negative space creates a shield shape (privacy)
- Convergence point highlighted with a gradient from Seraphim Violet to Seraphim Blue

### Clear Space
- Minimum clear space = 1× the height of the "S" icon
- Never place on busy backgrounds

## 6. Component Library

### Buttons
- **Primary CTA:** Black background (`#111827`), white text, 6px radius, 12px 24px padding
- **Secondary:** White background, black text, shadow-border, 6px radius
- **Rainbow Badge:** Full spectrum used in tech-stack labels and module tags

### Cards
- White background, no CSS border (shadow-as-border technique)
- 8px radius, multi-layer shadow stack
- Hover: shadow intensifies slightly
- Image cards: 12px top radius, `1px solid #e5e7eb` border

### Tags / Badges
- Tech stack tags: JetBrains Mono 12px, uppercase, 500 weight, 9999px radius
- Module tags: Colored by module (red for base, orange for bridge, green for messaging, etc.)
- Status badges: Rainbow gradient pill, 9999px radius

### Navigation
- Clean horizontal nav on white, sticky
- Links: Inter 14px medium, `#111827` text
- Active: color changes to corresponding rainbow accent
- Section-numbered links (§ 00, § 01, etc.)

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
