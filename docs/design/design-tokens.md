---
name: Mechanical Precision
colors:
  surface: '#fff8f6'
  surface-dim: '#f0d4ca'
  surface-bright: '#fff8f6'
  surface-container-lowest: '#ffffff'
  surface-container-low: '#fff1ec'
  surface-container: '#ffe9e2'
  surface-container-high: '#fee2d8'
  surface-container-highest: '#f8ddd2'
  on-surface: '#271812'
  on-surface-variant: '#5a4136'
  inverse-surface: '#3d2d26'
  inverse-on-surface: '#ffede7'
  outline: '#8e7164'
  outline-variant: '#e3bfb1'
  surface-tint: '#a33e00'
  primary: '#a33e00'
  on-primary: '#ffffff'
  primary-container: '#ff6500'
  on-primary-container: '#551d00'
  inverse-primary: '#ffb596'
  secondary: '#555f6f'
  on-secondary: '#ffffff'
  secondary-container: '#d6e0f3'
  on-secondary-container: '#596373'
  tertiary: '#006e2f'
  on-tertiary: '#ffffff'
  tertiary-container: '#00ad4e'
  on-tertiary-container: '#003714'
  error: '#ba1a1a'
  on-error: '#ffffff'
  error-container: '#ffdad6'
  on-error-container: '#93000a'
  primary-fixed: '#ffdbcd'
  primary-fixed-dim: '#ffb596'
  on-primary-fixed: '#360f00'
  on-primary-fixed-variant: '#7d2d00'
  secondary-fixed: '#d9e3f6'
  secondary-fixed-dim: '#bdc7d9'
  on-secondary-fixed: '#121c2a'
  on-secondary-fixed-variant: '#3d4756'
  tertiary-fixed: '#6bff8f'
  tertiary-fixed-dim: '#4ae176'
  on-tertiary-fixed: '#002109'
  on-tertiary-fixed-variant: '#005321'
  background: '#fff8f6'
  on-background: '#271812'
  surface-variant: '#f8ddd2'
typography:
  display-lg:
    fontFamily: Manrope
    fontSize: 48px
    fontWeight: '700'
    lineHeight: 56px
    letterSpacing: -0.02em
  headline-lg:
    fontFamily: Manrope
    fontSize: 32px
    fontWeight: '700'
    lineHeight: 40px
    letterSpacing: -0.01em
  headline-md:
    fontFamily: Manrope
    fontSize: 24px
    fontWeight: '600'
    lineHeight: 32px
  headline-sm:
    fontFamily: Manrope
    fontSize: 20px
    fontWeight: '600'
    lineHeight: 28px
  body-lg:
    fontFamily: Inter
    fontSize: 16px
    fontWeight: '400'
    lineHeight: 24px
  body-md:
    fontFamily: Inter
    fontSize: 14px
    fontWeight: '400'
    lineHeight: 20px
  body-sm:
    fontFamily: Inter
    fontSize: 12px
    fontWeight: '400'
    lineHeight: 18px
  label-md:
    fontFamily: Inter
    fontSize: 13px
    fontWeight: '500'
    lineHeight: 16px
    letterSpacing: 0.05em
  label-sm:
    fontFamily: Inter
    fontSize: 11px
    fontWeight: '600'
    lineHeight: 14px
    letterSpacing: 0.05em
rounded:
  sm: 0.125rem
  DEFAULT: 0.25rem
  md: 0.375rem
  lg: 0.5rem
  xl: 0.75rem
  full: 9999px
spacing:
  base: 4px
  xs: 4px
  sm: 8px
  md: 16px
  lg: 24px
  xl: 32px
  2xl: 48px
  3xl: 64px
  sidebar-width: 260px
  topbar-height: 64px
  gutter: 20px
---

## Brand & Style

The brand personality is **precise, industrious, and high-performance**. As a B2B SaaS platform for automotive workshops, the UI must balance industrial reliability with modern software sophistication. The design system follows a **Corporate / Modern** aesthetic with subtle **Minimalist** influences to handle high information density without overwhelming the user.

Visual metaphors are drawn from the "gear" and "motion" concepts in the logo:
- **Motion:** Subtle horizontal transitions and "forward-leaning" interactive states.
- **Precision:** Perfect grid alignment and micro-interactions that feel "mechanical" (crisp and deliberate).
- **Industrial Texture:** High-contrast borders and a clean, neutral background that mimics a modern, well-organized service bay.

## Colors

The palette is centered around a high-visibility **Safety Orange** (`#FF6500`), synonymous with the automotive and mechanical industry. 

