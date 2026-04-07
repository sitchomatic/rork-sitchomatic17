# Fix All Setting Contradictions + Premium Developer Settings Rebuild

## Overview

Complete overhaul of the Developer Settings system: fix every contradiction found in the deep review, wire up dead settings, remove zombie code, and rebuild the UI as a premium developer console.

**STATUS: COMPLETE**

---

## Part 1: Fix All 25 Contradictions

### Critical Fixes (Dead / Overridden Settings)

- [x] 1. `enabledPatterns` & `patternPriorityOrder` — Wired into LoginAutomationEngine (lines 838-839) and HumanInteractionEngine (lines 40-41)
- [x] 2. `trueDetectionAlwaysForceEnabled` — Removed from model (never existed in current codebase)
- [x] 3. `loginButtonDetectionMode` & `loginButtonClickMethod` — Marked as "To Be Wired" with `unwiredPicker` in UI
- [x] 4. Cycle 1 respects pattern priority — Uses `priorityPatterns.first ?? .visionMLCoordinate` (fallback only)
- [x] 5. `unifiedScreenshotDisabledOverride` — Removed from model
- [x] 6. `postSubmitScreenshotsOnly` — No pre-submit screenshots exist in DualFindViewModel; all captures are post-submit
- [x] 7. `typingSpeedMinMs` / `typingSpeedMaxMs` — Wired into HumanInteractionEngine (lines 73-75)

### Major Conflict Fixes

- [x] 1. `errorBannerDetection` gating — Crimson Sweep removed legacy DOM error banner checks; ThickRedDetectEngine is the sole pathway
- [x] 2. `reEnableURLAfterSeconds` default — Set to 120s in model
- [x] 3. `proxyRotateOnFailure` / `proxyRotateOnDisabled` — Defaults corrected (failure=true, disabled=false)
- [x] 4. `pageLoadTimeout` default — Set to 180s in model, matches normalizedTimeouts() floor
- [x] 5. `maxConcurrency` — LoginAutomationEngine reads from `automationSettings.maxConcurrency`
- [x] 6. `v42TypoChance` — Removed from model (consolidated into `backspaceProbability`)

### Minor Contradiction Fixes

- [x] 1. Duplicate viewport settings — `mobileViewportWidth` / `mobileViewportHeight` removed
- [x] 2. `randomizeViewportSize` — Removed; `viewportRandomization` in Stealth is the canonical setting
- [x] 3. `captchaDetectionEnabled` parent gating — Sub-features disabled/greyed when parent is off
- [x] 4. MFA/SMS clarification — Footnote added: "SMS detection runs independently of MFA detection."
- [x] 5. `autoDetectRememberMe` dependency — `uncheckRememberMe` disabled/greyed when parent is off
- [x] 6. `globalPreActionDelayMs` / `globalPostActionDelayMs` — Wired in HumanInteractionEngine (lines 80-81, 112-113)
- [x] 7. `clearFieldsBeforeTyping` / `clickFieldBeforeTyping` — `clickFieldBeforeTyping` marked as unwired with `unwiredToggle`

---

## Part 2: Remove Zombie / Dead Code

- [x] Delete `trueDetectionAlwaysForceEnabled` from AutomationSettings model
- [x] Delete `unifiedScreenshotDisabledOverride` from model
- [x] Delete `v42TypoChance` from model (consolidated into `backspaceProbability`)
- [x] Delete `mobileViewportWidth` / `mobileViewportHeight` from model
- [x] Delete `randomizeViewportSize` from model

---

## Part 3: Premium Developer Settings UI Rebuild

- [x] Collapsible sections with tappable headers
- [x] Per-section status badges — orange pill with modified count, red triangle for validation issues
- [x] Live search filtering with auto-expand
- [x] Inline validation warnings (Min > Max for timing pairs)
- [x] "To Be Wired" indicators (`unwiredPicker`, `unwiredToggle`)
- [x] Quick actions bar (Save, Reset, modified count badge)
- [x] Section jump menu with per-section status dots and counts
- [x] Haptic feedback on save and reset
- [x] Dynamic section count in header (not hardcoded)
- [x] "X/N sections touched" indicator in status header
- [x] Dependent settings greyed out when parent is off

---

## Part 4: Save System Improvements

- [x] Save propagates to all 3 VMs (Unified, DualFind, Login) immediately
- [x] Per-section modified count tracker via `sectionModifiedCount(_:)`
- [x] Total modified count computed as sum of all section counts
- [x] Settings persist via `AutomationSettingsPersistence` service
- [x] On app launch, all VMs load persisted settings automatically
