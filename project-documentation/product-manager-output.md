# RoleKeeper - Product Requirements Document

**Version**: 1.0
**Date**: December 8, 2025
**Status**: Initial Draft

---

## Executive Summary

### Elevator Pitch

A rule-agnostic character and event management tool for LARP and murder mystery games that players can use independently, and organizers can adopt to unlock powerful logistics features.

### Problem Statement

LARP and murder mystery organizers currently rely on spreadsheets, documents, and custom-built tools that are either:
1. **Tightly coupled to specific game rules** - requiring rebuilding for each new game system
2. **Organizer-only tools** - providing no value to players unless the organizer actively uses them
3. **Fragmented across multiple applications** - character sheets in one place, inventory in another, plot notes in a third

Players, meanwhile, lack a unified way to track their characters across different games and systems. They resort to paper sheets, photos of paper sheets, or scattered notes that are easily lost and impossible to reference quickly during play.

**The core insight**: Players should get immediate value from a personal character management tool, even if no organizer ever adopts it. When organizers do adopt it, the same player experience seamlessly upgrades with richer features (live inventory updates, event schedules, plot hooks).

### Target Audience / Personas

See Section 2 for detailed personas. Primary user segments:

1. **Event Organizers** - People who plan, produce, and run live events
2. **Active Players** - Engaged players who attend multiple events and invest in their characters
3. **Casual Players** - Occasional participants who want a simple, low-friction experience
4. **Plot Writers / Game Masters** - Content creators who design stories, characters, and encounters

### Unique Value Proposition

**"Your characters, everywhere. Your events, organized."**

Unlike existing LARP tools that require organizer buy-in to provide any value, RoleKeeper delivers immediate utility to individual players:

- **Player-first, organizer-enhanced**: Players get a powerful personal character vault that works standalone. Organizers get logistics tools that integrate with players' existing data.
- **Rule-agnostic by design**: Generic data structures that can represent any game system's characters, items, and abilities without hardcoding rules.
- **Offline-ready for the field**: Character display works without internet because that is when players need it most - in the middle of a forest, convention center, or venue with poor connectivity.
- **Scales from parlor games to festivals**: The same tool works for a 6-person murder mystery dinner and a 300-person weekend LARP.

### Success Metrics

| Metric | Target (Year 1) | Rationale |
|--------|-----------------|-----------|
| Monthly Active Players (standalone) | 5,000 | Validates player-first value proposition |
| Player-to-Organizer Conversion | 10% | Players who become organizers using the platform |
| Organizer-Linked Events | 500 | Events created by organizers with player integration |
| Character Sheets Created | 25,000 | Core engagement metric |
| Offline Usage Rate | 30%+ of character views | Validates offline-first investment |
| Player Retention (3-month) | 40% | Players who return after 90 days |
| Net Promoter Score | 40+ | Community advocacy in niche market |

### Project-Level Technical Constraints

Based on discovery:

- **Frontend**: Flutter (mobile + web) - enables cross-platform with shared codebase
- **Backend**: Firebase (Auth, Firestore, Cloud Functions, Storage)
- **Mobile-first for player features** with offline capability
- **Desktop/web-first for organizer features** (plot management, analytics)
- **Rule-agnostic data model** - must not embed any specific LARP system's rules

---

## Section 1: Key Insights and Product Direction

### Discovery Synthesis

From the discovery conversation, several critical insights emerged:

#### Insight 1: The Dual-Adoption Problem

Most LARP tools fail because they require organizer adoption before players see any benefit. This creates a chicken-and-egg problem: organizers will not adopt tools players do not use, and players cannot use tools organizers have not set up.

**Our approach**: Build player value first. A player downloads the app, creates characters, and gets immediate utility (offline character sheets, cross-game character vault). When they attend an organized event, their existing data optionally connects to gain additional features.

#### Insight 2: Rule-Agnostic is Non-Negotiable

The requester built a previous system that worked well but was locked to one LARP's rules. Every new game required rebuilding. The market is fragmented across hundreds of game systems with no dominant standard.

**Our approach**: Generic, flexible data structures. Characters have "attributes," "abilities," "items," and "notes" without defining what those mean. Each game/organizer can define templates, but the underlying model is universal.

#### Insight 3: Context Determines Connectivity Requirements

Different features have different network needs:
- **Character display** (reading your sheet mid-game): Must work offline
- **Character advancement** (adding XP, new abilities): Can require online (changes need to sync)
- **Plot management** (organizer tools): Online-only is acceptable (desk work)

**Our approach**: Clear separation of read-heavy (offline-capable) and write-heavy (online-required) features.

#### Insight 4: Scale Variance is Extreme

The tool must work for:
- A 6-person murder mystery dinner party (minimal logistics, high character focus)
- A 50-person weekend LARP (moderate logistics, character + plot coordination)
- A 300-person festival (complex logistics, staff coordination, real-time updates)

**Our approach**: Progressive complexity. Core features work at any scale. Advanced logistics features (staff coordination, real-time updates, multiple concurrent scenes) unlock as event size warrants.

### Product Direction

**Phase 1 (MVP)**: Player-centric character management
- Standalone value for individual players
- Basic character creation and display
- Offline character viewing
- Simple inventory tracking

**Phase 2**: Organizer tools and player-organizer connection
- Event creation and management
- Character templates per event/game system
- Linking player characters to events
- Organizer-pushed updates (items, advancement)

**Phase 3**: Advanced logistics
- Plot thread management
- Staff coordination tools
- Scheduling and scene management
- Analytics and reporting

### Core Design Principles

#### Principle 1: Game Systems as Configuration

Every game system should be expressible as a single configuration record. **Rules are a default part of all games**—templates, field definitions, and creation constraints constitute the rules. This means:

- **No hardcoded game logic**: The app has no concept of "hit points" or "mana" - only generic fields that organizers label and configure
- **Terminology mapping**: The same underlying concept (a numeric resource) can be called "Hit Points," "Essence," "Wounds," or "Vitality" depending on the game config
- **Structure definition**: Organizers define what fields exist (attributes, abilities, items), their types (number, text, rating), and how they're displayed (categories, order, quick stats)
- **Portable definitions**: A game system config could theoretically be exported/imported as JSON, enabling sharing between organizers

