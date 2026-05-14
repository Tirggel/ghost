---
name: Ghost Minimalist Noir (The Monolith)
version: 1.2.0
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
  # Kanban Priorities
  priority_urgent: "#ef4444"
  priority_high: "#f97316"
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
  sidebar_label:
    fontSize: 12px
  label_tiny:
    fontSize: 11px
    fontWeight: 900
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
  # Standard Settings Spacing
  settings_section: 32px
  settings_header: 12px
  settings_content: 20px
  settings_element: 16px
icons:
  size:
    tiny: 16px
    small: 18px
    medium: 20px
    large: 24px
    extra_large: 28px
    settings: 20px
  colors:
    primary: "{colors.primary}"
    dim: "{colors.text_dim}"
    error: "{colors.error}"
    success: "{colors.success}"
components:
  button-primary:
    backgroundColor: "{colors.primary}"
    textColor: "{colors.on_primary}"
    rounded: "{rounded.none}"
    fontWeight: 900
    textTransform: uppercase
  button-secondary:
    backgroundColor: "transparent"
    border: "1.2px solid {colors.primary}"
    textColor: "{colors.primary}"
    rounded: "{rounded.none}"
  input-field:
    backgroundColor: "{colors.background}"
    border: "1px solid {colors.border}"
    rounded: "{rounded.none}"
    focusedBorder: "1px solid {colors.primary}"
  selectable-card:
    backgroundColor: "{colors.surface}"
    hoverBackgroundColor: "{colors.surface_light}"
    activeBorderColor: "{colors.primary}"
    padding: 14px
  switch:
    activeTrackColor: "rgba(255, 255, 255, 0.5)"
    activeThumbColor: "{colors.primary}"
    inactiveTrackColor: "{colors.surface_light}"
    inactiveThumbColor: "{colors.text_dim}"
---

# Design System Document: The Monolith

## 1. Creative North Star: "The Monolith"
This design system is built upon the concept of **The Monolith**—an experience that feels carved from a single block of obsidian. It rejects the "web-page" aesthetic in favor of a high-precision, technical instrument. By leaning into a monochromatic, high-contrast grayscale palette, we create an environment where content and AI intelligence are the only focal points.

To move beyond a "generic dark mode," this system utilizes **Tonal Architecture**. Instead of relying on lines to define space, we use weight, light, and mathematical spacing. The result is an interface that feels quiet, authoritative, and impossibly sharp.

---

## 2. Color & Surface Architecture
The palette is strictly monochromatic (Zinc scale). High contrast is achieved through the interaction of `surface` and `background` tokens.

### The "No-Line" Rule
Layout sectioning should primarily be achieved through:
1.  **Tonal Shifting:** Placing a `surface` (#18181b) section against a `background` (#09090b) floor.
2.  **Negative Space:** Using the mathematical spacing tokens to create mental boundaries.

### Surface Hierarchy & Nesting
*   **Base Layer:** `background` (#09090b)
*   **Primary Work Area:** `surface` (#18181b)
*   **Active/Hover State:** `surface_light` (#27272a)
*   **Text (Main):** `text_main` (#fafafa)
*   **Text (Dim):** `text_dim` (#a1a1aa)

---

## 3. Typography: The Inter Technical Scale
We use **Inter** exclusively.

*   **Display:** 28px, Bold. Wizard headers.
*   **Heading:** 22px. Sidebar app name.
*   **Title:** 16px. Section headers in settings.
*   **Body:** 13px. Workhorse for messages and inputs. Line height 1.6.
*   **Label Tiny:** 11px, Extra Bold (900). Metadata and all-caps section labels.

---

## 4. Kanban & Task Management
The Kanban system extends The Monolith with functional color coding for priorities.

### Task Cards
*   **Structure:** Sharp-edged cards (`surface`) with a 3px left border indicating priority.
*   **Priority Colors:**
    *   `Urgent`: #ef4444
    *   `High`: #f97316
    *   `Normal`: `text_dim`
    *   `Low`: `border`
*   **Badges:** Small, technical labels with 8% primary opacity and 2px radius.
*   **Agents:** Agent assignments use an icon (`smart_toy`) and 10% primary opacity background.

### Interaction
*   **Drag & Drop:** Feedback state uses `surface_light` and a subtle 40% black shadow.
*   **Progress:** Completion indicated by primary color text and checkmark (e.g., `3/3 ✓`).
*   **Phase 3: Task Orchestration:**
    - **Dependency Management:** Tasks support `dependsOnIds` to model prerequisites.
    - **Automated Transitions:** The `TaskOrchestrator` background engine monitors task status. When all prerequisites for a "Backlog" task are marked as "Done", it is automatically promoted to "To Do".
    - **Autonomous Loops:** Agents can autonomously create, update, and manage tasks through the Kanban toolset, enabling multi-turn autonomous project execution.

---

## 5. Components

### Buttons & Actions
*   **AppSaveButton:** Primary action (White). Supports a 18px `CircularProgressIndicator` (Black) for loading states.
*   **AppActionButton:** Dual-mode (Primary/Secondary). Sharp corners (`none`).
*   **AppNavButton:** Standardized navigation (Back/Next) in sub-nav bars.

### Input & Selection
*   **AppUnifiedPicker:** The canonical dropdown/picker. Includes a built-in loading state to avoid layout shifts during data fetching.
*   **AppHoverCard:** The base for all selectable tiles. Shifts to `surface_light` over 150ms.

### Emoji & Iconography
*   **Colorful Emojis:** Emojis must always be rendered in color. System-wide `EmojiPicker` uses `appEmojiPickerConfig` with a `surface` background to match the theme.
*   **Icons:** Technical, line-based icons (Material Outlined style). Standardized at 20px for settings.

---

## 6. Navigation & Sidebar
*   **Structure:** Vertical sidebar with high-contrast text and pure-white primary icons.
*   **Ordering:** Chat is positioned as the primary entry point, followed by Kanban and Knowledge.
*   **Global Actions:** Settings and Profile are anchored to the bottom.

---

## 7. Visual Patterns & Feedback
*   **Loading States:** Use a stroke-width 2 `CircularProgressIndicator`. In primary buttons, the indicator is Black; in secondary contexts, it matches the `text_dim` or `primary` color.
*   **Transitions:** Strictly 150ms for tonal shifts. No bouncy animations; the feeling should be industrial and rigid.
*   **Asymmetry:** Use asymmetric layouts in editorial-style views (e.g., Wizard) to create a premium, non-generic feel.
