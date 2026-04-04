# Fix All Setting Contradictions + Premium Developer Settings Rebuild

## Overview

Complete overhaul of the Developer Settings system: fix every contradiction found in the deep review, wire up dead settings, remove zombie code, and rebuild the UI as a premium developer console.

---

## Part 1: Fix All 25 Contradictions

### 🔴 Critical Fixes (Dead / Overridden Settings)

1. `**enabledPatterns` & `patternPriorityOrder` — Wire into LoginAutomationEngine**
  - Replace the 3 hardcoded priority arrays in LoginAutomationEngine with logic that reads `patternPriorityOrder` from settings, filtered by `enabledPatterns`
  - This makes the Pattern Strategy section in Developer Settings actually functional
2. `**trueDetectionAlwaysForceEnabled` — Remove entirely**
  - It's never read anywhere. `trueDetectionEnabled` + `trueDetectionPriority` already control the behavior
  - Remove from the model and the UI
3. `**loginButtonDetectionMode` & `loginButtonClickMethod` — Mark as "To Be Wired"**
  - These require deeper refactoring of the pattern execution engine to respect
  - Add a visible "⚠️ Not Yet Wired" indicator in the UI so users know
4. **Cycle 1 always forces `.visionMLCoordinate` — Fix selectBestPattern()**
  - In LoginAutomationEngine, make cycle 1 respect the pattern priority order instead of always hardcoding visionMLCoordinate
  - Keep visionMLCoordinate as the *default* first choice, but allow the priority list to override it
5. `**unifiedScreenshotDisabledOverride` — Remove entirely**
  - Never read by any code. Screenshot behavior is controlled by `unifiedScreenshotsPerAttempt` which works fine
  - Remove from model and UI
6. `**postSubmitScreenshotsOnly` — Wire into DualFindViewModel**
  - Add a check: when this is true, skip pre-submit screenshots and only capture at the post-submit timings
  - Simple one-line gate in the screenshot capture logic
7. `**typingSpeedMinMs` / `typingSpeedMaxMs` — Wire into HumanInteractionEngine**
  - Pass these from settings into each pattern's typing delay instead of using hardcoded per-pattern values
  - The AntiBotDetectionService already uses them — make HumanInteractionEngine consistent

### 🟠 Major Conflict Fixes

1. `**errorBannerDetection` = false vs populated `trueDetectionErrorBannerSelectors**`
  - Make the True Detection error banner selectors respect the `errorBannerDetection` toggle
  - When off, skip error banner CSS checks entirely
2. `**reEnableURLAfterSeconds` = 0 — Change default to 120s**
  - A value of 0 means URLs get permanently disabled, contradicting the purpose of URL rotation
  - Change default to 120 seconds so disabled URLs auto-recover
3. `**proxyRotateOnFailure` = false vs `proxyRotateOnDisabled` = true — Fix logic**
  - Swap the defaults: rotate on actual failures (true), don't rotate on disabled results (false)
    - This makes the proxy rotation respond to real network issues
4. `**pageLoadTimeout` defaults to 90s but gets forced to 180s — Fix display**
  - Change the default in the model to 180s to match what actually happens
    - Same for `fieldVerificationTimeout`, `waitForResponseSeconds`, `mfaWaitTimeoutSeconds`, `captchaWaitTimeoutSeconds`, `http429RetryAfterSeconds`
    - Show the minimum floor (180s) as a footnote in the UI
5. `**maxConcurrency` = 7 in settings vs 8 in LoginAutomationEngine — Unify**
  - Make LoginAutomationEngine read `automationSettings.maxConcurrency` instead of using its own hardcoded 8