**What this enables**:
- An organizer running "Vampire: The Masquerade" creates a config with Blood Pool, Disciplines, Clan, etc.
- Another organizer running "D&D-style Fantasy" creates a config with HP, Spells, Class, Level, etc.
- A third organizer running a custom Nordic LARP has entirely different fields
- All three use the same app, same data structures, same sync - just different labels and field definitions

**What this does NOT include** (intentionally):
- Computed/derived fields (e.g., "Max HP = Constitution × 2")
- Dice rolling or mechanical resolution
- Validation rules beyond basic type checking
- Game-specific business logic

This keeps the system flexible and prevents feature creep toward becoming a rules engine.

#### Principle 2: Game-Centric Onboarding

New players discover RoleKeeper through games, not the app store:

- **QR code entry**: Primary onboarding is scanning a QR code at an event or from organizer materials
- **Game browsing**: Players can also browse public games to find communities to join
- **Character creation happens in context**: Instead of creating a generic character first, players join a game and create a character using that game's configured template
- **Standalone mode available**: Advanced users can create freeform characters without a game, but this is not the default flow

This inverts the typical "download app → create account → figure out what to do" pattern into "hear about game → scan code → you're in."

---

## Section 2: User Personas

### Persona 1: The Event Organizer ("Morgan")

**Demographics**
- Age: 28-45
- Organizes 2-6 events per year
- Has organized for 3+ years
- May run events for one game system or multiple

**Context**
- Primary Platform: Desktop/web (planning), Mobile (during events)
- Environment: Desk (planning), Field (during events)
- Connectivity: Online for planning; mixed during events
- Technical Comfort: Moderate to high

**Goals**
- Reduce administrative overhead before, during, and after events
- Provide players with accurate, up-to-date character information
- Track plot threads without losing details in email chains and documents
- Minimize day-of chaos with clear schedules and assignments

**Frustrations**
- Spreadsheet hell: multiple sheets for characters, items, NPCs, plot, schedules
- Players asking "what items do I have?" because paper sheets are outdated
- Losing track of which players know which secrets
- Post-event reconciliation of what actually happened vs. what was planned

**Behaviors**
- Plans events months in advance
- Delegates to co-organizers and staff
- Wants to see the "big picture" and drill into details
- Values reliability over flashy features

**Quote**
"I spend more time managing spreadsheets than writing plot. I need a system that handles the bookkeeping so I can focus on creating experiences."

---

### Persona 2: The Active Player ("Jordan")

**Demographics**
- Age: 22-40
- Attends 4-12 events per year
- Plays multiple game systems
- May have 3-10 active characters across different games

**Context**
- Primary Platform: Mobile (during events), occasionally desktop (between events)
- Environment: Field (during events), Desk (character planning)
- Connectivity: Often poor during events (rural sites, convention centers)
- Technical Comfort: Moderate to high

**Goals**
- Quick access to character information during play
- Track character progression across multiple games
- Never lose character history when paper sheets get damaged or lost
- Reduce "what abilities do I have again?" moments

**Frustrations**
- Paper character sheets that get wet, torn, or forgotten
- Different games using different formats and tracking methods
- No single place to see all their characters
- Having to re-enter character data for every new event

**Behaviors**
- Checks character sheet multiple times per event
- Updates character between events (new abilities, backstory)
- Takes notes during events to remember what happened
- Shares character information with other players for roleplay

**Quote**
"I have characters in three different LARPs and a monthly murder mystery group. I need one app that handles all of them, not a different system for each game."

---

### Persona 3: The Casual Player ("Alex")

**Demographics**
- Age: 25-50
- Attends 1-4 events per year
- Often introduced by friends
- May only play one game system

**Context**
- Primary Platform: Mobile only
- Environment: Field (during events only)
- Connectivity: Unreliable during events
- Technical Comfort: Low to moderate

**Goals**
- Understand their character without reading rulebooks
- Not feel lost or confused during play
- Have fun without heavy prep work
- Quick reference for "what can I do?"

**Frustrations**
- Complex character sheets with rules jargon
- Forgetting abilities and items mid-game
- Feeling like they need to study to participate
- Technology that adds friction instead of reducing it

**Behaviors**
- Minimal engagement between events
- Relies on organizers and experienced players for guidance
- Wants "just enough" information, not comprehensive data
- Values simplicity over features

**Quote**
"My friend invited me to this LARP thing. I just want to know who my character is and what I can do without reading a 50-page rulebook."

---

### Persona 4: The Plot Writer / Game Master ("Sam")

**Demographics**
- Age: 25-45
- Creates content for 1-3 game systems
- May or may not also be an organizer
- Often part of a writing team

**Context**
- Primary Platform: Desktop/web exclusively
- Environment: Desk (creative work)
- Connectivity: Online required
- Technical Comfort: Moderate to high

**Goals**
- Organize plot threads, secrets, and reveals
- Track which characters know what information
- Plan scenes and encounters with clear prerequisites
- Collaborate with other writers without version conflicts

**Frustrations**
- Plot details scattered across documents, emails, and chat logs
- Losing track of what secrets have been revealed
- Difficulty planning scenes that depend on prior player actions
- No visibility into how plot connects to specific characters

**Behaviors**
- Works in concentrated creative sessions
- Needs to reference past plot when writing new content
- Collaborates asynchronously with other writers
- Wants to see connections and dependencies visually

**Quote**
"I have a plot thread that has been running for two years across twelve events. I need to see the whole picture and know exactly what each player character has discovered."

---

## Section 3: User Stories by Feature Area

### 3.1 Character Management (Core)

#### Player-Side Stories

