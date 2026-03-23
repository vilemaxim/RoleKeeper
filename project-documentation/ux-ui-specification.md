# RoleKeeper - UX/UI Specification

**Version**: 1.0
**Date**: December 9, 2025
**Status**: Design Blueprint
**Based On**: Product Requirements Document v1.0, System Architecture v1.0

---

## Executive Summary

### Design Vision

RoleKeeper's user experience is built around one core principle: **"Your character, instantly available."** Every design decision prioritizes getting players to their character information as quickly as possible, especially in challenging field conditions where attention is divided and connectivity is unreliable.

### Design Goals

1. **Instant Access** - Character information available in 2 taps or less from app launch
2. **Field-Ready** - High contrast, large touch targets, works in sunlight with gloves
3. **Offline-First** - Core reading functionality works without network
4. **Progressive Complexity** - Simple for casual players, powerful for organizers
5. **Rule-Agnostic Flexibility** - UI adapts to any game system without hardcoded assumptions
6. **Game-Themable** - UI can be themed to fit the game being run (colors, branding)
7. **Orientation-Agnostic** - All screens must work in both portrait and landscape

### Platform Context Summary

| Persona | Primary Platform | Environment | Connectivity | Key UX Priority |
|---------|-----------------|-------------|--------------|-----------------|
| Jordan (Active Player) | Mobile | Field + Desk | Offline-first | Quick character access, multi-game portfolio |
| Alex (Casual Player) | Mobile | Field | Offline-first | Simplicity, Quick View mode |
| Morgan (Organizer) | Desktop/Web (planning), Mobile (events) | Desk + Field | Online for planning | Dashboard efficiency, bulk operations |
| Sam (Plot Writer) | Desktop/Web only | Desk | Online-required | Information density, relationships |

---

## Table of Contents

