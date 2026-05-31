# Task 001: Fix Flutter deprecation warnings

## Objective
Resolve all 5 remaining Flutter analyzer warnings so `flutter analyze` 
exits clean with 0 issues.

## Requirements
- Fix `groupValue` and `onChanged` deprecation in `death_count_confirm_screen.dart`
  by migrating to `RadioGroup` pattern
- Fix `setActiveGameId` deprecation in `larp_picker_screen.dart`
  by renaming to `setActiveTenantKey`
- Fix unnecessary underscores warnings in `sign_in_screen.dart` lines 126:47 and 126:51

## Acceptance Criteria
- [ ] `flutter analyze --no-pub` exits 0 with no issues
- [ ] All existing Flutter tests still pass
- [ ] No functional behaviour changes — purely mechanical fixes

## Files Likely Affected
- `lib/screens/death_count_confirm_screen.dart`
- `lib/screens/larp_picker_screen.dart`
- `lib/screens/sign_in_screen.dart`

## Context
Run `flutter analyze --no-pub` to see current warnings before starting.
These are all mechanical deprecation fixes — no logic changes needed.
The `setActiveGameId` rename is within the same package so check for
other callers with `grep -r "setActiveGameId" lib/`.

## Out of Scope
- Any Node.js deprecation warnings
- Any functional changes to screens
- Any UI changes


# 📊 Agent Report

Fix Flutter deprecation warnings: migrate to RadioGroup, rename setActiveGameId to setActiveTenantKey, single-underscore wildcards, drop analysis_options ignore directives.

---
DONE