**CH-001: Create a Character (Standalone)**
- As an **Active Player**, I want to create a character with custom attributes and abilities, so that I can track my character without needing an organizer to set anything up.
- **Acceptance Criteria**:
  - Given I am logged in, when I tap "Create Character," then I can enter a name, description, and add custom fields
  - Given I am creating a character, when I add an attribute (e.g., "Strength: 3"), then it appears on my character sheet
  - Given I am creating a character, when I add an ability or skill, then I can include a name and description
  - Given I have created a character, when I view it offline, then all data is available

**CH-002: View Character Sheet Offline**
- As a **Casual Player**, I want to view my character sheet without internet, so that I can reference it during events in areas with poor connectivity.
- **Acceptance Criteria**:
  - Given I have previously viewed my character while online, when I lose connectivity, then I can still view all character data
  - Given I am offline, when I view my character, then a visual indicator shows I am in offline mode
  - Given I am offline, when I attempt to edit my character, then I see a message explaining edits require connectivity

**CH-003: Quick Reference View**
- As a **Casual Player**, I want a simplified view of my character showing only key abilities and items, so that I can quickly answer "what can I do?" without scrolling through details.
- **Acceptance Criteria**:
  - Given I am viewing my character, when I select "Quick View," then I see only: name, key abilities (marked as such), and carried items
  - Given I am in Quick View, when I tap an ability, then I see its full description
  - Given I am in Quick View, when I want more detail, then I can easily switch to full character sheet

**CH-004: Character Portfolio**
- As an **Active Player**, I want to see all my characters across all games in one place, so that I can manage my LARP life without switching apps.
- **Acceptance Criteria**:
  - Given I have characters in multiple games, when I open the app, then I see a list of all my characters
  - Given I am viewing my portfolio, when I filter by game/event, then only relevant characters appear
  - Given I am viewing my portfolio, when I tap a character, then I see their full sheet

**CH-005: Character History/Journal**
- As an **Active Player**, I want to record notes and events for my character, so that I can remember what happened across multiple events.
- **Acceptance Criteria**:
  - Given I am viewing my character, when I add a journal entry, then it is timestamped and saved
  - Given I have journal entries, when I view the history, then entries appear in chronological order
  - Given I am offline, when I add a journal entry, then it syncs when I regain connectivity

#### Organizer-Side Stories

**CH-006: Create Character Template**
- As an **Event Organizer**, I want to create character templates for my game system, so that players have consistent character sheets with the right fields.
- **Acceptance Criteria**:
  - Given I am an organizer, when I create a template, then I can define required and optional fields
  - Given I have created a template, when a player creates a character for my event, then they see my template
  - Given I have a template, when I update it, then existing characters are not affected (only new characters)

**CH-007: Pre-Generate Characters**
- As an **Event Organizer**, I want to create pre-made characters for players to claim, so that I can run events where I control the character roster (murder mysteries, one-shots).
- **Acceptance Criteria**:
  - Given I am an organizer, when I create a character marked "pre-generated," then it appears in my event's character pool
  - Given a pre-gen character exists, when a player claims it, then it appears in their portfolio linked to my event
  - Given a pre-gen has been claimed, when another player tries to claim it, then they see it is unavailable

**CH-008: Push Character Updates**
- As an **Event Organizer**, I want to update a player's character (items, abilities, XP), so that players have accurate information without manual re-entry.
- **Acceptance Criteria**:
  - Given I am an organizer, when I add an item to a player's character, then it appears on their character sheet
  - Given I push an update, when the player is offline, then the update syncs when they reconnect
  - Given I push an update, when the player views their character, then they see a notification of changes

#### Character Creation Module Architecture

All games have character creation; the **Character Creation Module** defines **who creates characters** and **how** when the game designer creates them.

**Who creates characters**:

| Creator | Use Case |
|---------|----------|
| **Game designer** | Murder mysteries, one-shots, curated rosters—designer creates all characters (pre-generated) |
| **Player** | Open LARPs, campaigns—players create their own characters |
| **Both** | Mixed events—some pre-gen characters, some player-created |

**When the game designer creates characters**:

| Designer creation mode | Purpose |
|-----------------------|---------|
| **Freeform** | Designer can do whatever without limitations; no validation against templates or rules. Useful when designer needs full creative control (e.g., custom murder mystery cast). |
| **Rules-based** | Designer follows the same character creation rules as players—templates, point limits, validation. Ensures pre-gen characters are consistent with the system and valid for play. |

- **Freeform**: No constraints; designer can add any attributes, abilities, items regardless of template.
- **Rules-based**: Designer uses the same templates and validation as players; pre-gen characters conform to the game system's creation rules.

#### Rule Changes and Affected Characters

Rules change over time. When a game designer updates rules that affect character creation (templates, build costs, validation), **existing characters** may be impacted. The game designer must define a **rule change policy** for how to handle them.

**Scenarios**:

| Scenario | Question | Policy Options |
|----------|----------|----------------|
| **Nerf** (rules weakened something) | Do affected characters get compensated? | Compensation (organizer awards build points, etc.), or Rebuild (player can change character) |
| **Build cost increase** | Ability/item cost went up—character already has it | **Free upgrade** (they keep it; no additional spend) or **Pay difference** (must spend the new cost) |
| **Structural change** | Template/field definitions changed | **Grandfather** (keep as-is), **Rebuild** (player can update to new rules), or **Compensation** |

**Policy options** (game designer configures per Game System):

- **Grandfather**: Existing characters keep their current state; no changes required. New rules apply only to new characters.
- **Compensation**: Affected characters receive compensation (e.g., build points). Organizer applies manually; system tracks that rules changed.
- **Rebuild allowed**: Players can change their character to conform to new rules within a window.
- **Free upgrade**: When build cost increases, characters who already have the thing keep it at no additional cost.
- **Pay difference**: When build cost increases, characters must spend the additional build to keep it.
- **Organizer override**: Game runners can always make exceptions (e.g., grandfather one character, compensate another). This is always available.

The system stores **rules version** on characters (when they were created) and on the Game System (current version). When rules change, characters with an older version can be flagged. The app does not execute the policy—it displays it; the organizer and players apply it.

---

### 3.2 Inventory and Item Management

#### Inventory Module Architecture