- **Primary Action:** Used for the main CTA and active navigation states.
- **Surface & Background:** A cool gray background (`#F7F8FA`) provides contrast against pure white (`#FFFFFF`) cards and panels, creating clear visual boundaries.
- **Status Colors:** Standardized semantic colors for Success, Warning, and Danger are used for workshop status updates (e.g., "Ready for Pickup", "Delayed", "Urgent Repair").
- **Neutral Scale:** A rigorous range of grays ensures high legibility in data-dense environments like inventory tables and scheduling grids.

## Typography

This system uses a dual-typeface strategy to optimize for both brand character and data utility.

- **Manrope (Headings):** Selected for its modern, geometric structure. It provides a technical yet approachable feel for dashboard titles and KPI highlights.
- **Inter (Body/UI):** Chosen for its exceptional legibility at small sizes and high-density environments. It handles the "heavy lifting" of data grids, labels, and technical descriptions.

**Scaling Rules:**
- For mobile views, `headline-lg` should scale down to 24px.
- `Label` styles are strictly used for metadata, table headers, and status badges.

## Layout & Spacing

The layout is built on a **12-column fluid grid** with a fixed architectural shell.

- **Sidebar:** A fixed 260px left-hand navigation allows for persistent access to core workshop modules (Jobs, Inventory, Customers, Analytics).
- **Topbar:** A 64px top bar houses global search, workshop location switching, and user profile.
- **Data Density:** A strict 4px baseline grid ensures tight vertical rhythm. In "High Density" mode (e.g., Job Boards), padding is reduced from `md (16px)` to `sm (8px)` to maximize on-screen information.
- **Breakpoints:** 
  - Mobile: < 768px (Sidebar collapses to a bottom bar or hamburger).
  - Tablet: 768px - 1024px (Sidebar collapses to icon-only).
  - Desktop: > 1024px (Full sidebar).

## Elevation & Depth

To maintain a clean, professional aesthetic, this design system uses **Tonal Layers** and **Low-Contrast Outlines** instead of heavy shadows.

- **Level 0 (Background):** `#F7F8FA` - The canvas.
- **Level 1 (Surface):** `#FFFFFF` with a 1px `#E5E7EB` border. Used for main content cards and table containers.
- **Level 2 (Floating):** Used for Modals and Toasts. Features a subtle, highly diffused shadow: `0 10px 15px -3px rgba(0, 0, 0, 0.05)`.
- **Interactive Depth:** On hover, clickable cards or list items should transition to a `#F9FAFB` background rather than lifting via shadows, maintaining the "flat-industrial" look.

## Shapes

The design system utilizes **Soft** geometry (`roundedness: 1`). This provides a subtle 4px radius that feels modern and professional without appearing overly "bubbly" or consumer-grade.

- **Buttons & Inputs:** 4px (`0.25rem`) corner radius.
- **Cards & Containers:** 8px (`0.5rem`) corner radius.
- **Status Badges (Chips):** 100px (Pill-shaped) to distinguish them from interactive buttons.
- **Iconography:** Icons should follow a 2px stroke weight with slightly rounded terminals to match the font geometry.

## Components

### Buttons
- **Primary:** Orange background, white text. No gradient. 
- **Secondary:** White background, Gray-300 border, Dark Gray text.
- **Ghost:** No background/border. Primary color text. Used for "Add Row" or "Cancel" actions.
- **States:** Hover states use `primary_hover` (`#E85D00`). Active states shift down 1px to simulate a physical "click".

### Data Grids (Tables)
- **Header:** `label-sm` typography, light gray background (`#F9FAFB`), 1px bottom border.
- **Rows:** 48px height for standard, 36px for high-density. Inter 14px text.
- **Actions:** Inline ghost buttons or a trailing "More" (Vertical Ellipsis) menu.

### KPI Cards
- Large `headline-md` for the primary metric.
- Small sparkline (Line chart) or percentage trend indicator (Success/Danger color) in the top right corner.

### Kanban Boards
- Columns use the `background_color_hex`.
- Cards are Level 1 Surfaces with a thick left border color-coded by "Job Priority" or "Vehicle Type".

### Forms & Inputs
- **Inputs:** 1px border. On focus, the border turns Primary Orange with a 3px soft orange glow (`primary_light`).
- **Filters:** Horizontal bar above tables with pill-shaped "Active Filter" chips.

### Motion & Feedback
- **Skeletons:** Use a subtle pulse animation on `#E5E7EB`.
- **Toasts:** Slide in from the top-right. Success toasts use a checkmark icon with a green accent bar.
- **Gear Motif:** Used as a loading spinner (a rotating gear) or as a watermark pattern in empty states.