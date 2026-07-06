# GymPerformance Design System

Framework-neutral reference extracted from `src/client/ios/member-surface/DesignSystem.swift`.

Use this document for visual parity between the iOS app and the member web surface. Values are recorded as defined in source — not reinterpreted.

**Source file:** `src/client/ios/member-surface/DesignSystem.swift`

**Related asset catalog colours** (not referenced directly in `DesignSystem.swift`, but match or supplement it):

| Asset | Path | Hex | Notes |
|-------|------|-----|-------|
| LaunchWolfBlue | `GymPerformance/Assets.xcassets/LaunchWolfBlue.colorset` | `#1A5BA6` | Same as `wolfBlue` (sRGB 0.102, 0.357, 0.651) |
| AccentColor | `GymPerformance/Assets.xcassets/AccentColor.colorset` | `#1A5BA6` | Light and dark appearances; same as `wolfBlue` |
| LaunchScreenBackground | `GymPerformance/Assets.xcassets/LaunchScreenBackground.colorset` | `#000000` | Launch screen only; not used in `DesignSystem.swift` |

---

## 1. Colours

### Brand colours (fixed hex — no light/dark variants defined)

| Token | Hex | RGB (0–255) | Purpose in source |
|-------|-----|-------------|-------------------|
| `wolfBlue` | `#1A5BA6` | 26, 91, 166 | Primary Wolf blue; main brand colour |
| `pbYellow` | `#FFD600` | 255, 214, 0 | Electric yellow; personal-best / achievement accent |
| `brandAccent` | `#1A5BA6` | — | Alias of `wolfBlue` |
| `achievementAccent` | `#FFD600` | — | Alias of `pbYellow` |

These four tokens are the only custom hex colours defined in `DesignSystem.swift`. They do not change between light and dark mode.

### Semantic / system colours (platform-adaptive)

`DesignSystem.swift` references iOS system semantic colours. No custom hex is defined for these; they adapt to light and dark mode automatically.

| Reference in source | Used for |
|---------------------|----------|
| `Color.primary` | Default foreground text; empty-state icon at 20% opacity |
| `Color.secondary` | De-emphasised text (captions, labels, empty states) |
| `Color(.secondarySystemBackground)` | Standard card background (`standardCard()`) |
| `Color(.tertiarySystemBackground)` | Input field surface background (`inputFieldSurface()`) |
| `.white` | Primary button label colour (`primaryButtonStyle()`) |

Approximate iOS system values for web implementation reference (platform defaults, not hard-coded in `DesignSystem.swift`):

| Semantic | Light mode (approx.) | Dark mode (approx.) |
|----------|----------------------|---------------------|
| `primary` (text) | `#000000` | `#FFFFFF` |
| `secondary` (text) | `rgba(60, 60, 67, 0.6)` | `rgba(235, 235, 245, 0.6)` |
| `secondarySystemBackground` | `#F2F2F7` | `#1C1C1E` |
| `tertiarySystemBackground` | `#FFFFFF` | `#2C2C2E` |

### Opacity variants used in the app (defined at call sites, not in `DesignSystem.swift`)

These combinations appear in member-surface views that consume the design system:

| Colour + opacity | Typical use |
|------------------|-------------|
| `wolfBlue` at 30% | Disabled primary button background |
| `wolfBlue` at 50% | Non-PB chart data points |
| `wolfBlue` at 30% → clear | Chart area gradient |
| `pbYellow` at 15% | PB celebration circle fill (session save) |
| `pbYellow` at 25% | PB badge / capsule backgrounds |

---

## 2. Typography

### Font family

All text styles defined in `DesignSystem.swift` use **SF Rounded** via SwiftUI's `.design: .rounded` (system font with rounded design). On iOS this resolves to **SF Pro Rounded**. For web parity, use a rounded sans-serif stack (e.g. `"SF Pro Rounded", system-ui, sans-serif`) or the closest available rounded grotesque.

No custom font files are loaded; everything is system-derived.

### Named text styles (View modifiers)

| Modifier | Font specification | Weight | Other | Default / typical size |
|----------|-------------------|--------|-------|------------------------|
| `pbValueStyle(size:)` | `.system(size:, design: .rounded)` | semibold | `monospacedDigit()` | Default **34 pt**; also used at **28 pt** and **44 pt** in views |
| `exerciseTitleStyle()` | `.system(.headline, design: .rounded)` | regular (headline default) | — | **17 pt** (iOS headline default) |
| `captionLabelStyle()` | `.system(.caption, design: .rounded)` | regular | `foregroundStyle(.secondary)` | **12 pt** |
| `sectionLabelStyle()` | `.system(.caption2, design: .rounded)` | semibold | `tracking(1.2)`, `textCase(.uppercase)`, `foregroundStyle(.secondary)` | **11 pt** |
| `inputValueStyle()` | `.system(.title2, design: .rounded)` | medium | `monospacedDigit()` | **22 pt** |
| `primaryButtonStyle()` label | `.system(.body, design: .rounded)` | semibold | `foregroundStyle(.white)` | **17 pt** |