Inventory is a **modular system** with a minimal core and optional submodules. This keeps the base flexible for any game type while allowing game-specific mechanics to extend it.

**Core Module (always present)**:
- Every inventory item has two required attributes: **Name** and **Description**
- The core module supports basic item tracking without game-specific logic

**Game System Master Catalog**:
- Each Game System maintains a **master database of all inventory item definitions** and their attributes
- Character sheet inventory entries **link to** item definitions in the Game System catalog (by reference)
- Organizers/game writers define items in the Game System; characters hold instances that reference those definitions

**Submodules (optional, enabled per Game System)**:

| Submodule | Purpose | Example Use Case |
|-----------|---------|------------------|
| **Equipable** | Items that can be equipped to body slots; when equipped, they modify character attributes (e.g., DR, stats) | Boffer LARPs (Crucible, etc.): Armor equipped on torso grants +DR; slot limits (e.g., 1 armor per torso) |
| **Consumables** | Items that are used up when consumed; quantity decreases on use | Healing potions, spell components, single-use items |
| *(Future)* | Additional submodules as needed | Stackable, durability, etc. |

**Equipable Submodule (detailed)**:
- Game writer declares which **body parts** can be equipped (e.g., torso, head, hands, feet)
- Game writer sets **slot limits** per body part (e.g., only 1 armor on torso)
- Item definitions can be tagged as **equipable** and assigned to a body part
- When equipped, the item applies **modifiers** to the character (e.g., +2 DR)
- Modifier types (DR, Armor, etc.) are defined in a **separate module**—Inventory references them but does not define the rules

**INV-001: Personal Inventory**
- As an **Active Player**, I want to track items my character possesses, so that I know what resources I have available during play.
- **Acceptance Criteria**:
  - Given I am viewing my character, when I add an item, then it appears in my inventory
  - Given I have items, when I view inventory, then I see item names, quantities, and descriptions
  - Given I am offline, when I view inventory, then all items are visible

**INV-002: Item Transfer Between Players**
- As an **Active Player**, I want to transfer items to another player's character, so that in-game trades and gifts are reflected digitally.
- **Acceptance Criteria**:
  - Given I have an item, when I initiate a transfer to another player, then they receive a request
  - Given another player transfers an item to me, when I accept, then the item appears in my inventory
  - Given a transfer is initiated, when the recipient is offline, then the request queues until they are online

**INV-003: Organizer Item Management**
- As an **Event Organizer**, I want to create item definitions in my Game System's master catalog, so that items have consistent descriptions and players cannot create arbitrary items.
- **Acceptance Criteria**:
  - Given I am an organizer of a Game System, when I create an item definition, then it is added to the Game System's master catalog
  - Given I have defined items, when I view the catalog, then I see all items with name, description, and any submodule attributes (e.g., equipable, consumable)
  - Given a player has an item linked to a catalog definition, when I update the item definition, then their view updates

**INV-004: Treasure and Rewards Distribution**
- As an **Event Organizer**, I want to distribute items to players during or after an event, so that treasure found in-game appears on character sheets.
- **Acceptance Criteria**:
  - Given I select a player, when I award them an item, then it appears in their inventory
  - Given I am distributing loot, when I select multiple players, then I can batch-award the same item
  - Given I award an item, when the player views their character, then they see a "new item" notification

---

### 3.3 Event Management

**EV-001: Create Event**
- As an **Event Organizer**, I want to create an event with date, location, and description, so that players can discover and register for my events.
- **Acceptance Criteria**:
  - Given I am an organizer, when I create an event, then I can specify name, date(s), location, and description
  - Given I create an event, when I set it to "public," then it appears in search results
  - Given I create an event, when I set it to "private," then only invited players can see it

**EV-002: Player Registration**
- As an **Active Player**, I want to register for events and link my character, so that organizers know I am attending and which character I am playing.
- **Acceptance Criteria**:
  - Given I find an event, when I register, then I can select which character I am playing
  - Given I register, when the organizer views registrations, then they see me and my character
  - Given I have registered, when I change my character choice, then the organizer sees the update

**EV-003: Event Dashboard (Organizer)**
- As an **Event Organizer**, I want a dashboard showing registrations, character stats, and event status, so that I can prepare appropriately.
- **Acceptance Criteria**:
  - Given I have an event, when I view the dashboard, then I see registration count and player list
  - Given I view the dashboard, when I click a player, then I see their character sheet
  - Given I view the dashboard, then I see summary stats (total players, characters by type, etc.)

**EV-004: Event Schedule**
- As an **Event Organizer**, I want to create a schedule of scenes, encounters, or activities, so that staff and players know what happens when.
- **Acceptance Criteria**:
  - Given I am creating a schedule, when I add an item, then I specify time, location, description, and participants
  - Given I have a schedule, when players view the event, then they see relevant schedule items
  - Given I update the schedule, when players refresh, then they see updates

**EV-005: Player Event View**
- As a **Casual Player**, I want to see event details and schedule for events I am registered for, so that I know when and where to be.
- **Acceptance Criteria**:
  - Given I am registered for an event, when I view it, then I see date, location, and my character
  - Given the event has a schedule, when I view it, then I see times and activities
  - Given the event has started, when I view it offline, then I see cached schedule data

---

### 3.4 Death Module

Not all game systems use death as a mechanic. The **Death Module** is optional and configurable per Game System.

**When disabled**: No death tracking; characters are never marked as dead or out of play.

**When enabled**, the game writer chooses death submodules and resurrection behavior:

| Submodule | Purpose | Example Use Case |
|-----------|---------|------------------|
| **Simple Death** (default) | No stages; character is simply out of the game | Murder mysteries, parlor LARPs where death means "you're done" |
| **Stages** | Configurable stages of death with rules for exiting each stage | Boffer LARPs: "Dying" (easier to heal back) → "Dead" (harder resurrection) |
| **Resurrection** | How characters return from death; organizer override always available | Fixed count (3 free resurrections), chance (gets harder each time), or override only |

**Simple Death (default submodule)**:
- When a character dies, they are marked out of play
- No intermediate stages; no in-game recovery mechanics to track
- Organizer can mark character as back in play when rules allow (e.g., between scenes)

