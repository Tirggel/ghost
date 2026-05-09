---
name: Ghost Minimalist Noir (The Monolith)
version: 1.0.0
colors:
  primary: "#ffffff"
  on_primary: "#09090b"
  background: "#09090b"
  on_background: "#fafafa"
  surface: "#18181b"
  surface_light: "#27272a"
  border: "#27272a"
  text_main: "#fafafa"
  text_dim: "#a1a1aa"
  error: "#ff5252"
  success: "#4caf50"
  warning: "#ff9800"
typography:
  fontFamily: Inter
  display:
    fontSize: 28px
    fontWeight: 700
    letterSpacing: "-0.02em"
  heading:
    fontSize: 22px
    fontWeight: 600
  lead:
    fontSize: 20px
  title:
    fontSize: 16px
  subhead:
    fontSize: 14px
  body:
    fontSize: 13px
    lineHeight: 1.6
  small:
    fontSize: 13px
  caption:
    fontSize: 13px
  label_tiny:
    fontSize: 11px
    letterSpacing: "0.05em"
    textTransform: uppercase
rounded:
  none: 0px
  sm: 4px
  default: 6px
  lg: 8px
spacing:
  tiny: 4px
  small: 8px
  medium: 16px
  large: 24px
  extra_large: 32px
components:
  button-primary:
    backgroundColor: "{colors.primary}"
    textColor: "{colors.on_primary}"
    rounded: "{rounded.none}"
  input-field:
    backgroundColor: "{colors.surface}"
    border: "1px solid {colors.border}"
    rounded: "{rounded.none}"
---

# Design System Document: The Monolith

## 1. Creative North Star: "The Monolith"
This design system is built upon the concept of **The Monolith**—an experience that feels carved from a single block of obsidian. It rejects the "web-page" aesthetic in favor of a high-precision, technical instrument. By leaning into a monochromatic, high-contrast grayscale palette, we create an environment where content and AI intelligence are the only focal points.

To move beyond a "generic dark mode," this system utilizes **Tonal Architecture**. Instead of relying on lines to define space, we use weight, light, and mathematical spacing. The result is an interface that feels quiet, authoritative, and impossibly sharp.

---

## 2. Color & Surface Architecture
The palette is strictly monochromatic (Zinc scale). High contrast is achieved through the interaction of `surface` and `background` tokens, ensuring the technical feel of a command-line interface but with the polish of a luxury editorial.

### The "No-Line" Rule
While 1px solid borders are used sparingly (e.g., `border` token #27272a), layout sectioning should primarily be achieved through:
1.  **Tonal Shifting:** Placing a `surface` (#18181b) section against a `background` (#09090b) floor.
2.  **Negative Space:** Using the `medium` (16px) or `large` (24px) spacing tokens to create mental boundaries.

### Surface Hierarchy & Nesting
Depth is achieved through a "Layered Obsidian" approach:
*   **Base Layer:** `background` (#09090b)
*   **Primary Work Area:** `surface` (#18181b)
*   **Active/Hover State:** `surface_light` (#27272a)
*   **Text (Main):** `text_main` (#fafafa)
*   **Text (Dim):** `text_dim` (#a1a1aa)

---

## 3. Typography: The Inter Technical Scale
We use **Inter** exclusively. Its neutral, multi-height apertures provide the "Technical Professional" feel required.

*   **Display:** 28px, Bold. Used for major headers or splash screens.
*   **Heading:** 22px. Sidebar app name and primary section titles.
*   **Body:** 13px. Our workhorse for messages and inputs. Line height 1.6.
*   **Label Tiny:** 11px, Uppercase. Used for metadata and technical indicators.

---

## 4. Elevation & Depth: Tonal Layering
We avoid traditional "Drop Shadows". Instead, we use **Ambient Occlusion**.

*   **Layering Principle:** Instead of a shadow, a "lifted" element uses a different surface tone.
*   **The "Ghost Border":** We use `border` (#27272a) as a subtle boundary for containers like input fields or header separators. It is a "whisper" of a line that blends into the dark background.

---

## 5. Components

### Buttons
*   **Primary:** `primary` (White) background with `on_primary` (Deep Zinc) text. Radius: `none` (0px) for a brutalist feel.
*   **Secondary:** Background: `transparent`. Border: `border`. Text: `primary`.

### Input Fields
Inputs are integrated surfaces.
*   **Default:** `surface` with a `border` (#27272a). Radius: `none` (0px).
*   **Chat Input:** Uses `AppConstants.buttonBorderRadius` (0.0) and sits within a padded container.

### Messages
*   **AI Message Bubbles:** No traditional bubbles. AI text sits directly on the `surface` or `background` with high contrast.
*   **User Messages:** Clearly defined roles without relying on colorful bubbles.

---

## 6. Do's and Don'ts

### Do
*   **Use Asymmetry:** Create an editorial, high-end feel.
*   **Embrace Space:** Space is a luxury; use it to define hierarchy.
*   **High Contrast:** Ensure all primary actions are pure white (`#ffffff`) against the deep zinc background.

### Don't
*   **No Gradients:** Do not use colorful gradients.
*   **No Large Radii:** Keep corners sharp (`none` or `sm`) for an architectural feel.
*   **No "Off-Brand" Colors:** Stick to the monochromatic palette. Only use semantic colors (`error`, `success`) when functionally necessary.