### Empty state typography (`EmptyStateView`)

| Element | Specification |
|---------|---------------|
| Icon | `.system(size: 48)`, `Color.primary` at 20% opacity |
| Message | `.system(.subheadline, design: .rounded)`, secondary colour | **15 pt** |

### Monospaced / tabular numerals

- **`pbValueStyle`** — weights, reps, times, distances, and PB values displayed large
- **`inputValueStyle`** — numeric input fields (weight, reps, time, distance)

Both apply `.monospacedDigit()` so digits align and do not shift width when values change.

### iOS text style reference sizes

When a modifier uses a SwiftUI text style rather than a fixed point size, the default body size at standard Dynamic Type is:

| Text style | Default size | Weight |
|------------|--------------|--------|
| `.largeTitle` | 34 pt | regular |
| `.title2` | 22 pt | regular |
| `.title3` | 20 pt | regular |
| `.headline` | 17 pt | semibold |
| `.body` | 17 pt | regular |
| `.subheadline` | 15 pt | regular |
| `.caption` | 12 pt | regular |
| `.caption2` | 11 pt | regular |

(Additional ad-hoc sizes appear in consuming views — e.g. onboarding icon at 64 pt, celebration trophy at 60 pt — but are not defined as reusable modifiers in `DesignSystem.swift`.)

---

## 3. Layout and styling

### Spacing constants (`CGFloat` extension)

| Token | Value (pt / px) | Purpose |
|-------|-----------------|---------|
| `cardPadding` | **16** | Inner padding for standard cards |
| `cardSpacing` | **12** | Vertical spacing within card content stacks |
| `sectionSpacing` | **24** | Vertical spacing between major sections |

### Corner radii

| Token | Value | Applied to |
|-------|-------|------------|
| `cardRadius` | **16** | Standard cards, primary buttons |
| `inputRadius` | **10** | Input field surfaces |
| `chipRadius` | **8** | Defined but not yet used by any view modifier in the codebase |

All rounded rectangles use **continuous** corner style (superellipse), not circular arcs.

### Component styling modifiers

#### `standardCard()`

- Padding: `cardPadding` (16)
- Background: `secondarySystemBackground`
- Corner radius: `cardRadius` (16), continuous

#### `inputFieldSurface()`

- Horizontal padding: **12**
- Vertical padding: **10**
- Background: `tertiarySystemBackground`
- Corner radius: `inputRadius` (10), continuous

#### `primaryButtonStyle(isEnabled:)`

- Width: full width (`maxWidth: .infinity`)
- Vertical padding: **14**
- Background: `wolfBlue` when enabled; `wolfBlue` at **30% opacity** when disabled
- Foreground: white
- Font: body, rounded, semibold
- Corner radius: `cardRadius` (16), continuous

#### `EmptyStateView`

- Stack spacing: **12**
- Vertical padding: **48**
- Horizontal alignment: centred, full width

---

## 4. Usage rules

Patterns evident from `DesignSystem.swift` and its consumers in `src/client/ios/member-surface/`:

### Wolf blue (`#1A5BA6`)

- **Primary brand colour** — tab bar tint, navigation tint, tappable text, chart lines and markers, exercise/PB value display
- **Primary actions** — filled button backgrounds (`primaryButtonStyle`)
- **Structure** — board category indicators, exercise card accents, keyboard dismissal control
- **Not** used for PB celebration moments (see yellow below)

Aliases `brandAccent` and `wolfBlue` are equivalent; `brandAccent` is defined but not referenced elsewhere in the codebase yet.

### Electric yellow / PB yellow (`#FFD600`)

- **Reserved for personal-best and achievement moments** — not a general UI accent
- Used for: PB chart points, PB celebration trophy and headings, onboarding trophy icon, PB badge capsules, session-save celebration UI
- Often paired with **15–25% opacity** yellow fills for soft highlight backgrounds behind badges or icons
- Alias `achievementAccent` equals `pbYellow`; defined but not referenced elsewhere yet

### Grey / system semantics