**Stages Submodule**:
- Game writer creates **stages** (typically 1 or 2)
- First stage: often allows a simpler way to heal/revive the character back into the game (e.g., "Dying" — heal before count expires)
- Second stage: often requires a harder way to raise the character (e.g., "Dead" — resurrection spell, healer NPC)
- The system stores stage definitions; the game writer **defines the rules** for how a character exits each stage (as text/instructions)
- Character sheet displays current death stage (if any) and the exit rules for that stage
- The app does not execute rules—it displays them; resolution happens in physical play

**Resurrection Submodule** (when death is enabled):

When a character can be brought back from death, we need to track what happens. **Organizer override is always available** when death is enabled—game runners can bring any character back regardless of rules (e.g., between scenes, rule exceptions, plot needs). This is the default baseline.

| Mechanic | Purpose | What We Track |
|----------|---------|---------------|
| **Override only** (default) | No in-game resurrection rules; organizer decides when to bring characters back | `resurrectionCount` for organizer reference (how many times brought back) |
| **Fixed count** | X free resurrections per character (e.g., 3 per event) | `resurrectionCount` vs `maxResurrections`; display to organizer/player |
| **Chance** | Resurrection gets harder each time; chance-based resolution | `resurrectionCount`; game writer defines difficulty progression in rules text; we display count |

- **Fixed count**: Game writer sets `maxResurrections`. When under limit, resurrection may follow in-game rules; when at limit, organizer override only. We track and display.
- **Chance**: Each resurrection attempt increases difficulty. Game writer defines the rules (e.g., "add +1 to difficulty roll each time"); we store `resurrectionCount` and display it; resolution happens in physical play.
- Even with no resurrection mechanic, organizer override ensures game runners can always bring a character back when needed.

---

### 3.5 Plot Management (Organizer/Writer)

**PLT-001: Plot Thread Tracking**
- As a **Plot Writer**, I want to create and track plot threads with their status and dependencies, so that I can manage complex, multi-event storylines.
- **Acceptance Criteria**:
  - Given I am a writer, when I create a plot thread, then I can specify title, description, status, and related characters
  - Given I have plot threads, when I view the list, then I see status (active, resolved, dormant)
  - Given I view a plot thread, when I check "related characters," then I see which PCs and NPCs are involved

**PLT-002: Secret and Information Management**
- As a **Plot Writer**, I want to track which characters know which secrets, so that I can plan reveals and avoid spoilers.
- **Acceptance Criteria**:
  - Given I create a secret, when I assign it to characters, then those characters are flagged as "knows"
  - Given I view a secret, when I check "who knows," then I see all characters with this information
  - Given I view a character, when I check "secrets known," then I see all secrets assigned to them

**PLT-003: Scene Planning**
- As a **Plot Writer**, I want to plan scenes with triggers, participants, and outcomes, so that I can orchestrate gameplay effectively.
- **Acceptance Criteria**:
  - Given I am planning a scene, when I create it, then I can specify trigger conditions, required characters, and possible outcomes
  - Given I have planned scenes, when I view them, then I can filter by status (planned, triggered, completed)
  - Given a scene has prerequisites, when I view it, then I see whether prerequisites are met

---

### 3.6 Staff Coordination

**STF-001: Staff Roles and Assignment**
- As an **Event Organizer**, I want to assign staff to roles (marshal, NPC, logistics), so that everyone knows their responsibilities.
- **Acceptance Criteria**:
  - Given I have an event, when I invite staff, then I can assign them a role
  - Given staff have roles, when they view the event, then they see role-specific information
  - Given I am staff, when I view my assignment, then I see my role and responsibilities

**STF-002: Staff Communication**
- As an **Event Organizer**, I want to send messages to staff during an event, so that I can coordinate in real-time.
- **Acceptance Criteria**:
  - Given I am an organizer, when I send a staff message, then all staff receive a notification
  - Given I send a message, when staff view it, then they see the message content and timestamp
  - Given I want to message specific roles, when I filter by role, then only those staff receive it

---

## Section 4: Prioritized Feature Backlog

### MVP (Phase 1) - Player-First Foundation

**Goal**: Deliver standalone value to individual players. Validate the player-first hypothesis.

| ID | Feature | Priority | Rationale |
|----|---------|----------|-----------|
| CH-001 | Create Character (Standalone) | P0 | Core value proposition |
| CH-002 | View Character Offline | P0 | Critical for field use |
| CH-004 | Character Portfolio | P0 | Multi-game value proposition |
| INV-001 | Personal Inventory | P0 | Essential character data |
| CH-003 | Quick Reference View | P1 | Casual player accessibility |
| CH-005 | Character History/Journal | P1 | Long-term character investment |

**MVP Success Criteria**:
- Player can create, edit, and view characters without any organizer involvement
- Character data available offline after initial sync
- Player can manage multiple characters across different games

---

### Phase 2 - Organizer Integration

**Goal**: Add organizer tools that enhance rather than replace player-owned data.

| ID | Feature | Priority | Rationale |
|----|---------|----------|-----------|
| EV-001 | Create Event | P0 | Foundation for organizer features |
| EV-002 | Player Registration | P0 | Links players to events |
| CH-006 | Character Templates | P0 | Consistency for organized events |
| CH-007 | Pre-Generate Characters | P1 | Murder mystery / one-shot support |
| CH-008 | Push Character Updates | P1 | Organizer-to-player data flow |
| INV-003 | Item Catalog | P1 | Controlled item ecosystem |
| INV-004 | Treasure Distribution | P1 | In-game rewards |
| EV-003 | Event Dashboard | P1 | Organizer visibility |
| EV-005 | Player Event View | P1 | Player-side event information |

**Phase 2 Success Criteria**:
- Organizers can create events and have players register
- Character templates provide consistency without limiting flexibility
- Organizer updates flow to player devices seamlessly

---

### Phase 3 - Advanced Logistics

**Goal**: Full event management suite for complex, large-scale events.