6. `**v42TypoChance` vs `backspaceProbability` — Consolidate**
  - Remove `v42TypoChance` (it's a duplicate concept)
    - Make the V4.2 settlement gate use `backspaceProbability` from credential entry settings
    - One typo system, one setting

### 🟡 Minor Contradiction Fixes

1. **Duplicate viewport settings — Remove `mobileViewportWidth` / `mobileViewportHeight**`
  - They duplicate `viewportWidth` / `viewportHeight` with identical defaults
    - Remove the mobile duplicates, keep the primary viewport settings
2. `**randomizeViewportSize` = false vs `viewportRandomization` = true — Consolidate**
  - Remove `randomizeViewportSize` from Viewport section
    - `viewportRandomization` in Stealth section is the one that's actually used
3. `**captchaDetectionEnabled` = false but sub-features enabled — Add parent gating**
  - When `captchaDetectionEnabled` is false, grey out `captchaIframeDetection` and `captchaImageDetection` in the UI
    - Add visual dependency indicator
4. `**mfaDetectionEnabled` = false but `smsDetectionEnabled` = true — Clarify**
  - SMS detection runs independently of MFA detection (it's a separate subsystem)
    - Add a footnote in the UI explaining this
5. `**autoDetectRememberMe` = false but `uncheckRememberMe` = true — Fix dependency**
  - When `autoDetectRememberMe` is false, grey out `uncheckRememberMe` in the UI
    - Can't uncheck what you don't detect
6. `**globalPreActionDelayMs` / `globalPostActionDelayMs` — Wire into automation engines**
  - Add these as additive delays in the HumanInteractionEngine before/after each pattern execution
    - Simple 2-line addition per engine
7. `**clearFieldsBeforeTyping` / `clickFieldBeforeTyping` — Already partially wired**
  - `clearFieldsBeforeTyping` is used in AntiBotDetectionService — mark as ✅ in UI
    - `clickFieldBeforeTyping` is not used — mark as "To Be Wired"

---

## Part 2: Remove Zombie / Dead Code

- Delete `trueDetectionAlwaysForceEnabled` from AutomationSettings model
- Delete `unifiedScreenshotDisabledOverride` from model
- Delete `v42TypoChance` from model (consolidated into `backspaceProbability`)
- Delete `mobileViewportWidth` / `mobileViewportHeight` from model
- Delete `randomizeViewportSize` from model
- Delete any preset/template generation code from `SettingVariationGenerator` that creates preset configs (per user request to remove template zombie code)

---

## Part 3: Premium Developer Settings UI Rebuild

### Design

- **Dark theme** with monospaced accents for a true developer console feel
- **Collapsible sections** — each section header is tappable to expand/collapse, all start collapsed except "Actions"
- **Section status badges** — each section header shows a colored dot: 🟢 all defaults, 🟡 modified, 🔴 has validation issues
- **Live search filtering** — typing in the search bar instantly filters to matching settings across all sections, auto-expanding relevant sections
- **Inline validation** — settings that conflict show an orange warning icon with tooltip (e.g. "Min > Max" for timing pairs)
- **"To Be Wired" indicators** — settings not yet connected to automation code show a small ⚠️ badge
- **Modified value highlighting** — values changed from defaults show in blue text, defaults show in grey
- **Quick actions bar** — sticky bottom bar with Save, Reset, and a count of modified settings
- **Section jump menu** — toolbar button that shows a quick-jump list of all 25 sections
- **Haptic feedback** on save and reset

### Layout per Section

- Color-coded section header with icon (same colors as current, refined)
- Collapse chevron on the right
- Badge showing "X modified" count per section
- Settings listed with the current input controls (toggles, number fields, pickers, text fields)
- Dependent settings indented and greyed out when parent is off

### Sections (25 total, cleaned up)

1. Actions (Save / Reset)
2. True Detection (minus removed dead settings)
3. Page Loading (defaults updated to match actual minimums)
4. Field Detection
5. Cookie / Consent
6. Credential Entry
7. Pattern Strategy (now actually functional)
8. Fallback Chain
9. Submit Behavior
10. Post-Submit Evaluation
11. Retry / Requeue
12. Stealth / Fingerprinting
13. Screenshot / Debug (cleaned up, dead settings removed)
14. Concurrency
15. Network Per-Mode
16. URL Rotation (default fix for re-enable timer)
17. Blacklist / Auto-Actions
18. Human Simulation
19. Login Button Detection
20. Time Delays
21. MFA / Two-Factor
22. CAPTCHA
23. Session Management
24. Blank Page Recovery
25. Error Classification
26. Form Interaction
27. Viewport & Window (deduplicated)
28. V4.2 Settlement Gate (typo chance removed)
29. AI Telemetry

---

## Part 4: Save System Improvements

- Save propagates to all 3 VMs (Unified, DualFind, Login) immediately — same as current
- Add a "modified count" tracker that compares current settings to defaults
- Settings persist via the existing `AutomationSettingsPersistence` service
- On app launch, all VMs load persisted settings automatically (already wired from previous work)