- **Cards** sit on `secondarySystemBackground`; **inputs** on `tertiarySystemBackground`
- **Secondary text** (units, hints, metadata) uses `.secondary` via `captionLabelStyle()` and similar
- **Section headers** use uppercase, letter-spaced `sectionLabelStyle()` — not brand colour

### Numeric display hierarchy

1. **Large PB / summary values** — `pbValueStyle` (default 34 pt, up to 44 pt on progression chart), semibold rounded, monospaced digits, usually `wolfBlue`
2. **Input values** — `inputValueStyle` (title2 / 22 pt, medium, monospaced digits)
3. **Unit labels** — `captionLabelStyle()` beside inputs (`kg`, `reps`, `m`, `s`, `kcal`)

### Buttons

- One primary filled style: wolf blue background, white semibold label, 16 pt corner radius
- Disabled state: same layout, background at 30% opacity (not a separate grey)

### Cards and sections

- Content grouped in `standardCard()` containers with 16 pt padding
- Within cards: 12 pt spacing; between sections: 24 pt spacing

---

## Web Implementation Values

The iOS app uses platform-adaptive system colours (`secondarySystemBackground`, `tertiarySystemBackground`, `primary`, secondary text) that resolve automatically on iOS but have no web equivalent. The web surface must use **fixed values**. The values below pin the approximate iOS system colours already recorded in this document as the exact web target — do not re-approximate the neutrals at implementation time.

### Brand colours (identical on all platforms)

| Token | Hex | Notes |
|-------|-----|-------|
| Wolf blue | `#1A5BA6` | Exact; same as iOS `wolfBlue` / `brandAccent` |
| PB yellow | `#FFD600` | Exact; same as iOS `pbYellow` / `achievementAccent` |

### Neutral colours — light mode

| Role | Web value | iOS semantic equivalent |
|------|-----------|-------------------------|
| App background | `#FFFFFF` | System grouped/standard background |
| Primary text | `#000000` | `Color.primary` |
| Secondary text | `rgba(60, 60, 67, 0.6)` | `Color.secondary` |
| Card background | `#F2F2F7` | `secondarySystemBackground` |
| Input surface | `#FFFFFF` | `tertiarySystemBackground` |

### Neutral colours — dark mode

| Role | Web value | iOS semantic equivalent |
|------|-----------|-------------------------|
| App background | `#000000` | System grouped/standard background |
| Primary text | `#FFFFFF` | `Color.primary` |
| Secondary text | `rgba(235, 235, 245, 0.6)` | `Color.secondary` |
| Card background | `#1C1C1E` | `secondarySystemBackground` |
| Input surface | `#2C2C2E` | `tertiarySystemBackground` |

Apply light and dark values via a `prefers-color-scheme` media query or an equivalent theme mechanism.

### Opacity variants (identical on web)

Use the same opacity combinations documented in section 1:

| Combination | Use |
|-------------|-----|
| Wolf blue at **30%** | Disabled primary button background |
| Wolf blue at **50%** | Non-PB chart data points |
| Wolf blue **30% → clear** | Chart area gradient |
| PB yellow at **15%** | PB celebration circle fill |
| PB yellow at **25%** | PB badge / capsule backgrounds |

### Typography (web)

- **Font stack:** `"SF Pro Rounded", system-ui, sans-serif` (or equivalent rounded sans-serif fallbacks). SF Pro Rounded is not reliably available on web, especially on Android.
- **Accepted platform difference:** The rounded character is approximated on web by necessity. This is deliberate, not a defect.
- **Tabular numerals:** Preserve for weights, reps, times, distances, and PB values so digits do not shift width when values change. Use `font-variant-numeric: tabular-nums` (or an equivalent) on all numeric display and input fields that use `pbValueStyle` / `inputValueStyle` on iOS.

### Corner radius (web)

iOS uses **continuous** (superellipse) corners; web uses standard `border-radius` as the accepted approximation:

| Element | Radius |
|---------|--------|
| Cards, primary buttons | **16px** |
| Input surfaces | **10px** |

Spacing constants (`cardPadding` 16, `cardSpacing` 12, `sectionSpacing` 24) apply as **16px**, **12px**, and **24px** on web.

---

## Scope note

`DesignSystem.swift` also defines chart scroll/zoom behaviour (`ScrollableDateChartConfiguration`, `ScrollableDateChartModifier`). Those are interaction/layout logic for Swift Charts, not visual tokens, and are omitted from this reference.

For colours and typography not listed here, check individual view files under `src/client/ios/member-surface/` — this document covers only what `DesignSystem.swift` defines plus directly related asset catalog values noted above.