1. [Design System](#1-design-system)
2. [Information Architecture](#2-information-architecture)
3. [User Flows](#3-user-flows)
4. [Screen Specifications](#4-screen-specifications)
5. [Component Library](#5-component-library)
6. [Accessibility Standards](#6-accessibility-standards)
7. [Platform Adaptations](#7-platform-adaptations)
8. [Offline UX Patterns](#8-offline-ux-patterns)
9. [Motion and Animation](#9-motion-and-animation)
10. [Implementation Notes](#10-implementation-notes)

---

## 1. Design System

### 1.1 Design Principles

#### Principle 1: Field-First Design
Every screen must be usable:
- In direct sunlight (high contrast)
- With cold/gloved hands (large touch targets)
- With divided attention (clear visual hierarchy)
- Without network (offline indicators, cached data)

#### Principle 2: Progressive Disclosure
- Default views show essential information only
- Advanced features are one tap away but not cluttering the primary view
- Complexity reveals itself as users need it

#### Principle 3: Consistent Feedback
- Every action has visible feedback
- System state (online/offline/syncing) is always visible
- Errors are clear, actionable, and recoverable

#### Principle 4: Role-Appropriate Density
- Player screens: Low density, high scannability
- Organizer screens: Higher density, tables and filters
- Both: Respect the context (field vs desk)

#### Principle 5: Game-Themable
- When a character is linked to a Game System, the UI can adopt that game's theme (primary color, accent, branding)
- Default theme applies when no game context or for freeform characters
- Theming enhances immersion and helps players identify which game they're in

#### Principle 6: Portrait and Landscape Support
- All screens must function in both portrait and landscape orientations
- Layouts adapt: single-column in portrait, master-detail or multi-column in landscape where appropriate
- No orientation locking; the app follows device rotation

### 1.2 Color System

#### Primary Palette

```
Brand Colors:
- Primary:        #6366F1 (Indigo-500) - Main actions, links, focus states
- Primary Dark:   #4F46E5 (Indigo-600) - Hover states, active states
- Primary Light:  #818CF8 (Indigo-400) - Backgrounds, subtle highlights

Secondary Colors:
- Accent:         #F59E0B (Amber-500) - Notifications, highlights, warnings
- Accent Dark:    #D97706 (Amber-600) - Hover states
- Accent Light:   #FCD34D (Amber-300) - Subtle backgrounds
```

#### Semantic Colors

```
Status Colors:
- Success:        #10B981 (Emerald-500) - Synced, completed, positive
- Warning:        #F59E0B (Amber-500) - Pending, caution, attention needed
- Error:          #EF4444 (Red-500) - Failed, offline, errors
- Info:           #3B82F6 (Blue-500) - Informational messages

Sync Status Colors:
- Synced:         #10B981 (Emerald-500)
- Syncing:        #3B82F6 (Blue-500) with animation
- Pending:        #F59E0B (Amber-500)
- Offline:        #6B7280 (Gray-500)
- Error:          #EF4444 (Red-500)
```

#### Neutral Palette

```
Light Mode:
- Background:     #FFFFFF
- Surface:        #F9FAFB (Gray-50)
- Surface Elevated: #FFFFFF with shadow
- Border:         #E5E7EB (Gray-200)
- Border Strong:  #D1D5DB (Gray-300)
- Text Primary:   #111827 (Gray-900)
- Text Secondary: #6B7280 (Gray-500)
- Text Disabled:  #9CA3AF (Gray-400)

Dark Mode:
- Background:     #111827 (Gray-900)
- Surface:        #1F2937 (Gray-800)
- Surface Elevated: #374151 (Gray-700)
- Border:         #374151 (Gray-700)
- Border Strong:  #4B5563 (Gray-600)
- Text Primary:   #F9FAFB (Gray-50)
- Text Secondary: #9CA3AF (Gray-400)
- Text Disabled:  #6B7280 (Gray-500)
```

#### High Contrast Mode (Outdoor/Field Use)

```
High Contrast Light:
- Background:     #FFFFFF
- Text Primary:   #000000
- Primary:        #4338CA (Indigo-700) - Darker for better contrast
- Borders:        #000000 at 20% opacity

High Contrast Dark:
- Background:     #000000
- Text Primary:   #FFFFFF
- Primary:        #A5B4FC (Indigo-300) - Lighter for better contrast
- Borders:        #FFFFFF at 20% opacity
```

#### Game-Specific Theme Overrides

When a character or event is linked to a Game System, the UI can apply that game's theme. Game Systems may define optional theme overrides:

```
Game Theme (optional, per GameSystem):
- Primary Color:    Override for main actions, links (hex)
- Primary Dark:     Override for hover/active states
- Accent Color:     Override for highlights, notifications
- Background Image: Optional subtle texture or pattern (low opacity)
```

- **Fallback**: If no game theme is defined, use the default RoleKeeper palette
- **Accessibility**: Game theme colors must still meet WCAG 2.1 AA contrast requirements; system validates or falls back if insufficient
- **Scope**: Theme applies when viewing character sheets, event details, or any game-context screen

#### Color Accessibility

All color combinations must meet:
- **WCAG 2.1 AA**: 4.5:1 contrast for normal text, 3:1 for large text
- **WCAG 2.1 AAA target**: 7:1 for critical field-use text

| Combination | Light Mode Ratio | Dark Mode Ratio | Status |
|------------|------------------|-----------------|--------|
| Text Primary on Background | 16.1:1 | 15.1:1 | AAA |
| Text Secondary on Background | 5.7:1 | 4.6:1 | AA |
| Primary on Background | 4.5:1 | 5.2:1 | AA |
| Error on Background | 4.5:1 | 5.1:1 | AA |

### 1.3 Typography

#### Type Scale

```
Font Family:
- Primary: Inter (or system-ui fallback)
- Monospace: JetBrains Mono (for character stats/numbers)

Scale (Mobile):
- Display:      32px / 40px line-height / -0.02em tracking / Bold
- Headline 1:   28px / 36px / -0.02em / Bold
- Headline 2:   24px / 32px / -0.01em / Semi-bold
- Headline 3:   20px / 28px / -0.01em / Semi-bold
- Title:        18px / 24px / 0 / Semi-bold
- Body Large:   16px / 24px / 0 / Regular
- Body:         14px / 20px / 0.01em / Regular
- Body Small:   12px / 16px / 0.02em / Regular
- Caption:      11px / 14px / 0.02em / Regular
- Overline:     10px / 14px / 0.08em / Semi-bold / Uppercase

Scale (Desktop): Increase by 2px for Headline and Display sizes
```

#### Typography Usage

| Element | Style | Usage |
|---------|-------|-------|
| Character Name | Headline 1 | Character header, primary identifier |
| Section Title | Headline 3 | Attributes, Abilities, Inventory headers |
| Attribute Name | Title | Individual attribute labels |
| Attribute Value | Body Large, Monospace | Numeric values, ratings |
| Description | Body | Ability descriptions, notes |
| Metadata | Caption | Timestamps, sync status, counts |
| Button Primary | Title | Primary action buttons |
| Button Secondary | Body Large | Secondary actions |

### 1.4 Spacing System

#### Base Unit: 4px

```
Spacing Scale:
- 0:    0px
- 1:    4px    (xs - tight inline spacing)
- 2:    8px    (sm - compact elements)
- 3:    12px   (md - standard element spacing)
- 4:    16px   (lg - section padding, card padding)
- 5:    20px   (xl - large component gaps)
- 6:    24px   (2xl - section separators)
- 8:    32px   (3xl - major section breaks)
- 10:   40px   (4xl - screen-level spacing)
- 12:   48px   (5xl - hero spacing)
- 16:   64px   (6xl - dramatic spacing)
```

#### Layout Spacing

```
Screen Padding:
- Mobile: 16px horizontal, 16px top, safe area bottom
- Tablet: 24px horizontal
- Desktop: 32px horizontal (max-width container)

Card Padding:
- Compact: 12px
- Standard: 16px
- Spacious: 20px

List Item Spacing:
- Dense: 8px vertical
- Standard: 12px vertical
- Comfortable: 16px vertical
```

### 1.5 Iconography

#### Icon System

```
Icon Library: Lucide Icons (open source, consistent style)
Alternative: Material Symbols Outlined

Sizes:
- Small:   16px (inline with text)
- Medium:  20px (list items, buttons)
- Large:   24px (navigation, headers)
- XLarge:  32px (empty states, feature icons)
- Hero:    48px (onboarding, major features)

Stroke Width: 1.5px (2px for small sizes)
```

#### Core Icons

| Function | Icon | Context |
|----------|------|---------|
| Character | `user-circle` | Portfolio, character reference |
| Add/Create | `plus` | FAB, add buttons |
| Edit | `pencil` | Edit mode trigger |
| Delete | `trash-2` | Destructive actions |
| Search | `search` | Search fields |
| Filter | `filter` | Filter controls |
| Settings | `settings` | Settings access |
| Offline | `wifi-off` | Connectivity status |
| Syncing | `refresh-cw` | Sync in progress (animated) |
| Synced | `check-circle` | Sync complete |
| Error | `alert-circle` | Error states |
| Inventory | `package` | Items section |
| Abilities | `zap` | Abilities section |
| Attributes | `bar-chart-2` | Stats section |
| Journal | `book-open` | Notes/journal section |
| Event | `calendar` | Events feature |
| Quick View | `eye` | Quick view mode |

### 1.6 Elevation and Shadows

```
Elevation Levels:

Level 0 (Flat):
- No shadow
- Use: Background surfaces, inline elements

Level 1 (Raised):
- Shadow: 0 1px 2px rgba(0,0,0,0.05)
- Use: Cards, list items on scroll

Level 2 (Elevated):
- Shadow: 0 4px 6px rgba(0,0,0,0.07), 0 2px 4px rgba(0,0,0,0.05)
- Use: Floating cards, popovers

Level 3 (Floating):
- Shadow: 0 10px 15px rgba(0,0,0,0.1), 0 4px 6px rgba(0,0,0,0.05)
- Use: Modals, bottom sheets

Level 4 (Modal):
- Shadow: 0 20px 25px rgba(0,0,0,0.15), 0 10px 10px rgba(0,0,0,0.04)
- Use: Critical modals, full-screen overlays

Dark Mode: Increase opacity by 50%, add subtle light border
```

### 1.7 Border Radius

```
Radius Scale:
- None:     0px    (sharp corners where needed)
- Small:    4px    (inputs, chips)
- Medium:   8px    (cards, buttons)
- Large:    12px   (modals, larger cards)
- XLarge:   16px   (bottom sheets, panels)
- Full:     9999px (pills, avatars, circular buttons)
```

---

## 2. Information Architecture

### 2.1 Navigation Structure

#### Mobile Navigation (Bottom Tab Bar)

```
+--------------------------------------------------+
|                                                  |
|              [Screen Content]                    |
|                                                  |
+--------------------------------------------------+
|  [Portfolio]  |  [Events]  |  [Profile]         |
|    (home)     | (Phase 2)  |                    |
+--------------------------------------------------+

Tab Definitions:
- Portfolio: Character list (home screen), character management
- Events: Upcoming events, registrations, event discovery (Phase 2)
- Profile: Account settings, app settings, help
```

#### Mobile Navigation Details

```
Portfolio Tab:
  Portfolio Screen (Character List)
    |-- Character Detail Screen
    |     |-- Attributes Tab
    |     |-- Abilities Tab
    |     |-- Inventory Tab
    |     |-- Relationships Tab
    |     |-- Journal Tab
    |     |-- [Action] Quick View (simplified overlay)
    |     |-- [Action] Edit Character
    |
    |-- Create Character Screen
    |-- [Modal] Add Attribute
    |-- [Modal] Add Ability
    |-- [Modal] Add Relationship
    |-- [Modal] Add Item
    |-- [Modal] Add Journal Entry

Events Tab (Phase 2):
  Events List Screen
    |-- Event Detail Screen
    |     |-- Schedule Tab
    |     |-- My Character Tab (linked)
    |     |-- Info Tab
    |
    |-- Event Registration Flow
    |-- [Modal] Link Character to Event

Profile Tab:
  Profile Screen
    |-- Account Settings
    |-- App Settings (theme, offline, notifications)
    |-- Help & Support
    |-- About
    |-- Sign Out
```

#### Desktop/Web Navigation (Sidebar)

```
+--------+----------------------------------------+
|        |                                        |
| SIDEBAR|           MAIN CONTENT                 |
|        |                                        |
| [Logo] |  +----------------------------------+  |
|        |  |                                  |  |
| Player |  |     Context-dependent            |  |
| -------|  |     main content area            |  |
| Chars  |  |                                  |  |
| Events |  |                                  |  |
|        |  +----------------------------------+  |
| Org.   |                                        |
| -------|  +----------------------------------+  |
| Events |  |     Detail panel                 |  |
| Templ. |  |     (when item selected)         |  |
| Plot   |  +----------------------------------+  |
|        |                                        |
| [Prof] |                                        |
+--------+----------------------------------------+

Sidebar Sections:
- Player Section: My Characters, My Events
- Organizer Section (if isOrganizer): My Organized Events, Templates, Plot (Phase 3)
- Profile: Settings, Help, Sign Out
```

### 2.2 Screen Hierarchy

```
Level 0 - App Shell
|
+-- Level 1 - Tab Screens (Portfolio, Events, Profile)
|   |
|   +-- Level 2 - Detail Screens (Character Detail, Event Detail)
|   |   |
|   |   +-- Level 3 - Edit Screens (Character Edit, nested modals)
|   |
|   +-- Level 2 - Creation Flows (Create Character, Register for Event)
|
+-- Level 1 - Organizer Shell (separate navigation context on web)
    |
    +-- Level 2 - Dashboard, Event Management, Templates
        |
        +-- Level 3 - Player Management, Item Distribution
```

### 2.3 Content Organization

#### Character Detail Screen Tabs

```
Tabs Order (left to right):
1. Overview  - Quick summary of key stats, currency (default view)
2. Attributes - Full attribute list grouped by category
3. Abilities - Powers, skills, advantages, disadvantages
4. Inventory - Items, equipment, resources
5. Relationships - Structured links to other characters (allies, rivals, etc.)
6. Journal   - Notes, history, backstory

Tab Behavior:
- Swipe between tabs on mobile
- Tab bar sticks to top on scroll
- Last active tab remembered per character
```

#### Portfolio Screen Organization

```
Sort Options:
- Last Viewed (default) - Most recently accessed first
- Alphabetical - A-Z by character name
- Game System - Grouped by game/campaign
- Event Date - Sorted by upcoming linked events

Filter Options:
- All Characters (default)
- By Game System (dropdown of user's games)
- Linked to Event (show only event-linked characters)
- Archived (hidden by default)

View Options:
- Card View (default on mobile) - Character cards in a list
- Grid View (optional on tablet/desktop) - 2-3 column grid
```

---

## 3. User Flows

### 3.1 Onboarding Flow

#### Context Summary
- **Primary Platform**: Mobile-first
- **Environment**: Often at an event, holding an organizer's flyer with QR code
- **Connectivity**: Online required for account creation
- **Primary Role(s)**: New player discovering app through a game
- **Key Constraints**: Must get player into their first game in under 2 minutes

#### Design Philosophy

Players typically discover RoleKeeper through a game, not the app store:
- An organizer shares a QR code at an event, on social media, or on printed materials
- A friend recommends the app and tells them to "scan the code for our game"
- The app should prioritize this path while still allowing exploration

**Player-first adoption**: Players whose games do not use RoleKeeper can still set up their own character tracking. This delivers immediate value and may lead organizers to adopt the platform when they see players using it.

#### Flow Diagram

```
[App Launch]
     |
     v
[Welcome Screen]
     |
     +-- "Scan QR Code" (Primary) -----> [Camera/QR Scanner]
     |                                          |
     |                                          v
     |                                   [Game Preview Screen]
     |                                          |
     |                                          v
     |                                   [Sign Up/Sign In]
     |                                          |
     |                                          v
     |                                   [Create Character for Game]
     |                                          |
     |                                          v
     |                                   [Game Home / Character Sheet]
     |
     +-- "Browse Games" (Secondary) ---> [Public Games List]
     |                                          |
     |                                          v
     |                                   [Game Details]
     |                                          |
     |                                          +-- "Join Game" --> [Sign Up/Sign In] --> [Create Character]
     |
     +-- "Sign In" (Tertiary) ----------> [Sign In Screen]
     |                                          |
     |                                          v
     |                                   [Portfolio / Games List]
     |
     +-- "My game isn't using RoleKeeper yet" --> [Sign Up] --> [Standalone Setup]
         (Secondary, player-first adoption)              |
                                                        v
                                                 [How would you like to start?]
                                                        |
                 +--------------------------------------+--------------------------------------+
                 |                                      |                                      |
                 v                                      v                                      v
        [Use a known system]                  [Use a simple template]               [Define my own]
                 |                                      |                                      |
                 v                                      v                                      v
        [Cursible | RUIN | Other...]          [Generic LARP | Murder Mystery]       [Add attributes/abilities]
                 |                                      |                                      |
                 +--------------------------------------+--------------------------------------+
                                                        |
                                                        v
                                                 [Create Character] --> [Character Sheet / Portfolio]
```

#### Screen States

**Welcome Screen (Game-Centric)**
```
+----------------------------------+
|                                  |
|         [App Logo]               |
|                                  |
|      RoleKeeper              |
|                                  |
|    Join your LARP or mystery     |
|    game in seconds.              |
|                                  |
|                                  |
|  +----------------------------+  |
|  |                            |  |
|  |     [QR Code Icon]         |  |
|  |                            |  |
|  |   Scan Game QR Code        |  |
|  |                            |  |
|  +----------------------------+  |
|        ^ Primary CTA ^           |
|                                  |
|  [  Browse Public Games  ]       |
|                                  |
|  Already have an account?        |
|         [Sign In]                |
|                                  |
|  --------------------------------|
|  My game isn't using             |
|  RoleKeeper yet?             |
|  [Set up my own character        |
|   tracking]                      |
|                                  |
+----------------------------------+
```

**QR Scan Screen**
```
+----------------------------------+
|  [× Close]                       |
|                                  |
|  Point your camera at the        |
|  game's QR code                  |
|                                  |
|  +----------------------------+  |
|  |                            |  |
|  |                            |  |
|  |     [Camera Viewfinder]    |  |
|  |                            |  |
|  |        [ ]                 |  |
|  |                            |  |
|  +----------------------------+  |
|                                  |
|  Don't have a QR code?           |
|  [Enter game code manually]      |
|                                  |
+----------------------------------+
```

**Game Preview Screen (Post-Scan)**
```
+----------------------------------+
|  [<- Back]                       |
|                                  |
|  +----------------------------+  |
|  |    [Game Cover Image]      |  |
|  +----------------------------+  |
|                                  |
|  Vampire: The Masquerade         |
|  Chicago by Night Chronicle      |
|                                  |
|  Organized by: Sarah's Games     |
|  147 players · 3 active events   |
|                                  |
|  "A gothic horror LARP set in    |
|   modern-day Chicago..."         |
|                                  |
|  --------------------------------|
|                                  |
|  Join this game to create a      |
|  character and participate in    |
|  events.                         |
|                                  |
|  [  Join This Game (Primary)  ]  |
|                                  |
+----------------------------------+
```

**Browse Public Games Screen**
```
+----------------------------------+
|  [<- Back]          [Search Q]   |
|                                  |
|  Find a Game                     |
|                                  |
|  +----------------------------+  |
|  | [Q] Search games...        |  |
|  +----------------------------+  |
|                                  |
|  [Fantasy] [Horror] [Sci-Fi]     |
|  [Mystery] [Nordic] [All]        |
|                                  |
|  --------------------------------|
|                                  |
|  Popular Games                   |
|                                  |
|  +----------------------------+  |
|  | [img] Vampire: The         |  |
|  |       Masquerade           |  |
|  |       147 players · Horror |  |
|  +----------------------------+  |
|                                  |
|  +----------------------------+  |
|  | [img] Dungeons & Dragons   |  |
|  |       5th Edition          |  |
|  |       89 players · Fantasy |  |
|  +----------------------------+  |
|                                  |
|  +----------------------------+  |
|  | [img] Murder at the Manor  |  |
|  |       Custom mystery game  |  |
|  |       23 players · Mystery |  |
|  +----------------------------+  |
|                                  |
|  [Show More]                     |
|                                  |
+----------------------------------+
```

**Game Details Screen**
```
+----------------------------------+
|  [<- Back]               [...]   |
|                                  |
|  +----------------------------+  |
|  |                            |  |
|  |    [Game Cover Image]      |  |
|  |                            |  |
|  +----------------------------+  |
|                                  |
|  Vampire: The Masquerade         |
|  5th Edition                     |
|                                  |
|  [Horror] [World of Darkness]    |
|                                  |
|  Organized by: Sarah's Games     |
|  Created: June 2025              |
|                                  |
|  --------------------------------|
|                                  |
|  About this Game                 |
|                                  |
|  "The classic gothic horror      |
|  game of personal and political  |
|  monsters. Play as a vampire     |
|  navigating the dangerous        |
|  politics of the Camarilla..."   |
|                                  |
|  --------------------------------|
|                                  |
|  Game System Details             |
|                                  |
|  • Attributes: Physical, Social, |
|    Mental                        |
|  • Abilities: Disciplines,       |
|    Backgrounds, Merits           |
|  • Resources: Health, Blood Pool |
|                                  |
|  --------------------------------|
|                                  |
|  [  Join This Game (Primary)  ]  |
|                                  |
+----------------------------------+
```

**Sign Up (Post-Game Selection)**
```
+----------------------------------+
|  [<- Back]                       |
|                                  |
|  Join Vampire: The Masquerade    |
|                                  |
|  Create an account to join this  |
|  game and create your character. |
|                                  |
|  [G] Continue with Google        |
|                                  |
|  [] Continue with Apple         |
|                                  |
|  -------- or --------            |
|                                  |
|  [  Sign up with Email  ]        |
|                                  |
|  Already have an account?        |
|         [Sign In]                |
|                                  |
|  By continuing, you agree to     |
|  our Terms & Privacy Policy      |
|                                  |
+----------------------------------+
```

**Create Character for Game (Simplified)**
```
+----------------------------------+
|  [× Cancel]              [Save]  |
|                                  |
|  Create Your Character           |
|  for Vampire: The Masquerade     |
|                                  |
|  +----------------------------+  |
|  | [+ Add Portrait]           |  |
|  +----------------------------+  |
|                                  |
|  Character Name *                |
|  +----------------------------+  |
|  | Elara Nightwhisper         |  |
|  +----------------------------+  |
|                                  |
|  Pronouns                        |
|  +----------------------------+  |
|  | she/her                    |  |
|  +----------------------------+  |
|                                  |
|  --------------------------------|
|                                  |
|  Clan * (required by game)       |
|  +----------------------------+  |
|  | [Select...]            [v] |  |
|  +----------------------------+  |
|                                  |
|  [The game organizer will add    |
|   your stats after approval]     |
|                                  |
|  [  Create Character  ]          |
|                                  |
+----------------------------------+
```

#### 3.1.1 Standalone Character Setup Flow

For players whose games do not use RoleKeeper, this path lets them build enough rules to track their character. Entry: "My game isn't using RoleKeeper yet" → "Set up my own character tracking" on the Welcome Screen.

**How Would You Like to Start? Screen**
```
+----------------------------------+
|  [<- Back]                       |
|                                  |
|  Set up character tracking       |
|                                  |
|  How would you like to start?    |
|                                  |
|  +----------------------------+  |
|  | [icon] My game uses a      |  |
|  |        known system        |  |
|  | Cursible, RUIN, or other   |  |
|  +----------------------------+  |
|                                  |
|  +----------------------------+  |
|  | [icon] Use a simple        |  |
|  |        template           |  |
|  | Generic LARP, Murder       |  |
|  | Mystery, or Minimal        |  |
|  +----------------------------+  |
|                                  |
|  +----------------------------+  |
|  | [icon] I'll define my own  |  |
|  | Add attributes and         |  |
|  | abilities as I go           |  |
|  +----------------------------+  |
|                                  |
+----------------------------------+
```

**Known System Selection** (when "My game uses a known system" chosen)
```
+----------------------------------+
|  [<- Back]                       |
|                                  |
|  Pick your game system           |
|                                  |
|  +----------------------------+  |
|  | Cursible                   |  |
|  +----------------------------+  |
|  +----------------------------+  |
|  | RUIN                       |  |
|  +----------------------------+  |
|  +----------------------------+  |
|  | [Search other systems...]  |  |
|  +----------------------------+  |
|                                  |
+----------------------------------+
```

**Template Selection** (when "Use a simple template" chosen)
```
+----------------------------------+
|  [<- Back]                       |
|                                  |
|  Choose a template               |
|                                  |
|  +----------------------------+  |
|  | Generic LARP               |  |
|  | HP, abilities, inventory   |  |
|  +----------------------------+  |
|  +----------------------------+  |
|  | Murder Mystery             |  |
|  | Clues, secrets, notes      |  |
|  +----------------------------+  |
|  +----------------------------+  |
|  | Minimal                    |  |
|  | Name, description, notes   |  |
|  +----------------------------+  |
|                                  |
+----------------------------------+
```

**Define My Own**: Proceeds to character creation with minimal structure (name, description, notes). User adds attributes and abilities progressively as needed.

**Post-setup**: User lands on character creation, then character sheet. Optional prompt: "Love tracking your character here? Share RoleKeeper with your organizer—they can run events and push updates directly to your sheet."

#### Account Creation Timing

| Entry Path | When Account Created |
|------------|---------------------|
| QR Code Scan | After previewing game, before creating character |
| Browse Games | After selecting a game to join |
| Sign In | Already has account |
| Set up own character tracking | After sign up, before standalone setup flow |

#### Edge Cases

**QR Code for Private Game**:
- If game is private/unlisted but QR code is valid, show preview and allow joining
- The QR code acts as the "invitation"

**User Already Has Account**:
- After scanning QR, detect existing account and offer "Sign In" instead of "Sign Up"
- After sign in, prompt to create character for this game

**User Already In This Game**:
- Show "You're already part of this game" with link to their character(s)
- Offer to create another character if game allows multiple

### 3.2 Character Management Flow

#### 3.2.1 Create Character Flow

#### Context Summary
- **Primary Platform**: Mobile-first (but should work well on desktop)
- **Environment**: Usually desk/planning mode
- **Connectivity**: Online for initial save; offline creation queues
- **Primary Role(s)**: Active Player, Casual Player
- **Key Constraints**: Must feel lightweight, not like a bureaucratic form

#### Flow Diagram

```
[Portfolio Screen]
     |
     +-- [+ FAB] or [Create Character Button]
     |
     v
[Character Create Screen]
     |
     +-- Step 1: Basic Info
     |   - Name (required)
     |   - Pronouns (optional)
     |   - Game System (optional, searchable)
     |   - Campaign/Game (optional)
     |
     +-- Step 2: Description (optional, skippable)
     |   - Portrait image
     |   - Character description/backstory
     |
     +-- Step 3: Initial Setup (optional, skippable)
     |   - Add first attributes
     |   - Add first abilities
     |   - Suggestions based on game system (if selected)
     |
     v
[Save] --> [Character Detail Screen]
```

#### Create Character Screen (Single Scrollable Form)

```
+----------------------------------+
|  [X Close]     Create Character  |
|                                  |
|  +----------------------------+  |
|  |                            |  |
|  |     [+ Add Portrait]       |  |
|  |         (optional)         |  |
|  |                            |  |
|  +----------------------------+  |
|                                  |
|  Character Name *                |
|  +----------------------------+  |
|  | Elara Nightwhisper         |  |
|  +----------------------------+  |
|                                  |
|  Pronouns                        |
|  +----------------------------+  |
|  | she/her                    |  |
|  +----------------------------+  |
|                                  |
|  Game System                     |
|  +----------------------------+  |
|  | Vampire: The Masquerade   v|  |
|  +----------------------------+  |
|  (Optional - helps organize)     |
|                                  |
|  Campaign / Game                 |
|  +----------------------------+  |
|  | Seattle by Night           |  |
|  +----------------------------+  |
|                                  |
|  Description                     |
|  +----------------------------+  |
|  | A cunning diplomat from... |  |
|  |                            |  |
|  +----------------------------+  |
|                                  |
|  [  Create Character  ]          |
|                                  |
|  You can add attributes and      |
|  abilities after creation        |
|                                  |
+----------------------------------+
```

#### 3.2.2 View Character Flow

#### Context Summary
- **Primary Platform**: Mobile (90% of character viewing)
- **Environment**: Field (during events) - critical path
- **Connectivity**: Offline-first (must work without network)
- **Primary Role(s)**: All players
- **Key Constraints**: Must load cached data instantly (<500ms)

#### Flow Diagram

```
[Portfolio Screen]
     |
     +-- [Tap Character Card]
     |
     v
[Character Detail Screen]
     |
     +-- [Overview Tab] (default)
     |   - Character header (name, portrait, pronouns)
     |   - Quick Stats (key attributes)
     |   - Key Abilities (marked as important)
     |   - Recent Items (last 3-5 acquired)
     |
     +-- [Attributes Tab]
     |   - Grouped by category
     |   - Expandable/collapsible groups
     |   - [+ Add Attribute] action
     |
     +-- [Abilities Tab]
     |   - List with expand for description
     |   - Filter by category
     |   - [+ Add Ability] action
     |
     +-- [Inventory Tab]
     |   - Item list with quantity
     |   - Category filters
     |   - [+ Add Item] action
     |
     +-- [Relationships Tab]
     |   - Links to other characters (ally, rival, etc.)
     |   - [+ Add Relationship] action
     |
     +-- [Journal Tab]
         - Chronological entries
         - Filter by type (notes, events, goals)
         - [+ Add Entry] action
```

#### Character Detail Screen (Overview Tab)

```
+----------------------------------+
|  [<- Back]    [Quick View] [...]  |
|                                   |
|  +----+  Elara Nightwhisper       |
|  |    |  she/her                  |
|  |IMG |  Vampire: The Masquerade  |
|  +----+  Seattle by Night         |
|                                   |
|  [Synced] 2 min ago               |
|                                   |
| ================================= |
| Overview|Attr|Abil|Inv|Rel|Journal   |
| ================================= |
|                                   |
|  QUICK STATS                      |
|  +----+ +----+ +----+ +----+      |
|  |Hlth| |Will| |BP  | |Gen |      |
|  | 7  | | 5  | | 3  | | 12 |      |
|  +----+ +----+ +----+ +----+      |
|                                   |
|  KEY ABILITIES                    |
|  +-------------------------------+|
|  | [zap] Dominate               >||
|  | [zap] Presence               >||
|  | [zap] Auspex                 >||
|  +-------------------------------+|
|                                   |
|  CURRENCY (if defined)            |
|  +----+ +----+                    |
|  |Gold| | XP |                    |
|  | 50 | | 12 |                    |
|  +----+ +----+                    |
|                                   |
|  RECENT ITEMS                     |
|  +-------------------------------+|
|  | [pkg] Ancestral Blade    x1  >||
|  | [pkg] Blood Vial         x3  >||
|  +-------------------------------+|
|                                   |
+-----------------------------------+
```

### 3.3 Quick View Flow

#### Context Summary
- **Primary Platform**: Mobile only
- **Environment**: Field (during active gameplay)
- **Connectivity**: Offline-first
- **Primary Role(s)**: Casual Player (primary), Active Player
- **Key Constraints**: Maximum simplicity, largest text, one-hand operation

#### Flow Diagram

```
[Character Detail Screen]
     |
     +-- [Quick View Button] (top right)
     |
     v
[Quick View Overlay]
     |
     +-- Simplified character view
     |   - Large character name
     |   - Key abilities only (expandable)
     |   - Carried items only
     |   - No editing capabilities
     |
     +-- [Exit Quick View] --> back to Character Detail
```

#### Quick View Screen

```
+----------------------------------+
|  [X Exit]           QUICK VIEW   |
|                                  |
|  +----------------------------+  |
|  |                            |  |
|  |    ELARA NIGHTWHISPER      |  |
|  |         she/her            |  |
|  |                            |  |
|  +----------------------------+  |
|                                  |
|  WHAT YOU CAN DO                 |
|  +----------------------------+  |
|  |                            |  |
|  |  [zap] DOMINATE            |  |
|  |  Control minds with a      |  |
|  |  gaze. Cost: 1 Blood       |  |
|  |                            |  |
|  |  [zap] PRESENCE            |  |
|  |  Command attention and     |  |
|  |  awe. Cost: 1 Blood        |  |
|  |                            |  |
|  |  [zap] AUSPEX              |  |
|  |  See beyond the veil.      |  |
|  |  Cost: None                |  |
|  |                            |  |
|  +----------------------------+  |
|                                  |
|  WHAT YOU HAVE                   |
|  +----------------------------+  |
|  |  Ancestral Blade (1)       |  |
|  |  Blood Vial (3)            |  |
|  |  Forged Documents (1)      |  |
|  +----------------------------+  |
|                                  |
|      [View Full Sheet]           |
|                                  |
+----------------------------------+

Design Notes:
- Text is 20% larger than normal views
- High contrast colors always (regardless of theme setting)
- Abilities show short description inline
- Tap ability to see full description in modal
- No edit actions available
```

### 3.4 Portfolio Management Flow

#### Context Summary
- **Primary Platform**: Mobile-first, desktop supported
- **Environment**: Mixed (checking characters at home or event)
- **Connectivity**: Offline-tolerant (cached list works offline)
- **Primary Role(s)**: Active Player
- **Key Constraints**: Quick access to any character, clear organization

#### Portfolio Screen

```
+----------------------------------+
|  RoleKeeper      [Search][+] |
|                                  |
|  [All] [By Game v] [Archived]    |
|                                  |
|  RECENTLY VIEWED                 |
|  +----------------------------+  |
|  | +--+                       |  |
|  | |  | Elara Nightwhisper    |  |
|  | +--+ V:TM - Seattle        |  |
|  |      [synced] 2 min ago    |  |
|  +----------------------------+  |
|  +----------------------------+  |
|  | +--+                       |  |
|  | |  | Marcus Steel          |  |
|  | +--+ D&D - Waterdeep       |  |
|  |      [synced] 1 day ago    |  |
|  +----------------------------+  |
|  +----------------------------+  |
|  | +--+                       |  |
|  | |  | Inspector Chen        |  |
|  | +--+ Murder Mystery        |  |
|  |      [pending sync]        |  |
|  +----------------------------+  |
|                                  |
|  +----------------------------+  |
|  | +--+                       |  |
|  | |  | Thalia Stormwind      |  |
|  | +--+ Chronicles of Dark... |  |
|  |      [offline available]   |  |
|  +----------------------------+  |
|                                  |
+----------------------------------+
|  [Portfolio]  [Events]  [Profile]|
+----------------------------------+
```

#### Empty Portfolio State

```
+----------------------------------+
|  RoleKeeper           [+]    |
|                                  |
|                                  |
|                                  |
|        +------------------+      |
|        |                  |      |
|        |   [user-plus]    |      |
|        |                  |      |
|        +------------------+      |
|                                  |
|    No characters yet             |
|                                  |
|    Create your first character   |
|    to start tracking your        |
|    adventures across games.      |
|                                  |
|    [  Create Character  ]        |
|                                  |
|                                  |
|                                  |
+----------------------------------+
```

### 3.5 Inventory Management Flow

#### Context Summary
- **Primary Platform**: Mobile
- **Environment**: Field (checking items during play) and Desk (managing items)
- **Connectivity**: Offline for viewing, online preferred for editing
- **Primary Role(s)**: Active Player, Casual Player
- **Key Constraints**: Quick scanning of items, easy quantity updates

#### Flow Diagram

```
[Character Detail - Inventory Tab]
     |
     +-- View All Items
     |   - Grouped by category (optional)
     |   - Show quantity, quick info
     |
     +-- [+ Add Item] --> [Add Item Modal]
     |   - Name (required)
     |   - Quantity (default: 1)
     |   - Description (optional)
     |   - Category (optional)
     |
     +-- [Tap Item] --> [Item Detail Modal]
     |   - Full description
     |   - Properties
     |   - Source (where it came from)
     |   - [Edit] [Delete] [Transfer] actions
     |
     +-- [Transfer Item] (Phase 2)
         - Search for recipient character
         - Confirm transfer
         - Await acceptance
```

#### Inventory Tab Screen

```
+----------------------------------+
|  [<- Back]    Inventory    [+]   |
|                                  |
|  +----------------------------+  |
|  | [search...]          [filter]||
|  +----------------------------+  |
|                                  |
|  EQUIPPED                        |
|  +----------------------------+  |
|  | [sword] Ancestral Blade  1 |> |
|  | [shield] Shadow Cloak    1 |> |
|  +----------------------------+  |
|                                  |
|  CONSUMABLES (4)                 |
|  +----------------------------+  |
|  | [vial] Blood Vial        3 |> |
|  | [pill] Antidote          2 |> |
|  | [scroll] Scroll of Ward  1 |> |
|  | [food] Rations           5 |> |
|  +----------------------------+  |
|                                  |
|  QUEST ITEMS (2)                 |
|  +----------------------------+  |
|  | [key] Ancient Key        1 |> |
|  | [doc] Sealed Letter      1 |> |
|  +----------------------------+  |
|                                  |
|  MISC (3)                        |
|  +----------------------------+  |
|  | [coin] Gold Coins       47 |> |
|  | [gem] Ruby              2  |> |
|  | [rope] Silk Rope        1  |> |
|  +----------------------------+  |
|                                  |
+----------------------------------+
```

#### Add Item Modal

```
+----------------------------------+
|  [X Cancel]    Add Item   [Save] |
|                                  |
|  Item Name *                     |
|  +----------------------------+  |
|  | Health Potion              |  |
|  +----------------------------+  |
|                                  |
|  Quantity                        |
|  +----------------------------+  |
|  |  [-]        1         [+]  |  |
|  +----------------------------+  |
|                                  |
|  Category                        |
|  +----------------------------+  |
|  | Consumable               v |  |
|  +----------------------------+  |
|                                  |
|  Description (optional)          |
|  +----------------------------+  |
|  | Restores 2d4+2 hit points |  |
|  | when consumed.             |  |
|  +----------------------------+  |
|                                  |
|  Properties (optional)           |
|  [+ Add Property]                |
|  +----------------------------+  |
|  | Rarity: Common             |  |
|  | Weight: 0.5 lb             |  |
|  +----------------------------+  |
|                                  |
+----------------------------------+
```

### 3.6 Event Registration Flow (Phase 2)

#### Context Summary
- **Primary Platform**: Mobile-first
- **Environment**: Desk (registration usually happens in advance)
- **Connectivity**: Online required
- **Primary Role(s)**: Active Player, Casual Player
- **Key Constraints**: Clear event info, easy character linking

#### Flow Diagram

```
[Events Tab]
     |
     +-- [Discover Events] / [My Events]
     |
     v
[Events List Screen]
     |
     +-- [Tap Event]
     |
     v
[Event Detail Screen]
     |
     +-- View event info (date, location, description)
     +-- View schedule (if available)
     +-- [Register] button
     |
     v
[Registration Flow]
     |
     +-- Select/Create Character for Event
     |   - Choose existing character
     |   - Create new character (uses event template if available)
     |   - Claim pre-generated character (if event offers them)
     |
     +-- Confirm Registration
     |
     v
[Registration Confirmed]
     |
     +-- Character linked to event
     +-- Event appears in "My Events"
```

#### Event Detail Screen

```
+----------------------------------+
|  [<- Back]                 [...] |
|                                  |
|  +----------------------------+  |
|  |                            |  |
|  |     [Event Banner/Image]   |  |
|  |                            |  |
|  +----------------------------+  |
|                                  |
|  Shadows of Seattle              |
|  Vampire: The Masquerade         |
|                                  |
|  [calendar] Jan 15-17, 2026      |
|  [map-pin]  Camp Woodland, WA    |
|  [users]    42 / 60 registered   |
|                                  |
|  +----------------------------+  |
|  |                            |  |
|  |  [ Register for Event ]    |  |
|  |                            |  |
|  +----------------------------+  |
|                                  |
| ================================ |
| Info | Schedule | Characters     |
| ================================ |
|                                  |
|  ABOUT THIS EVENT                |
|                                  |
|  A weekend of gothic horror      |
|  in the Pacific Northwest.       |
|  New and experienced players     |
|  welcome...                      |
|                                  |
|  ORGANIZER                       |
|  Morgan's LARP Productions       |
|                                  |
+----------------------------------+
```

### 3.7 Organizer Dashboard Flow (Phase 2)

#### Context Summary
- **Primary Platform**: Desktop/Web (primary), Mobile (during events)
- **Environment**: Desk for planning, Field during events
- **Connectivity**: Online for planning, offline-tolerant during events
- **Primary Role(s)**: Organizer (Morgan)
- **Key Constraints**: Information density, bulk operations, quick player lookup

#### Flow Diagram

```
[Organizer Dashboard]
     |
     +-- Overview
     |   - Upcoming events summary
     |   - Recent registrations
     |   - Quick stats
     |
     +-- Events Management
     |   - List of organized events
     |   - Create new event
     |   - Event status indicators
     |
     +-- [Select Event] --> Event Management
         |
         +-- Registrations
         |   - Player list with search
         |   - Character assignments
         |   - Approval workflow
         |
         +-- Characters
         |   - All event characters
         |   - Pre-generated characters
         |   - Push updates to players
         |
         +-- Schedule
         |   - Timeline editor
         |   - Scene management
         |
         +-- Item Catalog
         |   - Define event items
         |   - Distribute to players
         |
         +-- Settings
             - Event details
             - Permissions
             - Templates
```

#### Organizer Dashboard (Desktop Layout)

```
+------------------------------------------------------------------+
|  [Logo] RoleKeeper                    [Profile] Morgan Smith  |
+--------+---------------------------------------------------------+
|        |                                                          |
| PLAYER |  ORGANIZER DASHBOARD                                     |
| -------|                                                          |
| Chars  |  Welcome back, Morgan                                    |
| Events |                                                          |
|        |  +------------------+ +------------------+                |
| ORGAN. |  | UPCOMING EVENTS  | | RECENT ACTIVITY |                |
| -------|  |                  | |                  |                |
| Events |  | Shadows of       | | [user] Alex reg |                |
| Templ. |  | Seattle          | |   for Shadows   |                |
| Plot   |  | Jan 15 | 42/60   | | [user] Pat reg  |                |
|        |  |                  | |   for Shadows   |                |
|        |  | Murder at the    | | [edit] You upd. |                |
|        |  | Manor            | |   event details |                |
|        |  | Feb 8 | 8/12     | |                  |                |
|        |  |                  | |                  |                |
|        |  | [+ New Event]    | | [View All]      |                |
|        |  +------------------+ +------------------+                |
|        |                                                          |
|        |  +------------------------------------------------+      |
|        |  | QUICK STATS                                     |     |
|        |  |                                                 |     |
|        |  | Total Players: 127  |  Events: 4  |  PreGens: 23|     |
|        |  +------------------------------------------------+      |
|        |                                                          |
+--------+---------------------------------------------------------+
```

#### Event Management Screen (Desktop)

```
+------------------------------------------------------------------+
|  [<- Dashboard]   Shadows of Seattle                   [Settings] |
+------------------------------------------------------------------+
|                                                                   |
|  [Registrations] [Characters] [Schedule] [Items] [Plot]           |
|                                                                   |
+------------------------+------------------------------------------+
|                        |                                          |
| REGISTRATIONS (42)     | PLAYER DETAILS                          |
|                        |                                          |
| [Search players...]    | Alex Thompson                           |
|                        | alex@email.com                          |
| [Filter: All v]        |                                          |
|                        | CHARACTER                                |
| +--------------------+ | Elara Nightwhisper                      |
| | [check] Alex T.    | | Clan: Ventrue | Status: Approved        |
| |   Elara Nightwh... | |                                          |
| +--------------------+ | [View Character] [Message Player]        |
| | [check] Pat R.     | |                                          |
| |   Marcus Steel     | | REGISTRATION                            |
| +--------------------+ | Registered: Dec 1, 2025                 |
| | [clock] Sam L.     | | Status: Approved                        |
| |   (No character)   | | Notes: Experienced player, prefers      |
| +--------------------+ |         combat scenarios                 |
| | [clock] Jordan K.  | |                                          |
| |   (Pending)        | | [Approve] [Waitlist] [Remove]           |
| +--------------------+ |                                          |
|                        |                                          |
| [Bulk Actions v]       |                                          |
|                        |                                          |
+------------------------+------------------------------------------+
```

---

## 4. Screen Specifications

### 4.1 Authentication Screens

#### Login Screen

**Purpose**: Authenticate existing users

**States**:
- Default: Email and password fields empty, buttons enabled
- Loading: Form disabled, primary button shows spinner
- Error: Error message displayed, relevant field highlighted
- Offline: Show "No internet connection" banner, disable submit

**Layout**:
```
+----------------------------------+
|                                  |
|          [App Logo]              |
|                                  |
|         Welcome Back             |
|                                  |
|  Email                           |
|  +----------------------------+  |
|  |                            |  |
|  +----------------------------+  |
|                                  |
|  Password                        |
|  +----------------------------+  |
|  |                        [eye]| |
|  +----------------------------+  |
|  [Forgot Password?]              |
|                                  |
|  [     Sign In (Primary)     ]   |
|                                  |
|  -------- or --------            |
|                                  |
|  [G] Continue with Google        |
|  [] Continue with Apple         |
|                                  |
|  Don't have an account?          |
|  [Sign Up]                       |
|                                  |
+----------------------------------+
```

**Interactions**:
- Email field: Text input, email keyboard on mobile
- Password field: Secure text, toggle visibility icon
- Sign In: Validate inputs, show loading, navigate on success
- Social buttons: Launch OAuth flow
- Forgot Password: Navigate to password reset screen
- Sign Up link: Navigate to registration

**Validation**:
- Email: Required, valid email format
- Password: Required, min 8 characters

**Error States**:
- Invalid credentials: "Email or password is incorrect"
- Network error: "Unable to connect. Check your internet connection."
- Too many attempts: "Too many failed attempts. Try again in X minutes."

### 4.2 Portfolio Screen

**Purpose**: Display all user's characters, primary app home screen

**States**:
- Loading: Skeleton loaders for character cards
- Empty: Empty state with create prompt
- Populated: Character list with sync status
- Offline: Offline banner, cached characters shown
- Error: Error banner with retry option

**Layout Components**:

1. **App Bar**
   - Title: "RoleKeeper" or custom greeting
   - Search icon: Opens search overlay
   - Create button: FAB or app bar action

2. **Filter Chips**
   - Horizontal scrollable
   - Options: All, By Game, Archived
   - Selected state visually distinct

3. **Character List**
   - Vertical scrolling list
   - Character cards (see component spec)
   - Pull-to-refresh on mobile

4. **FAB (Floating Action Button)**
   - Bottom right on mobile
   - [+] icon
   - Navigate to Create Character

**Offline Behavior**:
- Show cached characters immediately
- Display offline banner at top
- Sync status shows "Last synced: X ago"
- Create action queues for later sync

### 4.3 Character Detail Screen

**Purpose**: Display complete character information with tabbed sections

**States**:
- Loading: Skeleton loader for header and content
- Populated: Full character data displayed
- Offline: Offline indicator, cached data shown
- Syncing: Sync indicator in header
- Error: Error message with retry

**Layout**:

```
+----------------------------------+
|  [<-]  Character     [QV] [...] |
+----------------------------------+
|  +----+                          |
|  |IMG | Character Name           |
|  |    | pronouns                 |
|  +----+ Game System              |
|         Campaign                 |
|  [Sync Status: Synced]           |
+----------------------------------+
| [Overview][Attr][Abil][Inv][Rel][Jrnl]|
+----------------------------------+
|                                  |
|  Tab Content Area                |
|  (scrollable)                    |
|                                  |
|                                  |
|                                  |
+----------------------------------+
```

**Tab Content**:

1. **Overview Tab**
   - Quick Stats grid (4 key attributes)
   - Key Abilities list (expandable)
   - Recent Items (last 5)
   - Quick actions: Edit, Quick View

2. **Attributes Tab**
   - Grouped by category
   - Collapsible category headers
   - Each attribute: name, value, edit affordance
   - FAB: Add Attribute

3. **Abilities Tab**
   - List with icon, name, short description
   - Tap to expand full description
   - Filter by category
   - FAB: Add Ability

4. **Inventory Tab**
   - Grouped by category (optional)
   - Each item: icon, name, quantity
   - Tap for item detail modal
   - FAB: Add Item

5. **Relationships Tab**
   - Links to other characters (target, type, description)
   - FAB: Add Relationship

6. **Journal Tab**
   - Chronological list
   - Each entry: date, title, preview
   - Filter by entry type
   - FAB: Add Entry

**Header Actions**:
- Back: Navigate to Portfolio
- Quick View: Open Quick View overlay
- More (...): Edit, Archive, Delete, Share (future)

### 4.4 Quick View Screen

**Purpose**: Simplified, high-contrast view for field reference

**Design Requirements**:
- Maximum readability in outdoor conditions
- Larger text (20% increase from normal)
- High contrast (always, regardless of theme)
- Minimal interaction needed
- No editing capabilities

**Layout**:
```
+----------------------------------+
|  [X Exit]           QUICK VIEW   |
+----------------------------------+
|                                  |
|  +----------------------------+  |
|  |                            |  |
|  |    CHARACTER NAME          |  |
|  |       pronouns             |  |
|  |                            |  |
|  +----------------------------+  |
|                                  |
|  WHAT YOU CAN DO                 |
|  +----------------------------+  |
|  |                            |  |
|  |  ABILITY NAME              |  |
|  |  Short description that    |  |
|  |  explains the ability.     |  |
|  |                            |  |
|  |  ABILITY NAME              |  |
|  |  Another description.      |  |
|  |                            |  |
|  +----------------------------+  |
|                                  |
|  WHAT YOU HAVE                   |
|  +----------------------------+  |
|  |  Item Name (qty)           |  |
|  |  Item Name (qty)           |  |
|  |  Item Name (qty)           |  |
|  +----------------------------+  |
|                                  |
|       [View Full Sheet]          |
|                                  |
+----------------------------------+
```

**Interactions**:
- Exit (X): Close Quick View, return to Character Detail
- Tap ability: Show full description in modal
- Tap item: Show item details in modal
- View Full Sheet: Close Quick View, return to Character Detail

### 4.5 Character Create/Edit Screen

**Purpose**: Create new character or edit existing

**Mode Differences**:
- Create: Empty form, "Create" button
- Edit: Pre-populated, "Save Changes" button

**Layout**:
```
+----------------------------------+
|  [X Cancel]    Create     [Save] |
|                                  |
|  +----------------------------+  |
|  |      [+ Add Portrait]      |  |
|  +----------------------------+  |
|                                  |
|  Character Name *                |
|  +----------------------------+  |
|  |                            |  |
|  +----------------------------+  |
|                                  |
|  Pronouns                        |
|  +----------------------------+  |
|  |                            |  |
|  +----------------------------+  |
|                                  |
|  Game System                     |
|  +----------------------------+  |
|  |                          v |  |
|  +----------------------------+  |
|                                  |
|  Campaign / Game                 |
|  +----------------------------+  |
|  |                            |  |
|  +----------------------------+  |
|                                  |
|  Description                     |
|  +----------------------------+  |
|  |                            |  |
|  |                            |  |
|  +----------------------------+  |
|                                  |
|  (Edit mode only)                |
|  [Archive Character]             |
|  [Delete Character]              |
|                                  |
+----------------------------------+
```

**Validation**:
- Name: Required, non-empty
- All other fields: Optional

**Save Behavior**:
- Online: Save to Firestore, navigate to character detail
- Offline: Save locally, queue sync, navigate with "pending" status

### 4.6 Add Modals

#### Add Attribute Modal

```
+----------------------------------+
|  [X Cancel]  Add Attribute [Save]|
|                                  |
|  Attribute Name *                |
|  +----------------------------+  |
|  | Strength                   |  |
|  +----------------------------+  |
|                                  |
|  Value Type                      |
|  [Number] [Text] [Rating] [Bool] |
|                                  |
|  Value                           |
|  +----------------------------+  |
|  | 3                          |  |
|  +----------------------------+  |
|  (For Rating: show dot selector) |
|                                  |
|  Max Value (for ratings)         |
|  +----------------------------+  |
|  | 5                          |  |
|  +----------------------------+  |
|                                  |
|  Category                        |
|  +----------------------------+  |
|  | Physical                 v |  |
|  +----------------------------+  |
|                                  |
|  [ ] Show in Quick Stats         |
|                                  |
+----------------------------------+
```

#### Add Ability Modal

```
+----------------------------------+
|  [X Cancel]   Add Ability  [Save]|
|                                  |
|  Type                            |
|  +----------------------------+  |
|  | Ability | Advantage | Disadv|  |
|  +----------------------------+  |
|                                  |
|  Ability Name *                  |
|  +----------------------------+  |
|  | Dominate                   |  |
|  +----------------------------+  |
|                                  |
|  Description *                   |
|  +----------------------------+  |
|  | Control the minds of       |  |
|  | others with a commanding   |  |
|  | gaze...                    |  |
|  +----------------------------+  |
|                                  |
|  Category                        |
|  +----------------------------+  |
|  | Discipline               v |  |
|  +----------------------------+  |
|                                  |
|  Cost                            |
|  +----------------------------+  |
|  | 1 Blood Point              |  |
|  +----------------------------+  |
|                                  |
|  Duration                        |
|  +----------------------------+  |
|  | 1 Scene                    |  |
|  +----------------------------+  |
|                                  |
|  [ ] Mark as Key Ability         |
|                                  |
+----------------------------------+
```

#### Add Relationship Modal

```
+----------------------------------+
|  [X Cancel] Add Relationship [Save]|
|                                  |
|  Target Character *              |
|  +----------------------------+  |
|  | [Search characters...]   v |  |
|  +----------------------------+  |
|                                  |
|  Relationship Type *             |
|  +----------------------------+  |
|  | Ally | Rival | Mentor | ... v|  |
|  +----------------------------+  |
|                                  |
|  Description (optional)          |
|  +----------------------------+  |
|  | Former mentor, now estranged   |
|  +----------------------------+  |
|                                  |
|  [ ] Mutual (both characters     |
|      have this relationship)      |
|                                  |
+----------------------------------+
```

#### Add Item Modal

```
+----------------------------------+
|  [X Cancel]    Add Item    [Save]|
|                                  |
|  Item Name *                     |
|  +----------------------------+  |
|  | Silver Dagger              |  |
|  +----------------------------+  |
|                                  |
|  Quantity                        |
|      [-]       1       [+]       |
|                                  |
|  Category                        |
|  +----------------------------+  |
|  | Weapon                   v |  |
|  +----------------------------+  |
|                                  |
|  Description                     |
|  +----------------------------+  |
|  | A blessed silver blade,   |  |
|  | effective against...      |  |
|  +----------------------------+  |
|                                  |
|  Properties                      |
|  +----------------------------+  |
|  | Damage: 1d4+1 piercing     |  |
|  | [+ Add Property]           |  |
|  +----------------------------+  |
|                                  |
+----------------------------------+
```

### 4.7 Events List Screen (Phase 2)

**Purpose**: Browse and discover events

**Tabs**:
- My Events: Registered events (upcoming first)
- Discover: Public events near user/of interest

**Layout**:
```
+----------------------------------+
|  [<-]     Events        [Search] |
|                                  |
|  [My Events] [Discover]          |
|                                  |
|  UPCOMING                        |
|  +----------------------------+  |
|  | Shadows of Seattle         |  |
|  | Jan 15-17 | Camp Woodland  |  |
|  | [Playing: Elara]           |  |
|  +----------------------------+  |
|                                  |
|  +----------------------------+  |
|  | Murder at the Manor        |  |
|  | Feb 8 | Downtown Seattle   |  |
|  | [Playing: Inspector Chen]  |  |
|  +----------------------------+  |
|                                  |
|  PAST                            |
|  +----------------------------+  |
|  | Night of Shadows           |  |
|  | Nov 12 | Completed         |  |
|  +----------------------------+  |
|                                  |
+----------------------------------+
```

### 4.8 Organizer Dashboard (Phase 2)

**Purpose**: Central hub for event organization

**Platform**: Desktop-first, mobile-responsive

**Sections**:
1. Overview: Stats, recent activity, quick actions
2. Events: List of organized events
3. Templates: Character templates (reusable)
4. Plot (Phase 3): Plot thread management

**Desktop Layout**: See flow diagram in Section 3.7

**Mobile Layout**:
```
+----------------------------------+
|  [menu]  Organizer          [+]  |
|                                  |
|  Welcome back, Morgan            |
|                                  |
|  QUICK STATS                     |
|  +-------+ +-------+ +-------+   |
|  |Players| |Events | |PreGens|   |
|  |  127  | |   4   | |  23   |   |
|  +-------+ +-------+ +-------+   |
|                                  |
|  UPCOMING EVENTS                 |
|  +----------------------------+  |
|  | Shadows of Seattle         |  |
|  | Jan 15 | 42/60 registered  |  |
|  | [Manage]                   |  |
|  +----------------------------+  |
|  +----------------------------+  |
|  | Murder at the Manor        |  |
|  | Feb 8 | 8/12 registered    |  |
|  | [Manage]                   |  |
|  +----------------------------+  |
|                                  |
|  [View All Events]               |
|                                  |
|  RECENT ACTIVITY                 |
|  +----------------------------+  |
|  | Alex registered for        |  |
|  | Shadows of Seattle         |  |
|  | 2 hours ago                |  |
|  +----------------------------+  |
|                                  |
+----------------------------------+
```

---

## 5. Component Library

### 5.1 Buttons

#### Primary Button

```
Usage: Main actions (Create, Save, Register)
Style:
- Background: Primary color (#6366F1)
- Text: White, Title weight
- Padding: 16px horizontal, 12px vertical
- Border Radius: 8px
- Min Height: 48px (touch target)

States:
- Default: Primary background
- Hover: Primary Dark background
- Pressed: Primary Dark + slight scale (0.98)
- Disabled: 50% opacity, no interaction
- Loading: Spinner replaces text
```

#### Secondary Button

```
Usage: Alternative actions (Cancel, Back)
Style:
- Background: Transparent
- Border: 1px Primary color
- Text: Primary color, Title weight
- Padding: 16px horizontal, 12px vertical
- Border Radius: 8px

States:
- Default: Transparent with border
- Hover: Primary at 10% opacity background
- Pressed: Primary at 20% opacity
- Disabled: 50% opacity
```

#### Text Button

```
Usage: Tertiary actions (Learn more, Forgot password)
Style:
- Background: None
- Text: Primary color, Body Large weight
- Padding: 8px

States:
- Default: Primary text
- Hover: Underline
- Pressed: Primary Dark text
- Disabled: Text Disabled color
```

#### Icon Button

```
Usage: Action icons (Edit, Delete, More)
Style:
- Background: Transparent or Surface
- Icon: 24px, Text Primary or Text Secondary
- Size: 48px x 48px (touch target)
- Border Radius: Full (circular)

States:
- Default: Transparent
- Hover: Surface background
- Pressed: Surface + slight scale
```

#### FAB (Floating Action Button)

```
Usage: Primary creation action on list screens
Style:
- Background: Primary color
- Icon: 24px, White, plus icon
- Size: 56px x 56px
- Border Radius: Full (circular)
- Shadow: Elevation Level 3
- Position: Bottom right, 16px from edges

States:
- Default: Primary background
- Hover: Primary Dark + lift shadow
- Pressed: Scale (0.95)
```

### 5.2 Cards

#### Character Card

```
Usage: Portfolio list item
Style:
- Background: Surface Elevated
- Padding: 16px
- Border Radius: 12px
- Shadow: Elevation Level 1

Structure:
+----------------------------------+
| +--+                             |
| |  | Character Name      [sync] |
| |  | Game System                 |
| +--+ Campaign/Game               |
|      [Status Indicator]          |
+----------------------------------+

Elements:
- Avatar: 48px, rounded square (8px radius)
- Name: Title weight, Text Primary
- Game: Body, Text Secondary
- Campaign: Body Small, Text Secondary
- Sync Status: Caption + icon
- Chevron: Right arrow indicating navigation
```

#### Event Card

```
Usage: Event list item
Style:
- Background: Surface Elevated
- Padding: 16px
- Border Radius: 12px
- Shadow: Elevation Level 1

Structure:
+----------------------------------+
| Event Name                       |
| [calendar] Date Range            |
| [map-pin] Location               |
| [users] X/Y registered           |
| [Character: Name] (if registered)|
+----------------------------------+
```

#### Stat Card (Quick Stats)

```
Usage: Attribute display in Quick Stats grid
Style:
- Background: Surface
- Padding: 12px
- Border Radius: 8px
- Border: 1px Border color

Structure:
+--------+
|  NAME  |
| VALUE  |
+--------+

Elements:
- Name: Caption, Text Secondary, centered
- Value: Headline 3, Text Primary, centered
```

### 5.3 Form Inputs

#### Text Field

```
Style:
- Background: Surface (light) or slightly elevated (dark)
- Border: 1px Border color
- Border Radius: 8px
- Padding: 12px 16px
- Min Height: 48px

States:
- Default: Border color border
- Focused: Primary color border (2px)
- Error: Error color border, error message below
- Disabled: 50% opacity, no interaction

Label:
- Position: Above field
- Style: Body, Text Primary
- Required indicator: * in Error color

Helper Text:
- Position: Below field
- Style: Caption, Text Secondary
- Error: Caption, Error color
```

#### Dropdown / Select

```
Style: Same as Text Field with dropdown indicator
- Chevron down icon on right
- Opens platform-native picker or custom bottom sheet

Selection Display:
- Show selected option text
- Placeholder if none selected
```

#### Rating Input (Dots)

```
Usage: RPG-style dot ratings (1-5, 1-10)
Style:
- Row of circular dots
- Filled: Primary color
- Empty: Border color outline
- Size: 20px diameter, 8px gap

Interaction:
- Tap dot to set value
- Drag across to set value
- Shows numeric value optionally
```

#### Search Field

```
Style:
- Background: Surface
- Border Radius: Full (pill shape)
- Padding: 8px 16px
- Leading icon: Search
- Trailing icon: Clear (X) when has value

Behavior:
- Debounced search (300ms)
- Show recent searches on focus
- Clear button clears and focuses
```

### 5.4 Lists

#### Simple List Item

```
Style:
- Padding: 16px horizontal, 12px vertical
- Border Bottom: 1px Border color (optional)
- Min Height: 56px

Structure:
+----------------------------------+
| [icon] Primary Text        [>]   |
|        Secondary Text            |
+----------------------------------+
```

#### Expandable List Item

```
Style: Same as Simple, with expand/collapse
- Chevron rotates on expand
- Content area slides in below

Expanded Content:
- Additional padding (16px)
- Background slightly darker
```

#### Grouped List

```
Style:
- Section header: Overline style, 8px bottom margin
- Items grouped under header
- Optional collapse per section
```

### 5.5 Navigation

#### Bottom Tab Bar

```
Style:
- Background: Surface Elevated
- Height: 56px + safe area
- Shadow: Elevation Level 2 (top shadow)
- Border Top: 1px Border color (optional)

Tab Item:
- Icon: 24px
- Label: Caption
- Active: Primary color
- Inactive: Text Secondary
- Size: Equal width distribution
```

#### App Bar

```
Style:
- Background: Background (scrolled: Surface Elevated)
- Height: 56px + status bar
- Padding: 16px horizontal

Structure:
+----------------------------------+
| [back] Title              [act1] |
+----------------------------------+

Elements:
- Back: Icon button, arrow-left
- Title: Title style, centered or left-aligned
- Actions: Up to 3 icon buttons
```

#### Tab Bar (Content Tabs)

```
Style:
- Background: Transparent
- Height: 48px
- Border Bottom: 2px transparent

Tab:
- Text: Body, Text Secondary (inactive), Primary (active)
- Indicator: 2px Primary bar below active tab
- Padding: 16px horizontal

Behavior:
- Scrollable if more than 4 tabs
- Swipe to change tabs (mobile)
```

### 5.6 Modals and Overlays

#### Bottom Sheet

```
Usage: Add forms, filters, quick actions
Style:
- Background: Surface Elevated
- Border Radius: 16px top corners
- Handle: 40px x 4px, centered, Border Strong color
- Padding: 16px
- Max Height: 90% screen

Behavior:
- Drag handle to resize/dismiss
- Tap outside to dismiss (optional)
- Keyboard aware (shifts up)
```

#### Modal Dialog

```
Usage: Confirmations, alerts, complex forms
Style:
- Background: Surface Elevated
- Border Radius: 16px
- Padding: 24px
- Max Width: 400px (centered)
- Backdrop: Black at 50% opacity

Structure:
+----------------------------------+
|           Title                  |
|                                  |
|  Content / Message               |
|                                  |
|  [Secondary]      [Primary]      |
+----------------------------------+
```

#### Snackbar / Toast

```
Usage: Feedback messages, undo actions
Style:
- Background: Gray-800 (dark on both themes)
- Text: White
- Border Radius: 8px
- Padding: 12px 16px
- Position: Bottom center, 16px from bottom nav

Structure:
+----------------------------------+
| Message text              [Undo] |
+----------------------------------+

Behavior:
- Auto-dismiss after 4 seconds
- Swipe to dismiss
- Action button optional
```

### 5.7 Status Indicators

#### Sync Status Badge

```
Variants:
- Synced: Check icon, Emerald, "Synced"
- Syncing: Rotating refresh icon, Blue, "Syncing..."
- Pending: Clock icon, Amber, "Pending"
- Offline: Wifi-off icon, Gray, "Offline"
- Error: Alert icon, Red, "Sync failed"

Style:
- Icon: 16px
- Text: Caption
- Layout: Icon + text inline
- Gap: 4px
```

#### Offline Banner

```
Usage: Top of screen when offline
Style:
- Background: Amber (warning)
- Text: Dark text
- Height: 32px
- Full width

Content:
[wifi-off] You're offline. Some features unavailable.

Behavior:
- Appears when connectivity lost
- Dismissible or persistent
- Animates in from top
```

#### Connection Status Dot

```
Usage: Compact status indicator in headers
Style:
- Size: 8px circle
- Colors: Emerald (online), Amber (syncing), Red (offline)
- Position: Near sync text or standalone
```

---

## 6. Accessibility Standards

### 6.1 WCAG 2.1 Compliance

RoleKeeper targets **WCAG 2.1 Level AA** compliance with selective AAA targets for field-critical features.

#### Perceivable

1. **Text Alternatives**
   - All icons have accessible labels
   - Images have alt text
   - Decorative images are hidden from screen readers

2. **Adaptable**
   - Logical reading order matches visual order
   - Content structure uses proper headings (H1-H6)
   - Forms use proper labels and fieldsets

3. **Distinguishable**
   - Color contrast: 4.5:1 minimum for normal text
   - Color contrast: 3:1 minimum for large text (18px+)
   - Color contrast: 7:1 for Quick View (field use)
   - No information conveyed by color alone
   - Text resizable to 200% without loss

#### Operable

1. **Keyboard Accessible**
   - All functions available via keyboard (web)
   - Logical tab order
   - No keyboard traps
   - Skip links for main content

2. **Enough Time**
   - No time limits on user actions
   - Toasts allow sufficient reading time (4+ seconds)
   - Animations can be paused/disabled

3. **Navigable**
   - Page titles descriptive
   - Focus visible on all interactive elements
   - Multiple ways to navigate (tabs, search, breadcrumbs)
   - Clear focus indicators (2px Primary outline)

4. **Input Modalities**
   - Touch targets: 48px minimum
   - Gesture alternatives available
   - Motion actuation has alternatives

#### Understandable

1. **Readable**
   - Language identified (lang attribute)
   - Clear, simple language
   - Abbreviations explained

2. **Predictable**
   - Consistent navigation
   - Consistent identification
   - No unexpected context changes

3. **Input Assistance**
   - Error identification
   - Labels and instructions
   - Error prevention for destructive actions

#### Robust

1. **Compatible**
   - Valid markup
   - ARIA used appropriately
   - Status messages announced

### 6.2 Mobile Accessibility

#### Touch Targets
- Minimum size: 48x48px
- Recommended size: 56x56px for field use
- Spacing between targets: 8px minimum

#### Screen Reader Support
- VoiceOver (iOS) tested
- TalkBack (Android) tested
- Semantic Flutter widgets used
- Custom accessibility labels where needed

#### Gestures
- All swipe gestures have button alternatives
- Pull-to-refresh indicated visually
- Haptic feedback for confirmations

### 6.3 Visual Accessibility

#### Color Blindness Considerations
- Never use color as sole indicator
- Use icons alongside color status indicators
- Tested with Protanopia, Deuteranopia, Tritanopia simulations

#### High Contrast Mode
- System high contrast settings respected
- Custom high contrast toggle in settings
- Increased border visibility
- No subtle color differences for critical info

#### Reduced Motion
- System reduced motion settings respected
- Animations replaced with instant transitions
- Loading spinners simplified

### 6.4 Accessibility Testing Checklist

Per screen/feature:
- [ ] Tab order is logical
- [ ] All elements have accessible names
- [ ] Color contrast passes (4.5:1 / 3:1)
- [ ] Focus visible on all interactive elements
- [ ] Screen reader announces content correctly
- [ ] Touch targets are 48px minimum
- [ ] Works without color perception
- [ ] Works with 200% zoom
- [ ] Error messages are announced
- [ ] Form labels are associated

---

## 7. Platform Adaptations

### 7.1 Orientation Support (Portrait and Landscape)

**Requirement**: All screens must work in both portrait and landscape. The app does not lock orientation.

| Orientation | Behavior |
|-------------|----------|
| **Portrait** | Single-column layouts; bottom navigation; vertical scrolling; optimized for one-handed use |
| **Landscape** | Master-detail or multi-column where appropriate; sidebar navigation on tablet/desktop; horizontal space utilized for lists + detail |

**Implementation**:
- Use `OrientationBuilder` or media query for orientation-aware layouts
- Mobile: Bottom nav in both orientations; character list stacks in portrait, side-by-side in landscape when space allows
- Tablet: Master-detail in landscape; single column in portrait
- Ensure touch targets and text remain accessible in both orientations
- Test character sheet readability in landscape (common when device is propped or held sideways in field)

### 7.2 Responsive Breakpoints

```
Mobile Small:   320px - 374px  (iPhone SE, older Android)
Mobile:         375px - 767px  (Standard phones)
Tablet:         768px - 1023px (iPad, Android tablets)
Desktop:        1024px - 1439px (Laptops, small monitors)
Desktop Large:  1440px+        (Large monitors)
```

### 7.3 Layout Adaptations

#### Mobile (< 768px)

**Navigation**: Bottom tab bar (both orientations)
**Layout**: Single column in portrait; in landscape, consider master-detail when width allows (e.g., character list + detail)
**Touch**: Large targets (48px+), swipe gestures
**Modals**: Full-screen or bottom sheet
**Lists**: Full-width, vertical scroll
**Orientation**: Must work in portrait and landscape; no locking

```
Portrait:
+----------------------------------+
|           App Bar                |
+----------------------------------+
|         Single Column            |
|           Content                |
+----------------------------------+
|         Bottom Nav               |
+----------------------------------+

Landscape:
+------------------------------------------+
|              App Bar                     |
+------------------------------------------+
|  List (narrow)  |    Detail / Content     |
+------------------------------------------+
|              Bottom Nav                  |
+------------------------------------------+
```

#### Tablet (768px - 1023px)

**Navigation**: Bottom tab bar or sidebar (landscape)
**Layout**: Two-column where appropriate
**Lists**: Master-detail on landscape
**Modals**: Centered, max-width constrained

```
Portrait:
+----------------------------------+
|           App Bar                |
+----------------------------------+
|                                  |
|      Wider Single Column         |
|      (max-width: 600px)          |
|                                  |
+----------------------------------+
|         Bottom Nav               |
+----------------------------------+

Landscape:
+------------+---------------------+
|            |                     |
|   Master   |      Detail         |
|   List     |      View           |
|            |                     |
+------------+---------------------+
```

#### Desktop (1024px+)

**Navigation**: Sidebar (collapsible)
**Layout**: Multi-column, side panels
**Lists**: Master-detail default
**Modals**: Centered dialog, not full-screen

```
+--------+------------------------+
|        |                        |
| Sidebar|     Main Content       |
|        |                        |
| [Nav]  |  +-------+ +-------+   |
|        |  | Panel | | Panel |   |
|        |  +-------+ +-------+   |
|        |                        |
+--------+------------------------+
```

### 7.4 Platform-Specific Patterns

#### iOS Adaptations

- Navigation: iOS-style back gesture (swipe from edge)
- Modals: iOS sheet presentation style
- Inputs: Cupertino-style date pickers
- Typography: SF Pro system font
- Bottom sheet: iOS modal sheet appearance

#### Android Adaptations

- Navigation: Android back button support
- Modals: Material bottom sheets
- Inputs: Material date pickers
- Typography: Roboto or system font
- FAB: Material Design FAB behavior

#### Web Adaptations

- Navigation: Sidebar + breadcrumbs
- Keyboard: Full keyboard navigation
- Right-click: Context menus where appropriate
- Hover states: All interactive elements
- Focus: Visible focus rings
- Responsive: Adapts to window resize

### 7.5 Feature Availability by Platform

| Feature | Mobile | Tablet | Desktop |
|---------|--------|--------|---------|
| Character Management | Full | Full | Full |
| Quick View | Full (optimized) | Full | Available |
| Offline Mode | Full | Full | Limited (PWA) |
| Event Management | Basic | Full | Full |
| Organizer Dashboard | Limited | Full | Full (optimized) |
| Plot Management | Hidden | Basic | Full |
| Bulk Operations | Limited | Full | Full |
| Keyboard Shortcuts | N/A | Optional | Full |

---

## 8. Offline UX Patterns

### 8.1 Connectivity States

RoleKeeper defines four connectivity states:

1. **Online**: Full connectivity, real-time sync
2. **Syncing**: Connected, actively synchronizing
3. **Offline**: No connectivity, using cached data
4. **Error**: Sync failed, requires attention

### 8.2 Visual Indicators

#### Global Offline Banner

```
Position: Top of screen, below app bar
Appearance: Amber background, dark text
Content: "[wifi-off] You're offline. Changes will sync when connected."
Behavior: Appears on connectivity loss, dismisses on restoration
```

#### Sync Status in Headers

```
Location: Character detail header, portfolio items
Display: Icon + text (e.g., "Synced 2 min ago")
Variants:
- Synced: Check icon, emerald, "Synced X ago"
- Syncing: Animated refresh, blue, "Syncing..."
- Pending: Clock icon, amber, "Changes pending"
- Error: Alert icon, red, "Sync failed"
```

#### Item-Level Indicators

```
On character cards:
- Dot indicator (colored by status)
- Text label on hover/tap

On form fields after edit:
- Visual indicator that change is queued
```

### 8.3 Offline Behaviors by Feature

| Feature | Online Behavior | Offline Behavior |
|---------|-----------------|------------------|
| View Portfolio | Real-time list | Cached list, no new data |
| View Character | Live data | Cached data with indicator |
| Edit Character | Instant save | Queue for sync, local save |
| Create Character | Instant create | Local create, queue sync |
| Add Item | Instant save | Local save, queue sync |
| View Events | Real-time list | Cached registrations only |
| Register for Event | Instant | Blocked with message |
| Quick View | Works | Works (cached data) |
| Search | Live search | Search cached data only |

### 8.4 Offline Action Handling

#### Allowed Offline (with queuing)
- Edit character basic info
- Add/edit attributes
- Add/edit abilities
- Add/edit inventory items
- Add journal entries
- View all cached characters

#### Blocked Offline (with clear messaging)
- Create new account
- Sign in
- Register for events
- Transfer items to other players
- Claim pre-generated characters
- Access characters not previously cached

#### Offline Messaging

**Blocked Action Modal**:
```
+----------------------------------+
|                                  |
|      [wifi-off]                  |
|                                  |
|   You're currently offline       |
|                                  |
|   This action requires an        |
|   internet connection.           |
|                                  |
|        [Okay, got it]            |
|                                  |
+----------------------------------+
```

**Queued Action Feedback**:
```
Snackbar: "Changes saved. Will sync when online."
```

### 8.5 Sync Conflict Resolution

#### Strategy: Last-Write-Wins with User Notification

When a conflict is detected:
1. Remote version is applied (wins)
2. User is notified of the change
3. Local backup is preserved (accessible in settings)

#### Conflict Notification

```
+----------------------------------+
|  Your character was updated      |
|                                  |
|  Some changes you made were      |
|  overwritten by an organizer     |
|  update. Your original changes   |
|  are saved in version history.   |
|                                  |
|  [View Changes]   [Dismiss]      |
+----------------------------------+
```

### 8.6 Cache Management

#### Automatic Caching
- Characters: Cached on first view
- Cache duration: 7 days
- Max characters: User configurable (default: 20)
- Images: Cached on download, 30-day expiry

#### Manual Cache Control
Settings > Offline:
- View cached characters
- Clear cache
- Prioritize specific characters
- Set offline character limit

### 8.7 Empty States

Empty states should guide users toward action while setting appropriate expectations.

#### 8.7.1 Portfolio Empty States

**First-Time User (No Characters)**:
```
+------------------------------------------+
|                                          |
|           [character-icon]               |
|                64px, Primary             |
|                                          |
|        Your adventure begins here        |
|                                          |
|   Create your first character to start   |
|   tracking your LARP and roleplay        |
|   experiences.                           |
|                                          |
|       [Create Your First Character]      |
|              Primary Button              |
|                                          |
+------------------------------------------+
```

**Returning User (Characters Archived/Deleted)**:
```
+------------------------------------------+
|                                          |
|           [folder-open-icon]             |
|                                          |
|        No active characters              |
|                                          |
|   All your characters are archived.      |
|   Create a new one or view your archive. |
|                                          |
|   [Create Character]  [View Archive]     |
|                                          |
+------------------------------------------+
```

**Search With No Results**:
```
+------------------------------------------+
|                                          |
|           [search-icon]                  |
|                                          |
|        No characters match "xyz"         |
|                                          |
|   Try a different search term or         |
|   clear the filter.                      |
|                                          |
|           [Clear Search]                 |
|                                          |
+------------------------------------------+
```

**Filter With No Results**:
```
+------------------------------------------+
|                                          |
|           [filter-icon]                  |
|                                          |
|     No characters in "Vampire LARP"      |
|                                          |
|   You don't have any characters for      |
|   this game system yet.                  |
|                                          |
|   [Create Character]  [Clear Filter]     |
|                                          |
+------------------------------------------+
```

#### 8.7.2 Character Detail Empty States

**No Attributes**:
```
+------------------------------------------+
|  Attributes                    [+ Add]   |
|------------------------------------------|
|                                          |
|         [layers-icon]                    |
|                                          |
|       No attributes yet                  |
|                                          |
|   Add stats like Strength, Health,       |
|   or any custom attributes.              |
|                                          |
|         [Add First Attribute]            |
|                                          |
+------------------------------------------+
```

**No Abilities**:
```
+------------------------------------------+
|  Abilities                     [+ Add]   |
|------------------------------------------|
|                                          |
|         [zap-icon]                       |
|                                          |
|        No abilities yet                  |
|                                          |
|   Add skills, spells, or special         |
|   abilities your character has.          |
|                                          |
|          [Add First Ability]             |
|                                          |
+------------------------------------------+
```

**No Inventory Items**:
```
+------------------------------------------+
|  Inventory                     [+ Add]   |
|------------------------------------------|
|                                          |
|         [package-icon]                   |
|                                          |
|     Your inventory is empty              |
|                                          |
|   Add items your character carries,      |
|   from weapons to personal effects.      |
|                                          |
|           [Add First Item]               |
|                                          |
+------------------------------------------+
```

**No Relationships**:
```
+------------------------------------------+
|  Relationships                 [+ Add]   |
|------------------------------------------|
|                                          |
|         [users-icon]                     |
|                                          |
|     No relationships yet                |
|                                          |
|   Link this character to allies,        |
|   rivals, mentors, and others.          |
|                                          |
|         [Add Relationship]               |
|                                          |
+------------------------------------------+
```

**No Journal Entries**:
```
+------------------------------------------+
|  Journal                       [+ Add]   |
|------------------------------------------|
|                                          |
|         [book-open-icon]                 |
|                                          |
|      No journal entries yet              |
|                                          |
|   Record your character's adventures,    |
|   notes, and memories here.              |
|                                          |
|          [Write First Entry]             |
|                                          |
+------------------------------------------+
```

#### 8.7.3 Events Empty States

**No Registered Events**:
```
+------------------------------------------+
|                                          |
|         [calendar-icon]                  |
|                                          |
|       No upcoming events                 |
|                                          |
|   You haven't registered for any         |
|   events yet. Browse public events       |
|   or wait for an organizer invite.       |
|                                          |
|          [Browse Events]                 |
|                                          |
+------------------------------------------+
```

**No Public Events Available**:
```
+------------------------------------------+
|                                          |
|         [calendar-x-icon]                |
|                                          |
|       No events found                    |
|                                          |
|   There are no public events at this     |
|   time. Check back later or ask an       |
|   organizer for a private invite.        |
|                                          |
+------------------------------------------+
```

**Event With No Registrations (Organizer View)**:
```
+------------------------------------------+
|                                          |
|         [users-icon]                     |
|                                          |
|      No registrations yet                |
|                                          |
|   Share your event link to invite        |
|   players, or create pre-generated       |
|   characters for them to claim.          |
|                                          |
|   [Copy Link]  [Create Pre-Gen]          |
|                                          |
+------------------------------------------+
```

#### 8.7.4 Organizer Empty States

**No Events Created**:
```
+------------------------------------------+
|                                          |
|         [calendar-plus-icon]             |
|                                          |
|      Ready to organize?                  |
|                                          |
|   Create your first event to start       |
|   managing characters, registrations,    |
|   and plot for your LARP or mystery.     |
|                                          |
|        [Create Your First Event]         |
|                                          |
+------------------------------------------+
```

**No Character Templates**:
```
+------------------------------------------+
|                                          |
|         [file-text-icon]                 |
|                                          |
|      No templates yet                    |
|                                          |
|   Create character templates to give     |
|   players consistent sheets with the     |
|   right attributes for your game.        |
|                                          |
|         [Create Template]                |
|                                          |
+------------------------------------------+
```

**No Plot Threads (Phase 3)**:
```
+------------------------------------------+
|                                          |
|         [git-branch-icon]                |
|                                          |
|       No plot threads yet                |
|                                          |
|   Start weaving your story by creating   |
|   plot threads, secrets, and scenes.     |
|                                          |
|        [Create Plot Thread]              |
|                                          |
+------------------------------------------+
```

### 8.8 Error States and Recovery

#### 8.8.1 Error Severity Levels

| Level | Visual Treatment | User Action Required | Examples |
|-------|------------------|---------------------|----------|
| **Critical** | Full-screen blocker | Must resolve to continue | Auth expired, account suspended |
| **Error** | Banner + affected area | Should resolve soon | Save failed, sync error |
| **Warning** | Inline message | Optional/informational | Outdated data, pending changes |
| **Info** | Toast/snackbar | None required | Action completed, tip |

#### 8.8.2 Critical Error States

**Authentication Expired**:
```
+------------------------------------------+
|                                          |
|           [lock-icon]                    |
|             64px, Red                    |
|                                          |
|        Session Expired                   |
|                                          |
|   Your session has expired. Please       |
|   sign in again to continue.             |
|                                          |
|   Any unsaved changes have been          |
|   preserved locally.                     |
|                                          |
|           [Sign In Again]                |
|                                          |
+------------------------------------------+
```

**Account Issue**:
```
+------------------------------------------+
|                                          |
|           [alert-triangle-icon]          |
|             64px, Red                    |
|                                          |
|        Account Unavailable               |
|                                          |
|   There's an issue with your account.    |
|   Please contact support for help.       |
|                                          |
|   Error code: ACC-403                    |
|                                          |
|   [Contact Support]   [Sign Out]         |
|                                          |
+------------------------------------------+
```

**App Update Required**:
```
+------------------------------------------+
|                                          |
|           [download-icon]                |
|             64px, Primary                |
|                                          |
|        Update Required                   |
|                                          |
|   This version of RoleKeeper is      |
|   no longer supported. Please update     |
|   to continue.                           |
|                                          |
|           [Update Now]                   |
|                                          |
+------------------------------------------+
```

#### 8.8.3 Error Banners

**Save Failed**:
```
+------------------------------------------+
|  [!] Changes couldn't be saved.      [×] |
|      [Retry]  [Save Offline]             |
+------------------------------------------+
```

**Sync Error**:
```
+------------------------------------------+
|  [!] Sync failed. Some changes may   [×] |
|      not be up to date.  [Retry Sync]    |
+------------------------------------------+
```

**Network Error**:
```
+------------------------------------------+
|  [!] Can't connect to server.        [×] |
|      Check your connection. [Retry]      |
+------------------------------------------+
```

**Permission Denied**:
```
+------------------------------------------+
|  [!] You don't have permission to    [×] |
|      perform this action.                |
+------------------------------------------+
```

#### 8.8.4 Inline Errors (Form Fields)

**Input Validation Error**:
```
+------------------------------------------+
|  Character Name                          |
|  +------------------------------------+  |
|  |                                    |  |
|  +------------------------------------+  |
|  ⚠ Character name is required           |
|                                          |
+------------------------------------------+
```

**Format Error**:
```
+------------------------------------------+
|  Email Address                           |
|  +------------------------------------+  |
|  | not-an-email                       |  |
|  +------------------------------------+  |
|  ⚠ Please enter a valid email address   |
|                                          |
+------------------------------------------+
```

**Length Error**:
```
+------------------------------------------+
|  Description                             |
|  +------------------------------------+  |
|  | [very long text...]                |  |
|  +------------------------------------+  |
|  ⚠ Description must be under 10,000     |
|    characters (currently 10,234)         |
|                                          |
+------------------------------------------+
```

#### 8.8.5 Error Recovery Flows

**Failed Save Recovery**:
```
User attempts save
        |
        v
   Save fails
        |
        v
+----------------+
| Error banner   |  "Changes couldn't be saved"
| [Retry] [Save  |
|  Offline]      |
+----------------+
        |
   +----+----+
   |         |
   v         v
[Retry]   [Save Offline]
   |         |
   v         v
Try again  Save locally
   |       Show "pending" indicator
   |       Queue for sync
   v
Success?
   |
+--+--+
|     |
v     v
Yes   No (after 3 attempts)
|     |
v     v
Done  Show detailed error
      [Contact Support]
```

**Sync Conflict Recovery**:
```
Sync detects conflict
        |
        v
+------------------------------------------+
|        [sync-alert-icon]                 |
|                                          |
|   Your changes conflict with updates     |
|   from another device or organizer.      |
|                                          |
|   Character: Elara Nightwhisper          |
|   Field: Health                          |
|   Your value: 5                          |
|   Server value: 7                        |
|                                          |
|   [Keep Server]  [Keep Mine]  [View All] |
|                                          |
+------------------------------------------+

[Keep Server] -> Apply server version, discard local
[Keep Mine] -> Upload local, overwrite server
[View All] -> Show diff of all conflicting fields
```

**Offline Queue Recovery**:
```
Device comes online
        |
        v
   Begin sync
        |
        v
Queue item fails
        |
        v
+------------------------------------------+
|  [!] 1 change couldn't sync          [×] |
|                                          |
|  • Character "Elara": Health update      |
|    Error: Character no longer exists     |
|                                          |
|  [Discard Change]  [View Details]        |
+------------------------------------------+

[Discard Change] -> Remove from queue, log conflict
[View Details] -> Show full error, offer support link
```

#### 8.8.6 Degraded Functionality States

When partial functionality is available:

**Slow Connection Mode**:
```
+------------------------------------------+
|  [signal-low] Slow connection detected   |
|  Images disabled. Tap to enable.         |
+------------------------------------------+

Behavior:
- Disable image loading
- Simplify UI (remove animations)
- Batch sync operations
- Show text placeholders for images
```

**Partial Sync State**:
```
+------------------------------------------+
|  [!] Some data may be outdated       [×] |
|      Last full sync: 2 hours ago         |
|      [Sync Now]                          |
+------------------------------------------+

Behavior:
- Show "last synced" timestamp on each character
- Indicate which characters are outdated
- Allow viewing but warn before editing
```

**Limited Offline Mode**:
```
+------------------------------------------+
|  Character: Sir Edmund                   |
|  ----------------------------------------|
|                                          |
|  [!] Limited offline data                |
|                                          |
|  Only basic info is available offline.   |
|  Full details require connection.        |
|                                          |
|  Available: Name, Description            |
|  Unavailable: Abilities, Inventory       |
|                                          |
+------------------------------------------+

Behavior:
- Show available data normally
- Gray out unavailable sections
- Explain what's missing and why
```

#### 8.8.7 Error Message Guidelines

**Do:**
- Be specific about what went wrong
- Explain what the user can do
- Provide an error code for support
- Offer alternative actions when possible
- Use plain language, not technical jargon

**Don't:**
- Blame the user ("You entered invalid data")
- Use vague messages ("Something went wrong")
- Show raw error messages or stack traces
- Leave the user without options
- Use alarming language unnecessarily

**Error Message Template**:
```
[What happened]
[Why it might have happened - optional]
[What the user can do]
[Error code for support - if applicable]
```

**Examples**:

Bad: "Error 500: Internal Server Error"
Good: "We couldn't save your changes. Our servers are having issues. Try again in a few minutes. (Error: SRV-500)"

Bad: "Invalid input"
Good: "Character name can only contain letters, numbers, and spaces."

Bad: "Network error"
Good: "Can't connect to the server. Check your internet connection and try again."

#### 8.8.8 Error Logging for Support

All errors should log:
- Error code (e.g., SYNC-001, AUTH-403)
- Timestamp
- User action that triggered error
- Device/app version
- Network state at time of error

**Support Flow**:
```
Error occurs
     |
     v
Log error locally
     |
     v
Show error with code
     |
     v
User taps "Contact Support"
     |
     v
+------------------------------------------+
|  Report an Issue                         |
|                                          |
|  We've collected some diagnostic info    |
|  to help resolve your issue.             |
|                                          |
|  Describe what happened:                 |
|  +------------------------------------+  |
|  |                                    |  |
|  +------------------------------------+  |
|                                          |
|  [  ] Include diagnostic data            |
|  [  ] Include screenshot                 |
|                                          |
|  [Send Report]                           |
|                                          |
+------------------------------------------+
```

---

## 9. Motion and Animation

### 9.1 Animation Principles

1. **Purposeful**: Animations communicate relationships and state
2. **Quick**: Never delay the user (max 300ms for transitions)
3. **Smooth**: 60fps target, use native drivers
4. **Interruptible**: Long animations can be interrupted
5. **Accessible**: Respect reduced motion preferences

### 9.2 Timing and Easing

```
Duration Scale:
- Instant:    0ms     (micro-interactions, toggles)
- Fast:       100ms   (hover effects, small elements)
- Normal:     200ms   (most transitions)
- Slow:       300ms   (page transitions, modals)
- Emphasis:   400ms   (attention-grabbing animations)

Easing Curves:
- Standard:   cubic-bezier(0.4, 0.0, 0.2, 1)  // Most animations
- Decelerate: cubic-bezier(0.0, 0.0, 0.2, 1)  // Entering
- Accelerate: cubic-bezier(0.4, 0.0, 1, 1)    // Exiting
- Sharp:      cubic-bezier(0.4, 0.0, 0.6, 1)  // Quick, snappy
```

### 9.3 Common Animations

#### Page Transitions

**Mobile**:
- Push: Slide from right (200ms, Standard)
- Pop: Slide to right (200ms, Standard)
- Modal: Slide up from bottom (300ms, Decelerate)

**Tablet/Desktop**:
- Fade + Scale: Fade in from 0.95 scale (200ms)
- Sidebar navigation: Cross-fade (150ms)

#### Component Animations

**Button Press**:
```
- Scale: 1.0 -> 0.98 -> 1.0
- Duration: 100ms
- Easing: Sharp
```

**Card Selection**:
```
- Scale: 1.0 -> 1.02
- Shadow: Elevation 1 -> Elevation 2
- Duration: 150ms
```

**FAB**:
```
- Appear: Scale from 0 + fade (200ms, Decelerate)
- Press: Scale 0.95 (100ms)
```

**Tab Change**:
```
- Content: Cross-fade (150ms)
- Indicator: Slide (200ms, Standard)
- Swipe: Follow finger, snap to tab
```

**Sync Indicator**:
```
- Spinning: 360deg rotation, 1000ms, linear
- Success: Scale pop + check mark (200ms)
- Error: Shake (200ms, 3 oscillations)
```

#### Micro-interactions

**Toggle/Switch**:
```
- Thumb: Slide (150ms, Standard)
- Track: Color fade (150ms)
```

**Checkbox**:
```
- Check mark: Draw in (150ms)
- Background: Fade (100ms)
```

**Expand/Collapse**:
```
- Height: Animate (200ms, Standard)
- Content: Fade in after expand (100ms)
```

### 9.4 Loading States

#### Skeleton Loaders

```
- Color: Surface with shimmer
- Shimmer: Left to right gradient animation (1500ms, infinite)
- Shape: Match content shape (rounded rectangles)
```

#### Spinners

```
Usage: Button loading, data fetching
Style: Circular, 2px stroke, Primary color
Size:
- Small: 16px (in buttons)
- Medium: 24px (inline loading)
- Large: 40px (full page)
```

#### Progress Indicators

```
Usage: Long operations, uploads
Style: Linear bar, Primary color
Animation: Indeterminate or determinate
```

### 9.5 Reduced Motion

When reduced motion is enabled:
- Page transitions: Instant cross-fade
- Skeleton loaders: Static (no shimmer)
- Spinners: Simplified (fewer rotations)
- Expand/collapse: Instant
- All decorative animations: Disabled

---

## 10. Implementation Notes

### 10.1 Flutter Implementation

#### Theme Configuration

The app supports:
- **Default theme**: Light, dark, system (from user settings)
- **Game theme override**: When viewing a character/event linked to a Game System, apply that game's `theme` if defined (primaryColor, accentColor)
- **Orientation**: All layouts must respond to portrait and landscape; use `OrientationBuilder` or `MediaQuery.of(context).orientation`

```dart
// core/theme/app_theme.dart

final lightTheme = ThemeData(
  useMaterial3: true,
  colorScheme: ColorScheme.fromSeed(
    seedColor: const Color(0xFF6366F1),
    brightness: Brightness.light,
  ),
  textTheme: const TextTheme(
    displayLarge: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
    headlineLarge: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
    headlineMedium: TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
    headlineSmall: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
    titleLarge: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
    bodyLarge: TextStyle(fontSize: 16),
    bodyMedium: TextStyle(fontSize: 14),
    bodySmall: TextStyle(fontSize: 12),
    labelSmall: TextStyle(fontSize: 10, fontWeight: FontWeight.w600),
  ),
  // ... additional theme configuration
);
```

#### Component Implementation Pattern

```dart
// widgets/common/character_card.dart

class CharacterCard extends StatelessWidget {
  final Character character;
  final VoidCallback onTap;
  final SyncStatus syncStatus;

  const CharacterCard({
    required this.character,
    required this.onTap,
    required this.syncStatus,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'View ${character.name}, ${character.gameSystem ?? "no game system"}',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Card(
          // ... card implementation
        ),
      ),
    );
  }
}
```

### 10.2 Offline Implementation

#### Connectivity Provider

```dart
// providers/connectivity_provider.dart

final connectivityProvider = StateNotifierProvider<ConnectivityNotifier, ConnectivityState>((ref) {
  return ConnectivityNotifier();
});

class ConnectivityNotifier extends StateNotifier<ConnectivityState> {
  ConnectivityNotifier() : super(ConnectivityState.checking) {
    _init();
  }

  void _init() {
    Connectivity().onConnectivityChanged.listen((result) {
      state = result == ConnectivityResult.none
          ? ConnectivityState.offline
          : ConnectivityState.online;
    });
  }
}
```

#### Offline-Aware Widget

```dart
// widgets/common/offline_aware_widget.dart

class OfflineAwareWidget extends ConsumerWidget {
  final Widget Function(BuildContext, bool isOnline) builder;
  final Widget? offlineOverlay;

  const OfflineAwareWidget({
    required this.builder,
    this.offlineOverlay,
    super.key,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connectivity = ref.watch(connectivityProvider);
    final isOnline = connectivity == ConnectivityState.online;

    return Stack(
      children: [
        builder(context, isOnline),
        if (!isOnline && offlineOverlay != null)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: offlineOverlay!,
          ),
      ],
    );
  }
}
```

### 10.3 Testing Requirements

#### Accessibility Testing
- Automated: flutter_test with Accessibility checks
- Manual: VoiceOver (iOS), TalkBack (Android)
- Tools: Accessibility Insights, axe DevTools (web)

#### Offline Testing
- Airplane mode testing on real devices
- Network Link Conditioner (iOS) for degraded conditions
- Firebase emulator for local development

#### Performance Testing
- 60fps target for animations
- <500ms character load (cached)
- <2s app launch to portfolio
- Memory profiling for large portfolios

### 10.4 Design-Development Handoff

#### Asset Delivery
- Icons: SVG format, 24px base size
- Images: 1x, 2x, 3x for raster assets
- Colors: Hex values in design tokens
- Typography: Font files + scale specification

#### Component Documentation
- Each component documented with props/parameters
- States visually documented (Figma or similar)
- Interaction specifications written
- Accessibility requirements noted

#### Design Tokens Export

```json
{
  "color": {
    "primary": "#6366F1",
    "primaryDark": "#4F46E5",
    "success": "#10B981",
    "warning": "#F59E0B",
    "error": "#EF4444"
  },
  "spacing": {
    "xs": 4,
    "sm": 8,
    "md": 12,
    "lg": 16,
    "xl": 20,
    "2xl": 24
  },
  "borderRadius": {
    "sm": 4,
    "md": 8,
    "lg": 12,
    "xl": 16,
    "full": 9999
  }
}
```

---

## Appendix A: Screen Inventory

| Screen | Phase | Platform | Priority |
|--------|-------|----------|----------|
| Welcome / Landing | 1 | Mobile | P0 |
| Sign Up (Email) | 1 | Mobile | P0 |
| Sign Up (Social) | 1 | Mobile | P0 |
| Sign In | 1 | Mobile | P0 |
| Forgot Password | 1 | Mobile | P0 |
| Portfolio (Character List) | 1 | Mobile | P0 |
| Character Detail | 1 | Mobile | P0 |
| Character Quick View | 1 | Mobile | P1 |
| Character Create | 1 | Mobile | P0 |
| Character Edit | 1 | Mobile | P0 |
| Add Attribute Modal | 1 | Mobile | P0 |
| Add Ability Modal | 1 | Mobile | P0 |
| Add Relationship Modal | 1 | Mobile | P1 |
| Add Item Modal | 1 | Mobile | P0 |
| Add Journal Entry Modal | 1 | Mobile | P1 |
| Profile | 1 | Mobile | P0 |
| Settings | 1 | Mobile | P0 |
| Events List | 2 | Mobile | P0 |
| Event Detail | 2 | Mobile | P0 |
| Event Registration | 2 | Mobile | P0 |
| Organizer Dashboard | 2 | Desktop | P0 |
| Event Management | 2 | Desktop | P0 |
| Player Management | 2 | Desktop | P1 |
| Item Distribution | 2 | Desktop | P1 |
| Character Template Editor | 2 | Desktop | P1 |
| Plot Thread Management | 3 | Desktop | P1 |
| Scene Planning | 3 | Desktop | P2 |
| Staff Management | 3 | Desktop | P2 |

---

## Appendix B: Glossary

| Term | Definition |
|------|------------|
| Quick View | Simplified, high-contrast character view optimized for field use |
| Portfolio | Collection of all user's characters across games |
| Field Use | Using the app during active gameplay, often outdoors |
| Desk Use | Using the app at home or office for planning/management |
| Sync Status | Indicator of data synchronization state with server |
| Pre-gen | Pre-generated character created by organizer for players to claim |
| Quick Stats | Subset of attributes marked for quick reference display |
| Key Abilities | Abilities marked as most important for quick reference |

---

## Appendix C: Document History

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0 | 2025-12-09 | UX/UI Agent | Initial specification |

---

*Document prepared by UX/UI Designer Agent*
*Ready for review by Development Team*