| ID | Feature | Priority | Rationale |
|----|---------|----------|-----------|
| EV-004 | Event Schedule | P1 | Time-based coordination |
| PLT-001 | Plot Thread Tracking | P1 | Multi-event storyline management |
| PLT-002 | Secret Management | P1 | Information flow control |
| PLT-003 | Scene Planning | P2 | Orchestrated gameplay |
| INV-002 | Item Transfer | P2 | Player-to-player economy |
| STF-001 | Staff Roles | P2 | Large event coordination |
| STF-002 | Staff Communication | P2 | Real-time coordination |

**Phase 3 Success Criteria**:
- Writers can manage complex, multi-event storylines
- Large events can coordinate staff effectively
- Full logistics suite competes with custom-built solutions

---

### Future Phases (Backlog)

| Feature | Description | Rationale for Deferral |
|---------|-------------|------------------------|
| Combat/Resolution Tools | Dice rollers, combat trackers | Rule-specific; conflicts with rule-agnostic philosophy |
| Financial Management | Payment tracking, budgets | Different problem domain |
| Public Event Discovery | Searchable event marketplace | Requires critical mass of organizers |
| Analytics & Reporting | Post-event reports, trend analysis | Nice-to-have after core is solid |
| API for Third Parties | External integrations | Requires stable internal APIs first |
| NPC Database | Reusable NPC library | Plot writer convenience; not MVP |
| Prop/Costume Tracking | Physical item logistics | Adjacent problem; not core |

---

## Section 5: Feature Specifications (MVP)

### Feature: CH-001 - Create Character (Standalone)

**Context Summary**
- Primary Platform: Mobile-first, web secondary
- Environment: Mixed (field for viewing, desk for editing)
- Connectivity: Online for creation/editing, offline for viewing
- Primary Role(s): Active Player, Casual Player

**User Story**
As an Active Player, I want to create a character with custom attributes and abilities, so that I can track my character without needing an organizer to set anything up.

**Problem It Solves**
Players currently have no unified way to manage characters across different game systems. They use paper (losable, damageable), photos of paper (hard to update), or game-specific tools (fragmented). This feature provides a single source of truth for all their characters.

**Acceptance Criteria**

*Happy Path*
- Given I am logged in, when I tap "Create Character," then I see a character creation form
- Given I am creating a character, when I enter a name and tap save, then the character appears in my portfolio
- Given I am creating a character, when I add an attribute (key-value pair), then it saves and displays on the sheet
- Given I am creating a character, when I add an ability with name and description, then it appears in the abilities section
- Given I am creating a character, when I add an item, then it appears in the inventory section
- Given I have saved a character, when I return later, then all data persists exactly as entered

*Edge Cases*
- Given I am creating a character, when I leave name empty and tap save, then I see a validation error requiring name
- Given I am creating a character, when I lose connectivity mid-creation, then I see a warning and can continue offline
- Given I created a character offline, when connectivity returns, then the character syncs automatically
- Given I have 50 attributes on one character, when I view the sheet, then performance remains acceptable (<500ms load)

*Error Conditions*
- Given I am creating a character, when the save fails due to server error, then I see an error message and can retry
- Given I am creating a character, when sync fails repeatedly, then data is preserved locally with a "sync pending" indicator

**Priority**: P0 - This is the core value proposition. Without it, there is no product.

**Dependencies**
- User authentication (Firebase Auth)
- Firestore data model for characters
- Offline persistence (Firebase offline)

**Technical Constraints (PM perspective)**
- Must support arbitrary key-value attributes (rule-agnostic)
- Must cache locally for offline access
- Must sync when connectivity returns

**UX Considerations**
- Creation should feel fast and lightweight, not like filling out a form
- Mobile keyboard interaction should be optimized
- First-time user should be able to create a character in under 2 minutes

---

### Feature: CH-002 - View Character Offline

**Context Summary**
- Primary Platform: Mobile-first
- Environment: Field (during events)
- Connectivity: Offline-first (must work without network)
- Primary Role(s): Active Player, Casual Player

**User Story**
As a Casual Player, I want to view my character sheet without internet, so that I can reference it during events in areas with poor connectivity.

**Problem It Solves**
LARP events frequently occur in locations with poor or no connectivity (forests, rural sites, convention centers). Players need to reference their characters precisely when internet is least available. Paper sheets are a workaround but easily lost or outdated.

**Acceptance Criteria**

*Happy Path*
- Given I have viewed my character while online, when I lose connectivity, then I can still view the character
- Given I am offline, when I open the app, then I see my character list (cached)
- Given I am offline, when I tap a character, then I see the full character sheet
- Given I am offline, when I view inventory, then all items are visible
- Given connectivity returns, when I view my character, then any organizer updates sync automatically

*Edge Cases*
- Given I have never viewed a character while online, when I go offline, then that character is not available offline
- Given I have multiple characters, when I go offline, then only previously-viewed characters are available
- Given I view a character offline, when data was updated by an organizer while offline, then I see stale data until sync

*Error Conditions*
- Given I am offline, when I tap a character never cached, then I see a clear message explaining it is not available offline
- Given I am offline, when I attempt to edit, then I see a message that edits require connectivity (or queue for sync)

*Indicators*
- Given I am offline, when I view any screen, then I see a clear "offline mode" indicator
- Given I am viewing stale data, when I return online, then I see a "syncing" indicator followed by "up to date"

**Priority**: P0 - Offline viewing is essential for the primary use case (field reference during events).

**Dependencies**
- CH-001 (characters must exist to view)
- Firebase offline persistence configuration
- Local storage management

**Technical Constraints (PM perspective)**
- All character data must be available offline after one online view
- Offline data should be reasonably fresh (sync on each app open when online)
- Storage limits must be managed (cannot cache unlimited data)

**UX Considerations**
- Offline mode should feel nearly identical to online mode for reading
- Clear visual distinction between "connected" and "offline" states
- No error messages for expected offline behavior

---

### Feature: CH-004 - Character Portfolio

**Context Summary**
- Primary Platform: Mobile-first, web secondary
- Environment: Mixed
- Connectivity: Offline-tolerant (cached list works offline)
- Primary Role(s): Active Player

**User Story**
As an Active Player, I want to see all my characters across all games in one place, so that I can manage my LARP life without switching apps.

**Problem It Solves**
Active players participate in multiple games with multiple characters. Currently, they manage each separately, often with different tools. This creates fragmentation and cognitive overhead. A unified portfolio makes the app a "home base" for all LARP activity.

**Acceptance Criteria**

*Happy Path*
- Given I have created characters, when I open the app, then I see a list of all my characters
- Given I have characters from different games, when I view the portfolio, then I see game/system labels
- Given I view the portfolio, when I tap a character, then I navigate to their full sheet
- Given I have many characters, when I search/filter, then I can find specific ones quickly
- Given I view the portfolio, then characters are sorted by last accessed (most recent first)

*Edge Cases*
- Given I have no characters, when I view the portfolio, then I see an empty state with a prompt to create one
- Given I have 100+ characters, when I view the portfolio, then performance is acceptable (loads in <1s)
- Given I am offline, when I view the portfolio, then I see cached characters with an offline indicator

*Error Conditions*
- Given the portfolio fails to load, when I retry, then it attempts to fetch again
- Given sync is delayed, when I view the portfolio, then I see locally cached data immediately

**Priority**: P0 - The portfolio is the app's main screen and entry point.

**Dependencies**
- CH-001 (characters must exist)
- Character data model with game/system metadata

**Technical Constraints (PM perspective)**
- Must handle large portfolios without performance degradation
- Filtering and search must work on cached data (offline)

**UX Considerations**
- Portfolio should load instantly with cached data, then sync in background
- Visual hierarchy should emphasize character names and key info
- Easy access to create new character from portfolio view

---

### Feature: INV-001 - Personal Inventory

**Context Summary**
- Primary Platform: Mobile-first
- Environment: Field (viewing) and Desk (editing)
- Connectivity: Offline for viewing, online for editing
- Primary Role(s): Active Player, Casual Player

**User Story**
As an Active Player, I want to track items my character possesses, so that I know what resources I have available during play.

**Problem It Solves**
Players frequently need to know "what do I have?" during gameplay. Paper inventory lists are easily outdated, especially when organizers award items during play. Digital inventory provides a single source of truth that can be updated by both player and organizer.

**Acceptance Criteria**

*Happy Path*
- Given I am viewing my character, when I tap "Inventory," then I see a list of my items
- Given I am in inventory, when I add an item, then I can enter name, quantity, and description
- Given I have items, when I view them, then I see name, quantity, and can tap for description
- Given I am offline, when I view inventory, then all items are visible from cache
- Given I have stackable items, when I add more of the same, then quantity increases

*Edge Cases*
- Given I have 100+ items, when I view inventory, then performance is acceptable with scrolling
- Given an organizer adds an item while I am offline, when I reconnect, then the item appears
- Given I delete an item, when I view inventory, then it no longer appears

*Error Conditions*
- Given I try to add an item offline, when connectivity is unavailable, then the action queues or I see a message
- Given save fails, when I retry, then it attempts again without losing entered data

**Priority**: P0 - Inventory is core character data essential for gameplay.

**Dependencies**
- CH-001 (inventory belongs to a character)
- Data model for items (flexible, not rule-specific)

**Technical Constraints (PM perspective)**
- Items must be flexible (arbitrary names/descriptions for standalone use)
- Must support organizer-defined items (Phase 2)

**UX Considerations**
- Inventory should be scannable at a glance (quick counts, key items highlighted)
- Adding items should be fast (common action during play)
- Consider grouping or categorization for large inventories

---

## Section 6: Non-Functional Requirements

### 6.1 Performance

| Scenario | Target | Rationale |
|----------|--------|-----------|
| App launch to portfolio | < 2 seconds | Users expect instant access |
| Character sheet load (cached) | < 500ms | Mid-game reference needs to be fast |
| Character sheet load (network) | < 3 seconds | Acceptable for initial load |
| Search/filter response | < 200ms | Interactive feel |
| Offline mode activation | Seamless | User should not notice transition |

### 6.2 Scalability

| Dimension | Phase 1 | Phase 2 | Phase 3 |
|-----------|---------|---------|---------|
| Users | 1,000 | 10,000 | 100,000 |
| Characters per user | 50 | 100 | 200 |
| Events (total) | N/A | 1,000 | 10,000 |
| Concurrent users per event | N/A | 100 | 500 |

### 6.3 Reliability and Offline Behavior

**Offline Requirements**:
- Character viewing must work completely offline after one online sync
- Portfolio list must be available offline
- Read operations never fail due to connectivity (use cached data)
- Write operations either queue (with indicator) or clearly explain connectivity requirement

**Data Durability**:
- User data must never be lost due to sync issues
- Conflict resolution: last-write-wins for most fields; additive for inventory
- Local data persists across app restarts

**Sync Behavior**:
- Background sync when connectivity available
- Visual indicator during active sync
- Clear feedback when sync completes or fails

### 6.4 Security and Privacy

**Data Sensitivity**:
- Character data: Low sensitivity (game fiction, not PII)
- User accounts: Standard sensitivity (email, password)
- Event data: Low-medium (organizers control visibility)

**Access Control**:
- Users can only view/edit their own characters (standalone)
- Organizers can view characters linked to their events
- Organizers can edit characters only with explicit permission

**Audit Requirements (Phase 2+)**:
- Log organizer modifications to player characters
- Players can see history of changes to their characters

### 6.5 Accessibility

**Minimum Standard**: WCAG 2.1 AA compliance for all interactive elements

**Specific Considerations**:
- High contrast mode for outdoor readability (sunlight)
- Large touch targets for field use (gloves, movement)
- Screen reader support for character content
- No reliance on color alone for information

---

## Section 7: Information Architecture

### Core Entities

```
User
  |-- owns --> Character (many)
  |-- organizes --> Event (many)
  |-- registered for --> Event (many)

Character
  |-- has --> Attribute (many, key-value)
  |-- has --> Ability (many)
  |-- has --> InventoryItem (many)  [links to --> GameSystemItemDefinition]
  |-- has --> JournalEntry (many)
  |-- linked to --> Event (optional)
  |-- based on --> CharacterTemplate (optional)

GameSystem
  |-- has --> ItemCatalog (master definitions; Inventory Module)
  |-- has --> FieldDefinitions (attributes, etc.)

Event
  |-- has --> CharacterTemplate (optional)
  |-- has --> EventItemCatalog (references GameSystem items; event-specific availability)
  |-- has --> Registration (many)
  |-- has --> ScheduleItem (many)
  |-- has --> PlotThread (many)

Registration
  |-- links --> User
  |-- links --> Character
  |-- links --> Event
```

### Navigation Structure (Mobile)

```
Bottom Navigation:
  [Portfolio] [Events] [Profile]

Portfolio (Home):
  - Character List
    - Character Detail
      - Attributes Tab
      - Abilities Tab
      - Inventory Tab
      - Journal Tab

Events (Phase 2):
  - Upcoming Events
    - Event Detail
      - My Registration
      - Schedule
      - My Character (linked)

Profile:
  - Account Settings
  - App Settings
  - Help/Support
```

### Navigation Structure (Web/Desktop - Phase 2)

```
Sidebar:
  [Dashboard]
  [My Characters]
  [My Events]
  [Organizer Tools]
    - Events
    - Templates
    - Plot (Phase 3)

Main Content:
  - Context-dependent based on sidebar selection
  - Multi-pane layouts for complex data (e.g., event + registrations)
```

---

## Section 8: Critical Questions Checklist

- [x] **Are we solving a real, validated problem?**
  Yes. The requester has built a previous solution and experienced the limitations firsthand. The problem of fragmented character management across games is universal in the LARP community.

- [x] **What is the minimum viable version (MVP)?**
  Standalone character management with offline viewing. No organizer features required for initial value.

- [x] **What are the most likely failure modes?**
  - Player adoption without organizer adoption (acceptable - still provides value)
  - Organizer adoption without player adoption (problematic - need player-first strategy)
  - Offline sync conflicts (mitigate with clear conflict resolution)
  - Feature creep toward rule-specific functionality (mitigate with strict rule-agnostic philosophy)

- [x] **Have we captured platform, environment, connectivity, and roles?**
  Yes. Each feature specifies context. Summary:
  - Players: Mobile-first, field environment, offline-first for viewing
  - Organizers: Desktop-first, desk environment, online-required

- [x] **Does this align with stated tech constraints?**
  Yes. Flutter + Firebase aligns with mobile-first, offline-capable, cross-platform requirements.

- [x] **Are success metrics clear and measurable?**
  Yes. Key metrics: MAU, retention, offline usage rate, organizer adoption, NPS.

---

## Appendix A: Glossary

| Term | Definition |
|------|------------|
| Character Creation Module | Defines who creates characters (game designer, player, or both) and, when the designer creates, whether creation is freeform or rules-based |
| Character | A fictional persona played by a participant in a LARP or murder mystery; may be player character or NPC |
| Character Sheet | The document (digital or physical) containing a character's attributes, abilities, inventory, currencies, relationships, and journal |
| Character Type | Distinguishes player characters (played by participants) from NPCs (non-player characters, often created by organizers) |
| Character Relationship | Structured link between two characters (e.g., Ally, Rival, Mentor); stored in relationships subcollection |
| Character Currency | Tracked currency amounts (Gold, Silver, XP, etc.) per character; Game Systems may define currency types |
| Ability Type | Classification of abilities: ability (standard), advantage (positive trait), disadvantage (negative trait) |
| Death Module | Optional module for game systems that use death; submodules: Simple Death, Stages, Resurrection (override_only, fixed_count, or chance) |
| Death Stages | In the Stages submodule: configurable states (e.g., Dying, Dead) with game-writer-defined rules for how a character exits each stage and returns to play |
| Organizer Override | Game runners can always make exceptions (death resurrection, rule changes, etc.) regardless of configured rules |
| Rule Change Policy | Game designer's policy for handling existing characters when rules change: grandfather, compensation, rebuild allowed, free upgrade, pay difference |
| Rules Version | Version number on Game System; incremented when rules change; characters store rulesVersionAtCreation to identify those affected by changes |
| Resurrection (submodule) | Tracks how characters return from death: override_only (organizer decides), fixed_count (N free resurrections), or chance (gets harder each time) |
| Equipable (submodule) | Optional Inventory submodule for items that can be equipped to body slots; when equipped, they modify character attributes (e.g., armor grants DR) |
| Game System | A configuration defining a type of game (e.g., Vampire: The Masquerade, Crucible); includes terminology, field definitions, master item catalog, and optional Death config |
| Inventory Module | Modular inventory system with core (name, description) and optional submodules (Equipable, Consumables); Game System holds master item definitions |
| LARP | Live Action Role-Playing; a game where participants physically act out characters |
| Murder Mystery | A social deduction game where participants solve a fictional crime |
| Organizer | A person who plans and runs LARP or murder mystery events |
| Plot Thread | A storyline that may span multiple events or involve multiple characters |
| Pre-gen / Pre-generated Character | A character created by the organizer for a player to adopt |
| Rule-Agnostic | Designed to work with any game system without embedding specific rules |
| Staff / Marshal | A person who facilitates gameplay but does not play a character |

---

## Appendix B: Open Questions for Future Resolution

1. **Monetization Model**: Freemium? Subscription? One-time purchase? Per-event fees for organizers?
2. **Data Portability**: Can users export their characters? What format?
3. **Community Features**: Should players be able to share characters publicly? Discover other players?
4. **Combat/Resolution**: Should the app ever include rule-specific features, or strictly remain rule-agnostic?
5. **Physical Item Integration**: QR codes on props that link to digital items? Out of scope for MVP but interesting for future.

---

*Document prepared by Product Manager Agent*
*Ready for review by System Architect and UX/UI Designer*