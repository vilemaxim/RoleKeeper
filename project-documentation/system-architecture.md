# RoleKeeper - System Architecture Document

**Version**: 1.0
**Date**: December 9, 2025
**Status**: Technical Blueprint
**Based On**: Product Requirements Document v1.0

---

## Executive Summary

### Project Overview

RoleKeeper is a rule-agnostic character and event management platform for LARP and murder mystery games. **Rules are a default part of all games** (templates, field definitions, creation constraints); the system stores and displays them but does not execute game logic. The architecture prioritizes:

1. **Player-first value delivery** - Standalone utility without organizer dependency
2. **Offline-first mobile experience** - Character viewing works without connectivity
3. **Rule-agnostic flexibility** - Generic data structures supporting any game system
4. **Progressive enhancement** - Features scale from 6-person dinners to 300-person festivals

### Key Architectural Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Frontend Framework | Flutter 3.x | Cross-platform (iOS, Android, Web, Desktop) with shared codebase; excellent offline support via Hive/Isar |
| Backend Platform | Firebase | Managed BaaS with native Flutter integration; real-time sync; built-in offline persistence |
| State Management | Riverpod | Type-safe, testable, supports code generation; better than Provider for complex state |
| Local Database | Isar | High-performance NoSQL for Flutter; better than Hive for complex queries; works alongside Firestore |
| Authentication | Firebase Auth | Supports email/password, Google, Apple; integrates with Firestore security rules |
| Database | Cloud Firestore | Real-time sync, offline persistence, security rules; fits document-based character data |
| Server Logic | Cloud Functions | Node.js 20+ for privileged operations, webhooks, scheduled tasks |
| File Storage | Firebase Storage | Profile images, event media, exportable files |

### Technology Stack Summary

```
+----------------------------------------------------------+
|                     CLIENT LAYER                          |
|  +----------------------------------------------------+  |
|  |              Flutter 3.x Application               |  |
|  |  +-------------+  +-------------+  +------------+  |  |
|  |  |   Mobile    |  |     Web     |  |  Desktop   |  |  |
|  |  | (iOS/Android)|  |   (PWA)    |  | (Windows/  |  |  |
|  |  |             |  |             |  |  macOS)    |  |  |
|  |  +-------------+  +-------------+  +------------+  |  |
|  +----------------------------------------------------+  |
|  |  State: Riverpod | Navigation: go_router           |  |
|  |  Local DB: Isar  | HTTP: dio + Firebase SDKs       |  |
|  +----------------------------------------------------+  |
+----------------------------------------------------------+
                            |
                            | HTTPS / WebSocket
                            v
+----------------------------------------------------------+
|                    FIREBASE BACKEND                       |
|  +----------------+  +----------------+  +-------------+  |
|  | Firebase Auth  |  |   Firestore    |  |   Storage   |  |
|  | (Identity)     |  | (Data + Sync)  |  |  (Files)    |  |
|  +----------------+  +----------------+  +-------------+  |
|  +----------------+  +----------------+  +-------------+  |
|  |Cloud Functions |  |    FCM         |  |  Hosting    |  |
|  | (Server Logic) |  | (Push Notify)  |  | (Web PWA)   |  |
|  +----------------+  +----------------+  +-------------+  |
+----------------------------------------------------------+
```

### System Component Overview

```
RoleKeeper System
|
+-- Player Domain
|   +-- Character Management (CRUD, templates, offline)
|   +-- Character Creation Module (creator: designer/player/both; designer mode: freeform/rules-based)
|   +-- Inventory Module (modular: core + Equipable, Consumables submodules)
|   +-- Death Module (optional: Simple Death or Stages submodules)
|   +-- Journal System (entries, history)
|   +-- Portfolio View (multi-character, multi-game)
|
+-- Event Domain
|   +-- Event Management (create, configure, publish)
|   +-- Registration System (player-event-character linking)
|   +-- Schedule Management (timeline, scenes)
|   +-- Item Catalog (references Game System master catalog; event-specific availability)
|
+-- Plot Domain (Phase 3)
|   +-- Plot Thread System (storylines, status)
|   +-- Secret Management (who knows what)
|   +-- Scene Planning (triggers, outcomes)
|
+-- Staff Domain (Phase 3)
|   +-- Role Management (assignments, permissions)
|   +-- Communication System (messaging, alerts)
|
+-- Core Infrastructure
    +-- Authentication & Authorization
    +-- Offline Sync Engine
    +-- Push Notification System
    +-- Analytics & Monitoring
```

### Critical Technical Constraints

1. **Offline-First for Character Viewing**: Character data must be fully accessible without network after initial sync
2. **Rule-Agnostic Data Model**: No hardcoded game rules; flexible key-value structures
3. **Real-Time Sync**: Organizer updates must propagate to connected players within seconds
4. **Scalability Range**: Support 6-person events to 300-person festivals
5. **Multi-Platform**: Single codebase for iOS, Android, Web, and Desktop

---

## Section 1: Data Architecture

### 1.1 Firestore Collection Structure

```
firestore/
|
+-- users/
|   +-- {userId}/
|       +-- profile: { displayName, email, avatarUrl, createdAt, settings }
|       +-- (subcollection) notifications/
|           +-- {notificationId}/
|
+-- characters/
|   +-- {characterId}/
|       +-- (subcollection) attributes/
|       |   +-- {attributeId}/
|       +-- (subcollection) abilities/
|       |   +-- {abilityId}/
|       +-- (subcollection) inventory/
|       |   +-- {itemId}/
|       +-- (subcollection) currencies/
|       |   +-- {currencyId}/
|       +-- (subcollection) relationships/
|       |   +-- {relationshipId}/
|       +-- (subcollection) journal/
|           +-- {entryId}/
|
+-- events/
|   +-- {eventId}/
|       +-- (subcollection) registrations/
|       |   +-- {registrationId}/
|       +-- (subcollection) schedule/
|       |   +-- {scheduleItemId}/
|       +-- (subcollection) itemCatalog/
|       |   +-- {catalogItemId}/
|       +-- (subcollection) staff/
|           +-- {staffAssignmentId}/
|
+-- gameSystems/
|   +-- {gameSystemId}/
|       +-- (subcollection) terminology/
|       |   +-- {termId}/
|       +-- (subcollection) fieldDefinitions/
|       |   +-- {fieldDefId}/
|       +-- (subcollection) itemCatalog/          # Master inventory item definitions
|       |   +-- {itemId}/
|
+-- templates/
|   +-- {templateId}/
|       +-- (subcollection) attributeDefinitions/
|       |   +-- {attrDefId}/
|       +-- (subcollection) abilityDefinitions/
|           +-- {abilityDefId}/
|
+-- plotThreads/ (Phase 3)
|   +-- {threadId}/
|       +-- (subcollection) secrets/
|       |   +-- {secretId}/
|       +-- (subcollection) scenes/
|           +-- {sceneId}/
|
+-- itemTransfers/
    +-- {transferId}/
```

### 1.2 Core Data Models

#### User Document

**Collection**: `users`
**Document ID**: Firebase Auth UID

```typescript
interface User {
  // Core identity
  uid: string;                    // Firebase Auth UID (document ID)
  email: string;                  // User's email address
  displayName: string;            // Display name (can differ from auth)
  avatarUrl: string | null;       // Profile image URL (Firebase Storage)

  // Account metadata
  createdAt: Timestamp;           // Account creation time
  updatedAt: Timestamp;           // Last profile update
  lastActiveAt: Timestamp;        // Last app activity

  // Settings
  settings: {
    theme: 'light' | 'dark' | 'system';
    notificationsEnabled: boolean;
    offlineCharacterLimit: number;  // Max characters to cache (default: 20)
    defaultCharacterView: 'full' | 'quick';
  };

  // Role flags (for global permissions)
  isOrganizer: boolean;           // Has created at least one event
  isPremium: boolean;             // Future: premium subscription

  // Denormalized counts (for quick display)
  characterCount: number;
  eventCount: number;             // Events organized
}
```

**Example Document**:
```json
{
  "uid": "user_abc123",
  "email": "jordan@example.com",
  "displayName": "Jordan the Brave",
  "avatarUrl": "gs://rolekeeper.appspot.com/avatars/user_abc123.jpg",
  "createdAt": "2025-01-15T10:30:00Z",
  "updatedAt": "2025-12-08T14:22:00Z",
  "lastActiveAt": "2025-12-09T09:15:00Z",
  "settings": {
    "theme": "dark",
    "notificationsEnabled": true,
    "offlineCharacterLimit": 20,
    "defaultCharacterView": "quick"
  },
  "isOrganizer": true,
  "isPremium": false,
  "characterCount": 7,
  "eventCount": 3
}
```

---

#### Character Document

**Collection**: `characters`
**Document ID**: Auto-generated UUID

```typescript
interface Character {
  // Identity
  id: string;                     // Document ID
  ownerId: string;                // User UID who owns this character

  // Core information
  name: string;                   // Character name (required)
  pronouns: string | null;        // Character pronouns
  description: string | null;     // Character background/description
  portraitUrl: string | null;     // Character image URL

  // Character type (player character vs NPC; used by organizers for filtering/display)
  characterType: 'player' | 'npc';  // Default: 'player' for player-created; 'npc' for organizer-created NPCs

  // Game System association (required for game-linked, null for freeform)
  gameSystemId: string | null;    // Reference to GameSystem document
  gameSystemName: string | null;  // Denormalized: "Vampire: The Masquerade 5th Edition"
  rulesVersionAtCreation: number | null;  // GameSystem.rulesVersion when character was created; used to flag characters affected by rule changes

  // Event linkage (optional - null for standalone characters)
  linkedEventId: string | null;   // Event this character is linked to
  templateId: string | null;      // Template this character is based on

  // Pre-generated character fields
  isPreGenerated: boolean;        // Created by organizer for claiming
  preGenStatus: 'available' | 'claimed' | 'locked' | null;
  claimedBy: string | null;       // User ID who claimed (if pre-gen)

  // Death Module state (when Game System has deathConfig enabled)
  deathStageId: string | null;     // When set: character is in this death stage (out of play). References config.deathConfig.stages[].id. Null = active/in play.
  resurrectionCount: number;       // Times this character has been brought back from death. Incremented when organizer clears deathStageId. Used for fixed_count, chance, and organizer reference.

  // Metadata
  createdAt: Timestamp;
  updatedAt: Timestamp;
  lastViewedAt: Timestamp;        // For offline cache prioritization

  // Sync status (client-side use)
  syncStatus: 'synced' | 'pending' | 'conflict';

  // Quick access denormalized data
  quickStats: {                   // Top 5 attributes for quick view
    [key: string]: string | number;
  };
  keyAbilities: string[];         // Names of abilities marked as "key"

  // Soft delete
  isArchived: boolean;
  archivedAt: Timestamp | null;
}
```

**Example Document**:
```json
{
  "id": "char_xyz789",
  "ownerId": "user_abc123",
  "name": "Elara Nightwhisper",
  "pronouns": "she/her",
  "description": "A cunning diplomat from the northern courts...",
  "portraitUrl": "gs://rolekeeper.appspot.com/characters/char_xyz789.jpg",
  "characterType": "player",
  "gameSystemId": "gs_cod",
  "gameSystemName": "Chronicles of Darkness",
  "rulesVersionAtCreation": 3,
  "linkedEventId": "event_def456",
  "templateId": "template_ccc111",
  "isPreGenerated": false,
  "preGenStatus": null,
  "claimedBy": null,
  "deathStageId": null,
  "resurrectionCount": 0,
  "createdAt": "2025-03-10T18:00:00Z",
  "updatedAt": "2025-12-08T20:30:00Z",
  "lastViewedAt": "2025-12-09T08:45:00Z",
  "syncStatus": "synced",
  "quickStats": {
    "Health": 7,
    "Willpower": 5,
    "Blood Potency": 3
  },
  "keyAbilities": ["Dominate", "Presence", "Auspex"],
  "isArchived": false,
  "archivedAt": null
}
```

---

#### Attribute Document (Subcollection)

**Collection**: `characters/{characterId}/attributes`
**Document ID**: Auto-generated or slug from name

```typescript
interface Attribute {
  id: string;                     // Document ID
  characterId: string;            // Parent character ID

  // Attribute data
  name: string;                   // e.g., "Strength", "Health", "Clan"
  value: string | number | boolean; // Flexible value type
  valueType: 'string' | 'number' | 'boolean' | 'rating';

  // For rating-type attributes (e.g., dots)
  maxValue: number | null;        // e.g., 5 for a 5-dot rating

  // Display
  category: string | null;        // Grouping: "Physical", "Mental", "Social"
  displayOrder: number;           // Sort order within category
  isQuickStat: boolean;           // Show in quick view

  // Template linkage
  templateAttributeId: string | null; // If from template
  isCustom: boolean;              // Player-added (not from template)

  // Metadata
  createdAt: Timestamp;
  updatedAt: Timestamp;
  updatedBy: string;              // User ID who last updated
}
```

**Example Document**:
```json
{
  "id": "attr_str001",
  "characterId": "char_xyz789",
  "name": "Strength",
  "value": 3,
  "valueType": "rating",
  "maxValue": 5,
  "category": "Physical",
  "displayOrder": 1,
  "isQuickStat": true,
  "templateAttributeId": "tattr_phys_str",
  "isCustom": false,
  "createdAt": "2025-03-10T18:00:00Z",
  "updatedAt": "2025-06-15T10:00:00Z",
  "updatedBy": "user_abc123"
}
```

---

#### Ability Document (Subcollection)

**Collection**: `characters/{characterId}/abilities`
**Document ID**: Auto-generated

```typescript
interface Ability {
  id: string;
  characterId: string;

  // Ability data
  name: string;                   // e.g., "Fireball", "Diplomacy", "Cloak of Shadows"
  description: string;            // What the ability does

  // Classification
  abilityType: 'ability' | 'advantage' | 'disadvantage';  // Default: 'ability' when absent (backward compat); advantages/disadvantages are distinct mechanics in many systems
  category: string | null;        // "Combat", "Social", "Magic", etc.
  tier: string | null;            // "Basic", "Advanced", "Master", etc.

  // Mechanics (rule-agnostic)
  cost: string | null;            // e.g., "1 Blood Point", "3 Mana"
  duration: string | null;        // e.g., "Instant", "1 scene", "Permanent"
  range: string | null;           // e.g., "Touch", "30 feet", "Self"

  // Display
  displayOrder: number;
  isKeyAbility: boolean;          // Show in quick view

  // Template linkage
  templateAbilityId: string | null;
  isCustom: boolean;

  // Metadata
  createdAt: Timestamp;
  updatedAt: Timestamp;
  updatedBy: string;
}
```

---

#### InventoryItem Document (Subcollection)

**Collection**: `characters/{characterId}/inventory`
**Document ID**: Auto-generated

Character inventory entries hold **instances** of items. Each instance links to a definition in the Game System's master catalog. Core attributes (name, description) are denormalized for offline display; the canonical definition lives in the Game System.

```typescript
interface InventoryItem {
  id: string;
  characterId: string;

  // Link to master definition (required when character is linked to a Game System)
  gameSystemItemId: string | null;  // Reference to gameSystems/{gsId}/itemCatalog/{itemId}

  // Core attributes (required; denormalized from catalog for offline/display)
  name: string;                     // e.g., "Healing Potion", "Silver Dagger"
  description: string | null;

  // Instance data
  quantity: number;                  // Default: 1

  // Classification (denormalized from catalog)
  category: string | null;           // "Weapon", "Consumable", "Quest Item"
  rarity: string | null;             // "Common", "Rare", "Legendary"

  // Properties (flexible key-value; instance overrides or catalog defaults)
  properties: {
    [key: string]: string | number | boolean;
  };

  // Source tracking
  source: 'player' | 'organizer' | 'transfer' | 'template';
  sourceEventId: string | null;      // Event where item was obtained
  catalogItemId: string | null;     // Reference to event item catalog (for distribution tracking)

  // Transfer tracking
  transferredFrom: string | null;    // Character ID if transferred
  transferredAt: Timestamp | null;

  // Display
  displayOrder: number;

  // Equipable submodule (when item definition has equipable config)
  isEquipped: boolean;               // Currently equipped
  equippedSlotId: string | null;     // Body part/slot ID when equipped (e.g., "torso")

  // Metadata
  createdAt: Timestamp;
  updatedAt: Timestamp;
  updatedBy: string;

  // Soft delete (for transfer tracking)
  isDeleted: boolean;
  deletedAt: Timestamp | null;
}
```

---

#### JournalEntry Document (Subcollection)

**Collection**: `characters/{characterId}/journal`
**Document ID**: Auto-generated

```typescript
interface JournalEntry {
  id: string;
  characterId: string;

  // Entry data
  title: string | null;           // Optional title
  content: string;                // Entry text (markdown supported)

  // Context
  eventId: string | null;         // Associated event (optional)
  eventName: string | null;       // Denormalized for offline display
  entryDate: Timestamp;           // When this happened in-game

  // Classification
  entryType: 'note' | 'event_log' | 'backstory' | 'goal' | 'relationship';
  tags: string[];                 // User-defined tags

  // Privacy
  isPrivate: boolean;             // Hidden from organizers if true

  // Metadata
  createdAt: Timestamp;
  updatedAt: Timestamp;
}
```

---

#### CharacterRelationship Document (Subcollection)

**Collection**: `characters/{characterId}/relationships`
**Document ID**: Auto-generated

Structured links to other characters (e.g., Ally, Rival, Mentor). Complements journal entries with `entryType: 'relationship'` for freeform notes.

```typescript
interface CharacterRelationship {
  id: string;
  characterId: string;            // This character (owner of the relationship)

  // Target
  targetCharacterId: string;      // Reference to characters/{characterId}
  targetCharacterName: string | null;  // Denormalized for offline display

  // Relationship data
  relationshipType: string;       // e.g., "Ally", "Rival", "Mentor", "Family", "Enemy"
  description: string | null;     // Optional context or notes
  mutual: boolean;               // If true, the relationship is bidirectional (both characters have it)

  // Display
  displayOrder: number;

  // Metadata
  createdAt: Timestamp;
  updatedAt: Timestamp;
  updatedBy: string;
}
```

**Note**: `targetCharacterId` may reference a character in the same event or a character in the same owner's portfolio. The app displays the relationship; it does not enforce visibility or permissions.

---

#### CharacterCurrency Document (Subcollection)

**Collection**: `characters/{characterId}/currencies`
**Document ID**: Auto-generated or slug from currency type

Tracks currency amounts (Gold, Silver, XP, etc.). Game Systems may define currency types in their config; character entries store amounts.

```typescript
interface CharacterCurrency {
  id: string;
  characterId: string;

  // Currency identity
  name: string;                   // e.g., "Gold", "Silver", "Experience Points"
  gameSystemCurrencyId: string | null;  // Reference to Game System currency definition (if defined)

  // Amount
  amount: number;                 // Current amount (can be negative if game allows)

  // Display
  displayOrder: number;

  // Metadata
  createdAt: Timestamp;
  updatedAt: Timestamp;
  updatedBy: string;
}
```

**Note**: For games with a single currency, one entry suffices. For multiple currencies (e.g., Gold + Silver + XP), one entry per type. Game Systems can define currency types in `config.currencyTypes` with optional `defaultValue`, `minValue`, etc.

---

#### Event Document

**Collection**: `events`
**Document ID**: Auto-generated UUID

```typescript
interface Event {
  id: string;

  // Ownership
  organizerId: string;            // Primary organizer user ID
  coOrganizerIds: string[];       // Additional organizers

  // Core information
  name: string;
  description: string;

  // Timing
  startDate: Timestamp;
  endDate: Timestamp;
  timezone: string;               // e.g., "America/New_York"

  // Location
  location: {
    name: string;                 // e.g., "Camp Woodland"
    address: string | null;
    coordinates: GeoPoint | null;
    notes: string | null;         // Parking, directions, etc.
  };

  // Game system
  gameSystem: string | null;
  templateId: string | null;      // Default character template

  // Configuration
  settings: {
    maxPlayers: number | null;
    registrationDeadline: Timestamp | null;
    allowPreGeneratedOnly: boolean;   // Only pre-gen characters allowed
    allowPlayerCharacters: boolean;   // Players can bring own characters
    requireCharacterApproval: boolean; // Organizer must approve characters
  };

  // Visibility
  visibility: 'public' | 'private' | 'unlisted';
  inviteCode: string | null;      // For private/unlisted events

  // Status
  status: 'draft' | 'published' | 'active' | 'completed' | 'cancelled';

  // Denormalized counts
  registrationCount: number;
  preGenCharacterCount: number;

  // Metadata
  createdAt: Timestamp;
  updatedAt: Timestamp;
  publishedAt: Timestamp | null;
}
```

---

#### Registration Document (Subcollection)

**Collection**: `events/{eventId}/registrations`
**Document ID**: Auto-generated

```typescript
interface Registration {
  id: string;
  eventId: string;

  // Player info
  userId: string;
  userDisplayName: string;        // Denormalized
  userEmail: string;              // Denormalized for organizer contact

  // Character linkage
  characterId: string | null;     // Linked character (may be null initially)
  characterName: string | null;   // Denormalized

  // Registration status
  status: 'pending' | 'approved' | 'waitlisted' | 'cancelled';

  // Organizer notes
  organizerNotes: string | null;  // Private notes for organizers

  // Metadata
  registeredAt: Timestamp;
  updatedAt: Timestamp;
  approvedAt: Timestamp | null;
  approvedBy: string | null;
}
```

---

#### GameSystem Document

**Collection**: `gameSystems`
**Document ID**: Auto-generated UUID

A GameSystem defines the configuration for a type of game (e.g., "Vampire: The Masquerade", "D&D 5e", "Nordic Freeform"). It specifies terminology and field structure that all characters in that game system will use.

```typescript
interface GameSystem {
  id: string;

  // Ownership
  creatorId: string;              // User who created this game system
  organizerIds: string[];         // Additional users who can manage

  // Core info
  name: string;                   // e.g., "Vampire: The Masquerade 5th Edition"
  shortName: string;              // e.g., "V5" (for compact display)
  description: string | null;
  imageUrl: string | null;        // Cover image/logo

  // Discovery
  visibility: 'public' | 'private' | 'unlisted';
  inviteCode: string | null;      // For private/unlisted systems
  qrCodeUrl: string | null;       // Generated QR code for joining

  // Categorization
  genre: string | null;           // "Horror", "Fantasy", "Sci-Fi", etc.
  tags: string[];                 // ["vampire", "world-of-darkness", "horror"]

  // UI Theme (optional; for game-specific theming)
  theme?: {
    primaryColor?: string;        // Hex, e.g. "#6366F1"
    primaryDarkColor?: string;     // Hover/active states
    accentColor?: string;         // Highlights, notifications
  };

  // Configuration
  config: {
    // Terminology mapping (what this game calls standard concepts)
    terminology: {
      attributes: string;         // e.g., "Attributes", "Stats", "Traits"
      abilities: string;          // e.g., "Disciplines", "Spells", "Skills"
      inventory: string;          // e.g., "Inventory", "Possessions", "Equipment"
      healthResource: string;     // e.g., "Health", "Hit Points", "Wounds"
      powerResource: string | null; // e.g., "Blood Pool", "Mana", "Essence" (optional)
      experience: string | null;  // e.g., "XP", "Experience", "Beats" (optional)
    };

    // Field categories (groups for organizing attributes)
    attributeCategories: string[]; // e.g., ["Physical", "Social", "Mental"]
    abilityCategories: string[];   // e.g., ["Disciplines", "Backgrounds", "Merits"]
    inventoryCategories: string[]; // e.g., ["Weapons", "Armor", "Consumables"]

    // Currency types (optional; for games that track Gold, Silver, XP, etc.)
    currencyTypes?: {
      id: string;                  // e.g., "gold", "xp"
      name: string;                // Display: "Gold", "Experience Points"
      defaultValue?: number;      // Starting amount for new characters (default: 0)
      minValue?: number;          // Optional floor (e.g., 0)
    }[];

    // Inventory Module config (optional submodules)
    inventoryConfig?: {
      equipSlots?: {               // Equipable submodule: body parts that can hold equipment
        id: string;                // e.g., "torso", "head", "hands"
        label: string;             // Display name
        maxEquipped: number;       // Slot limit (e.g., 1 armor on torso)
      }[];
      // Consumables submodule config TBD
    };

    // Death Module config (optional; null = death not used)
    deathConfig?: null | {
      submodule: 'simple' | 'stages';
      stages: {
        id: string;                // e.g., "dead", "dying"
        label: string;             // Display name
        exitRules: string;          // Game writer's rules for exiting this stage (displayed to players/staff)
      }[];

      // Resurrection submodule (when death enabled; defaults to override_only if absent)
      resurrection?: {
        mechanic: 'override_only' | 'fixed_count' | 'chance';
        // override_only: Organizer override always available; track resurrectionCount for reference (default)
        // fixed_count: maxResurrections per character; track count vs max
        // chance: Track count; difficulty increases each time (rules in text); we display count
        maxResurrections?: number;  // For fixed_count: e.g., 3 free resurrections per event
        chanceRules?: string;       // For chance: game writer's rules (e.g., "add +1 to difficulty each time")
      };
    };
    // Organizer override: Game runners can ALWAYS bring a character back when death is enabled, regardless of resurrection mechanic.

    // Display settings
    displaySettings: {
      showPowerResource: boolean;
      showExperience: boolean;
      quickStatCount: number;      // How many stats in quick view (default: 5)
      ratingMaxDefault: number;    // Default max for rating fields (e.g., 5 for dots)
    };

    // Character Creation Module
    characterCreation: {
      // Who creates characters
      creator: 'game_designer' | 'player' | 'both';
      // When game designer creates (pre-gens): freeform or rules-based. Required when creator is 'game_designer' or 'both'.
      designerCreationMode?: 'freeform' | 'rules_based';
      // freeform: designer can do anything, no template/validation constraints
      // rules_based: designer follows same templates and creation rules as players

      allowFreeformAttributes: boolean;  // Can players add custom attributes?
      allowFreeformAbilities: boolean;
      allowFreeformInventory: boolean;
      requireApproval: boolean;          // Must organizer approve new characters?
    };

    // Rule change policy (when rules affect character creation; for rules-based systems)
    ruleChangePolicy?: {
      affectedCharacterHandling: 'grandfather' | 'compensation' | 'rebuild_allowed';
      // grandfather: existing characters keep current state; new rules apply only to new characters
      // compensation: organizer awards compensation (build points, etc.); organizer applies manually
      // rebuild_allowed: players can change character to conform to new rules within a window
      buildCostChangeHandling?: 'free_upgrade' | 'pay_difference' | 'grandfather';
      // When build cost of something increases: free_upgrade (keep at no cost), pay_difference (must spend), grandfather (keep as-is)
      // Organizer override: always available; game runners can make exceptions per character
    };
  };

  // Rules versioning (increment when rules/templates/config change)
  rulesVersion: number;           // Current version; bump when character-affecting rules change
  // Workflow: When game designer changes rules, increment rulesVersion. New characters get rulesVersionAtCreation = rulesVersion. Characters with rulesVersionAtCreation < rulesVersion can be flagged as "affected by rule change" for organizer review per ruleChangePolicy.

  // Stats
  characterCount: number;         // Total characters using this system
  activeEventCount: number;       // Events currently using this system

  // Metadata
  createdAt: Timestamp;
  updatedAt: Timestamp;
  isArchived: boolean;
}
```

**Example Document**:
```json
{
  "id": "gs_vtm5",
  "creatorId": "user_org123",
  "organizerIds": ["user_org123", "user_coorg456"],
  "name": "Vampire: The Masquerade 5th Edition",
  "shortName": "V5",
  "description": "The latest edition of the classic World of Darkness vampire game.",
  "imageUrl": "gs://rolekeeper.appspot.com/gamesystems/vtm5_cover.jpg",
  "visibility": "public",
  "inviteCode": null,
  "qrCodeUrl": "gs://rolekeeper.appspot.com/qrcodes/gs_vtm5.png",
  "genre": "Horror",
  "tags": ["vampire", "world-of-darkness", "horror", "urban-fantasy"],
  "config": {
    "terminology": {
      "attributes": "Attributes",
      "abilities": "Disciplines",
      "inventory": "Possessions",
      "healthResource": "Health",
      "powerResource": "Blood Pool",
      "experience": "Experience"
    },
    "attributeCategories": ["Physical", "Social", "Mental"],
    "abilityCategories": ["Disciplines", "Backgrounds", "Merits & Flaws"],
    "inventoryCategories": ["Weapons", "Resources", "Haven"],
    "displaySettings": {
      "showPowerResource": true,
      "showExperience": true,
      "quickStatCount": 5,
      "ratingMaxDefault": 5
    },
    "characterCreation": {
      "creator": "player",
      "designerCreationMode": "rules_based",
      "allowFreeformAttributes": false,
      "allowFreeformAbilities": false,
      "allowFreeformInventory": true,
      "requireApproval": true
    }
  },
  "rulesVersion": 3,
  "characterCount": 147,
  "activeEventCount": 3,
  "createdAt": "2025-06-01T10:00:00Z",
  "updatedAt": "2025-12-01T14:30:00Z",
  "isArchived": false
}
```

---

#### GameSystemFieldDefinition (Subcollection)

**Collection**: `gameSystems/{gameSystemId}/fieldDefinitions`
**Document ID**: Auto-generated

Defines a standard field that characters in this game system should have.

```typescript
interface GameSystemFieldDefinition {
  id: string;
  gameSystemId: string;

  // Field identity
  name: string;                   // e.g., "Strength", "Blood Potency", "Clan"
  description: string | null;     // Tooltip/help text

  // Type definition
  fieldType: 'attribute' | 'ability' | 'resource' | 'info';
  valueType: 'string' | 'number' | 'boolean' | 'rating' | 'select' | 'text';

  // For number/rating types
  minValue: number | null;
  maxValue: number | null;
  defaultValue: string | number | boolean | null;

  // For select type
  options: string[] | null;       // e.g., ["Brujah", "Gangrel", "Ventrue"]

  // Categorization
  category: string | null;        // Must match a category in config
  displayOrder: number;

  // Behavior
  isRequired: boolean;            // Must have a value
  isQuickStat: boolean;           // Show in quick view
  isPlayerEditable: boolean;      // Can player modify, or organizer-only?

  // Metadata
  createdAt: Timestamp;
  updatedAt: Timestamp;
}
```

**Example Document** (Clan selector for V:tM):
```json
{
  "id": "field_clan",
  "gameSystemId": "gs_vtm5",
  "name": "Clan",
  "description": "Your character's vampiric bloodline",
  "fieldType": "info",
  "valueType": "select",
  "minValue": null,
  "maxValue": null,
  "defaultValue": null,
  "options": ["Brujah", "Gangrel", "Malkavian", "Nosferatu", "Toreador", "Tremere", "Ventrue", "Caitiff", "Thin-Blood"],
  "category": null,
  "displayOrder": 1,
  "isRequired": true,
  "isQuickStat": true,
  "isPlayerEditable": false,
  "createdAt": "2025-06-01T10:00:00Z",
  "updatedAt": "2025-06-01T10:00:00Z"
}
```

---

#### GameSystemItemDefinition (Subcollection) — Inventory Module Master Catalog

**Collection**: `gameSystems/{gameSystemId}/itemCatalog`
**Document ID**: Auto-generated

The **Inventory Module** uses a modular design. The Game System holds the **master database** of all inventory item definitions. Character inventory entries link to these definitions. The core has two required attributes (name, description); submodules add optional behavior.

**Core attributes (all items)**:
- `name` (required)
- `description` (required)

**Submodules** are enabled per Game System. When enabled, the item definition includes submodule-specific config.

```typescript
interface GameSystemItemDefinition {
  id: string;
  gameSystemId: string;

  // Core attributes (required)
  name: string;
  description: string;

  // Classification
  category: string | null;           // "Weapon", "Armor", "Consumable", "Quest Item"
  rarity: string | null;             // "Common", "Rare", "Legendary"

  // Default properties (flexible key-value for instances)
  defaultProperties: {
    [key: string]: string | number | boolean;
  };

  // Submodule: Equipable (optional; for boffer LARPs, etc.)
  equipable?: {
    bodySlotId: string;              // e.g., "torso", "head", "hands" — from GameSystem config
    modifiers: {                     // References modifier types from a separate module (e.g., DR system)
      modifierTypeId: string;         // e.g., "dr", "armor" — defined elsewhere
      value: number | string;
    }[];
  } | null;

  // Submodule: Consumables (optional; future)
  consumable?: {
    // TBD: use-once, quantity consumed per use, etc.
  } | null;

  // Metadata
  createdAt: Timestamp;
  updatedAt: Timestamp;
  createdBy: string;
}
```

**Equipable body slots** are defined in the Game System config (not per-item). Example:

```typescript
// In GameSystem.config.inventoryConfig (or similar)
equipSlots: [
  { id: "torso", label: "Torso", maxEquipped: 1 },
  { id: "head", label: "Head", maxEquipped: 1 },
  { id: "hands", label: "Hands", maxEquipped: 2 },
  { id: "feet", label: "Feet", maxEquipped: 1 },
]
```

Modifier types (DR, Armor, etc.) are defined in a **separate module**; the Inventory/Equipable submodule references them by ID but does not define the rules.

---

#### EventItemCatalogEntry (Subcollection of Event)

**Collection**: `events/{eventId}/itemCatalog`

Event-level catalog entries reference Game System item definitions and add **event-specific availability** (max per character, total in economy, distribution tracking). The item definition lives in the Game System; events control supply for this event.

```typescript
interface EventItemCatalogEntry {
  id: string;
  eventId: string;

  // Link to master definition
  gameSystemItemId: string;         // Reference to gameSystems/{gsId}/itemCatalog/{itemId}

  // Event-specific availability
  isDistributable: boolean;         // Can be awarded during event
  maxPerCharacter: number | null;   // Limit per character for this event
  totalAvailable: number | null;   // Total in game economy for this event

  // Tracking
  distributedCount: number;         // How many have been given out

  // Metadata
  createdAt: Timestamp;
  updatedAt: Timestamp;
  createdBy: string;
}
```

---

#### CharacterTemplate Document

**Collection**: `templates`
**Document ID**: Auto-generated UUID

```typescript
interface CharacterTemplate {
  id: string;

  // Ownership
  creatorId: string;              // User who created template
  eventId: string | null;         // Event-specific or null for reusable

  // Game System linkage
  gameSystemId: string;           // Reference to GameSystem document
  gameSystemName: string;         // Denormalized for display

  // Core info
  name: string;                   // e.g., "Chicago by Night - Neonate"
  description: string | null;

  // Settings (can override GameSystem defaults)
  settings: {
    allowCustomAttributes: boolean;   // Override: can players add custom attributes?
    allowCustomAbilities: boolean;
    requiredAttributeCategories: string[];
  };

  // Visibility
  visibility: 'private' | 'event' | 'public';  // Who can use this template

  // Metadata
  createdAt: Timestamp;
  updatedAt: Timestamp;
  usageCount: number;             // How many characters use this template
}
```

---

#### AttributeDefinition (Subcollection of Template)

**Collection**: `templates/{templateId}/attributeDefinitions`

```typescript
interface AttributeDefinition {
  id: string;
  templateId: string;

  // Definition
  name: string;
  description: string | null;

  // Type and constraints
  valueType: 'string' | 'number' | 'boolean' | 'rating' | 'select';
  defaultValue: string | number | boolean | null;

  // For number/rating types
  minValue: number | null;
  maxValue: number | null;

  // For select type
  options: string[] | null;       // e.g., ["Brujah", "Gangrel", "Ventrue"]

  // Display
  category: string | null;
  displayOrder: number;
  isRequired: boolean;
  isQuickStat: boolean;

  // Metadata
  createdAt: Timestamp;
  updatedAt: Timestamp;
}
```

---


#### ItemTransfer Document

**Collection**: `itemTransfers`
**Document ID**: Auto-generated

```typescript
interface ItemTransfer {
  id: string;

  // Transfer details
  itemId: string;                 // Original item document ID
  itemName: string;               // Denormalized
  quantity: number;

  // Parties
  fromCharacterId: string;
  fromCharacterName: string;      // Denormalized
  fromUserId: string;

  toCharacterId: string;
  toCharacterName: string;        // Denormalized
  toUserId: string;

  // Context
  eventId: string | null;         // Event where transfer occurred

  // Status
  status: 'pending' | 'accepted' | 'rejected' | 'cancelled' | 'expired';

  // Timestamps
  initiatedAt: Timestamp;
  respondedAt: Timestamp | null;
  expiresAt: Timestamp;           // Auto-expire after 7 days
}
```

---

#### PlotThread Document (Phase 3)

**Collection**: `plotThreads`
**Document ID**: Auto-generated

```typescript
interface PlotThread {
  id: string;

  // Ownership
  eventId: string;                // Associated event
  creatorId: string;              // User who created

  // Thread info
  title: string;
  description: string;            // Markdown supported

  // Status tracking
  status: 'planned' | 'active' | 'resolved' | 'dormant' | 'cancelled';
  priority: 'low' | 'medium' | 'high' | 'critical';

  // Relationships
  relatedCharacterIds: string[];  // Characters involved
  relatedThreadIds: string[];     // Connected plot threads
  prerequisiteThreadIds: string[]; // Must be resolved first

  // Planning
  targetResolutionDate: Timestamp | null;
  estimatedDuration: string | null; // "1 event", "3 events", etc.

  // Notes
  organizerNotes: string | null;  // Private planning notes

  // Metadata
  createdAt: Timestamp;
  updatedAt: Timestamp;
  resolvedAt: Timestamp | null;
}
```

---

### 1.3 Firestore Indexes

**Required Composite Indexes** (firestore.indexes.json):

```json
{
  "indexes": [
    {
      "collectionGroup": "characters",
      "queryScope": "COLLECTION",
      "fields": [
        { "fieldPath": "ownerId", "order": "ASCENDING" },
        { "fieldPath": "isArchived", "order": "ASCENDING" },
        { "fieldPath": "lastViewedAt", "order": "DESCENDING" }
      ]
    },
    {
      "collectionGroup": "characters",
      "queryScope": "COLLECTION",
      "fields": [
        { "fieldPath": "ownerId", "order": "ASCENDING" },
        { "fieldPath": "gameSystem", "order": "ASCENDING" },
        { "fieldPath": "lastViewedAt", "order": "DESCENDING" }
      ]
    },
    {
      "collectionGroup": "characters",
      "queryScope": "COLLECTION",
      "fields": [
        { "fieldPath": "linkedEventId", "order": "ASCENDING" },
        { "fieldPath": "isPreGenerated", "order": "ASCENDING" },
        { "fieldPath": "preGenStatus", "order": "ASCENDING" }
      ]
    },
    {
      "collectionGroup": "characters",
      "queryScope": "COLLECTION",
      "fields": [
        { "fieldPath": "linkedEventId", "order": "ASCENDING" },
        { "fieldPath": "characterType", "order": "ASCENDING" },
        { "fieldPath": "lastViewedAt", "order": "DESCENDING" }
      ]
    },
    {
      "collectionGroup": "events",
      "queryScope": "COLLECTION",
      "fields": [
        { "fieldPath": "visibility", "order": "ASCENDING" },
        { "fieldPath": "status", "order": "ASCENDING" },
        { "fieldPath": "startDate", "order": "ASCENDING" }
      ]
    },
    {
      "collectionGroup": "events",
      "queryScope": "COLLECTION",
      "fields": [
        { "fieldPath": "organizerId", "order": "ASCENDING" },
        { "fieldPath": "status", "order": "ASCENDING" },
        { "fieldPath": "startDate", "order": "DESCENDING" }
      ]
    },
    {
      "collectionGroup": "registrations",
      "queryScope": "COLLECTION_GROUP",
      "fields": [
        { "fieldPath": "userId", "order": "ASCENDING" },
        { "fieldPath": "status", "order": "ASCENDING" }
      ]
    },
    {
      "collectionGroup": "inventory",
      "queryScope": "COLLECTION",
      "fields": [
        { "fieldPath": "isDeleted", "order": "ASCENDING" },
        { "fieldPath": "category", "order": "ASCENDING" },
        { "fieldPath": "displayOrder", "order": "ASCENDING" }
      ]
    },
    {
      "collectionGroup": "journal",
      "queryScope": "COLLECTION",
      "fields": [
        { "fieldPath": "entryType", "order": "ASCENDING" },
        { "fieldPath": "entryDate", "order": "DESCENDING" }
      ]
    },
    {
      "collectionGroup": "itemTransfers",
      "queryScope": "COLLECTION",
      "fields": [
        { "fieldPath": "toUserId", "order": "ASCENDING" },
        { "fieldPath": "status", "order": "ASCENDING" },
        { "fieldPath": "initiatedAt", "order": "DESCENDING" }
      ]
    },
    {
      "collectionGroup": "plotThreads",
      "queryScope": "COLLECTION",
      "fields": [
        { "fieldPath": "eventId", "order": "ASCENDING" },
        { "fieldPath": "status", "order": "ASCENDING" },
        { "fieldPath": "priority", "order": "DESCENDING" }
      ]
    }
  ],
  "fieldOverrides": []
}
```

---

## Section 2: Flutter Application Architecture

### 2.1 Project Structure

```
lib/
|
+-- main.dart                     # App entry point
+-- app.dart                      # MaterialApp configuration
+-- firebase_options.dart         # Firebase configuration (generated)
|
+-- core/
|   +-- constants/
|   |   +-- app_constants.dart
|   |   +-- firestore_paths.dart
|   |   +-- storage_paths.dart
|   |
|   +-- errors/
|   |   +-- app_exception.dart
|   |   +-- failure.dart
|   |
|   +-- extensions/
|   |   +-- context_extensions.dart
|   |   +-- string_extensions.dart
|   |   +-- timestamp_extensions.dart
|   |
|   +-- theme/
|   |   +-- app_theme.dart
|   |   +-- app_colors.dart
|   |   +-- app_typography.dart
|   |
|   +-- utils/
|       +-- logger.dart
|       +-- validators.dart
|       +-- date_utils.dart
|
+-- data/
|   +-- models/                   # Data transfer objects / JSON models
|   |   +-- user_model.dart
|   |   +-- character_model.dart
|   |   +-- attribute_model.dart
|   |   +-- ability_model.dart
|   |   +-- inventory_item_model.dart
|   |   +-- journal_entry_model.dart
|   |   +-- event_model.dart
|   |   +-- registration_model.dart
|   |   +-- template_model.dart
|   |
|   +-- repositories/             # Data access layer
|   |   +-- auth_repository.dart
|   |   +-- user_repository.dart
|   |   +-- character_repository.dart
|   |   +-- event_repository.dart
|   |   +-- template_repository.dart
|   |   +-- sync_repository.dart
|   |
|   +-- datasources/
|   |   +-- remote/
|   |   |   +-- firestore_datasource.dart
|   |   |   +-- functions_datasource.dart
|   |   |   +-- storage_datasource.dart
|   |   |
|   |   +-- local/
|   |       +-- isar_datasource.dart
|   |       +-- secure_storage_datasource.dart
|   |
|   +-- mappers/                  # Model <-> Entity conversion
|       +-- character_mapper.dart
|       +-- event_mapper.dart
|
+-- domain/
|   +-- entities/                 # Business objects
|   |   +-- user.dart
|   |   +-- character.dart
|   |   +-- attribute.dart
|   |   +-- ability.dart
|   |   +-- inventory_item.dart
|   |   +-- event.dart
|   |
|   +-- services/                 # Business logic
|       +-- auth_service.dart
|       +-- character_service.dart
|       +-- sync_service.dart
|       +-- offline_service.dart
|
+-- features/
|   +-- auth/
|   |   +-- presentation/
|   |   |   +-- screens/
|   |   |   |   +-- login_screen.dart
|   |   |   |   +-- register_screen.dart
|   |   |   |   +-- forgot_password_screen.dart
|   |   |   |
|   |   |   +-- widgets/
|   |   |       +-- auth_form.dart
|   |   |       +-- social_login_buttons.dart
|   |   |
|   |   +-- providers/
|   |       +-- auth_provider.dart
|   |       +-- auth_state.dart
|   |
|   +-- portfolio/
|   |   +-- presentation/
|   |   |   +-- screens/
|   |   |   |   +-- portfolio_screen.dart
|   |   |   |
|   |   |   +-- widgets/
|   |   |       +-- character_card.dart
|   |   |       +-- character_list.dart
|   |   |       +-- portfolio_filter.dart
|   |   |       +-- empty_portfolio.dart
|   |   |
|   |   +-- providers/
|   |       +-- portfolio_provider.dart
|   |       +-- portfolio_filter_provider.dart
|   |
|   +-- character/
|   |   +-- presentation/
|   |   |   +-- screens/
|   |   |   |   +-- character_detail_screen.dart
|   |   |   |   +-- character_edit_screen.dart
|   |   |   |   +-- character_create_screen.dart
|   |   |   |   +-- quick_view_screen.dart
|   |   |   |
|   |   |   +-- widgets/
|   |   |       +-- character_header.dart
|   |   |       +-- attributes_section.dart
|   |   |       +-- abilities_section.dart
|   |   |       +-- inventory_section.dart
|   |   |       +-- journal_section.dart
|   |   |       +-- attribute_editor.dart
|   |   |       +-- ability_editor.dart
|   |   |
|   |   +-- providers/
|   |       +-- character_provider.dart
|   |       +-- character_detail_provider.dart
|   |       +-- attributes_provider.dart
|   |       +-- abilities_provider.dart
|   |       +-- inventory_provider.dart
|   |       +-- journal_provider.dart
|   |
|   +-- events/                   # Phase 2
|   |   +-- presentation/
|   |   |   +-- screens/
|   |   |   +-- widgets/
|   |   +-- providers/
|   |
|   +-- organizer/                # Phase 2
|   |   +-- presentation/
|   |   |   +-- screens/
|   |   |   +-- widgets/
|   |   +-- providers/
|   |
|   +-- profile/
|   |   +-- presentation/
|   |   +-- providers/
|   |
|   +-- settings/
|       +-- presentation/
|       +-- providers/
|
+-- routing/
|   +-- app_router.dart           # go_router configuration
|   +-- route_names.dart
|   +-- route_guards.dart
|
+-- providers/
|   +-- app_providers.dart        # Global providers
|   +-- connectivity_provider.dart
|   +-- sync_status_provider.dart
|
+-- widgets/                      # Shared widgets
    +-- common/
    |   +-- app_scaffold.dart
    |   +-- loading_indicator.dart
    |   +-- error_widget.dart
    |   +-- empty_state.dart
    |   +-- offline_banner.dart
    |
    +-- forms/
    |   +-- app_text_field.dart
    |   +-- app_dropdown.dart
    |   +-- rating_input.dart
    |
    +-- dialogs/
        +-- confirm_dialog.dart
        +-- error_dialog.dart
```

### 2.2 State Management Architecture (Riverpod)

**Provider Hierarchy**:

```
App-Level Providers
|
+-- authStateProvider            # Stream of auth state changes
+-- currentUserProvider          # Current authenticated user
+-- connectivityProvider         # Network connectivity status
+-- syncStatusProvider           # Global sync status
|
Feature-Level Providers
|
+-- portfolioProvider            # List of user's characters
+-- characterProvider(id)        # Single character with subcollections
+-- attributesProvider(charId)   # Character's attributes
+-- abilitiesProvider(charId)    # Character's abilities
+-- inventoryProvider(charId)    # Character's inventory
+-- journalProvider(charId)      # Character's journal
|
+-- eventsProvider               # User's events (registered + organized)
+-- eventDetailProvider(id)      # Single event with registrations
+-- registrationsProvider(eventId)  # Event's registrations
```

**Provider Patterns**:

```dart
// Auth state provider - Stream-based for real-time updates
final authStateProvider = StreamProvider<User?>((ref) {
  return ref.watch(authRepositoryProvider).authStateChanges;
});

// Current user provider - Derived from auth state
final currentUserProvider = FutureProvider<UserEntity?>((ref) async {
  final authState = ref.watch(authStateProvider);
  return authState.when(
    data: (user) async {
      if (user == null) return null;
      return ref.watch(userRepositoryProvider).getUser(user.uid);
    },
    loading: () => null,
    error: (_, __) => null,
  );
});

// Portfolio provider - Handles offline-first character list
final portfolioProvider = StateNotifierProvider<PortfolioNotifier, AsyncValue<List<Character>>>((ref) {
  return PortfolioNotifier(
    characterRepository: ref.watch(characterRepositoryProvider),
    syncService: ref.watch(syncServiceProvider),
    connectivityStatus: ref.watch(connectivityProvider),
  );
});

// Character detail provider - Family provider for individual characters
final characterDetailProvider = FutureProvider.family<CharacterDetail, String>((ref, characterId) async {
  final repository = ref.watch(characterRepositoryProvider);
  final isOnline = ref.watch(connectivityProvider);

  // Try local first, then remote
  final character = await repository.getCharacterWithDetails(
    characterId,
    forceRemote: isOnline,
  );

  return character;
});
```

### 2.3 Navigation Architecture (go_router)

```dart
// routing/app_router.dart

final appRouterProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(authStateProvider);

  return GoRouter(
    initialLocation: '/',
    refreshListenable: GoRouterRefreshStream(authState),
    redirect: (context, state) {
      final isLoggedIn = authState.valueOrNull != null;
      final isLoggingIn = state.matchedLocation.startsWith('/auth');

      if (!isLoggedIn && !isLoggingIn) {
        return '/auth/login';
      }
      if (isLoggedIn && isLoggingIn) {
        return '/portfolio';
      }
      return null;
    },
    routes: [
      // Auth routes
      GoRoute(
        path: '/auth',
        builder: (context, state) => const AuthScreen(),
        routes: [
          GoRoute(
            path: 'login',
            name: RouteNames.login,
            builder: (context, state) => const LoginScreen(),
          ),
          GoRoute(
            path: 'register',
            name: RouteNames.register,
            builder: (context, state) => const RegisterScreen(),
          ),
          GoRoute(
            path: 'forgot-password',
            name: RouteNames.forgotPassword,
            builder: (context, state) => const ForgotPasswordScreen(),
          ),
        ],
      ),

      // Main app shell with bottom navigation
      ShellRoute(
        builder: (context, state, child) => AppShell(child: child),
        routes: [
          // Portfolio tab
          GoRoute(
            path: '/portfolio',
            name: RouteNames.portfolio,
            builder: (context, state) => const PortfolioScreen(),
            routes: [
              GoRoute(
                path: 'create',
                name: RouteNames.createCharacter,
                builder: (context, state) => const CharacterCreateScreen(),
              ),
              GoRoute(
                path: 'character/:characterId',
                name: RouteNames.characterDetail,
                builder: (context, state) {
                  final characterId = state.pathParameters['characterId']!;
                  return CharacterDetailScreen(characterId: characterId);
                },
                routes: [
                  GoRoute(
                    path: 'edit',
                    name: RouteNames.characterEdit,
                    builder: (context, state) {
                      final characterId = state.pathParameters['characterId']!;
                      return CharacterEditScreen(characterId: characterId);
                    },
                  ),
                  GoRoute(
                    path: 'quick',
                    name: RouteNames.characterQuickView,
                    builder: (context, state) {
                      final characterId = state.pathParameters['characterId']!;
                      return QuickViewScreen(characterId: characterId);
                    },
                  ),
                ],
              ),
            ],
          ),

          // Events tab
          GoRoute(
            path: '/events',
            name: RouteNames.events,
            builder: (context, state) => const EventsScreen(),
            routes: [
              GoRoute(
                path: ':eventId',
                name: RouteNames.eventDetail,
                builder: (context, state) {
                  final eventId = state.pathParameters['eventId']!;
                  return EventDetailScreen(eventId: eventId);
                },
              ),
            ],
          ),

          // Profile tab
          GoRoute(
            path: '/profile',
            name: RouteNames.profile,
            builder: (context, state) => const ProfileScreen(),
            routes: [
              GoRoute(
                path: 'settings',
                name: RouteNames.settings,
                builder: (context, state) => const SettingsScreen(),
              ),
            ],
          ),
        ],
      ),

      // Organizer routes (separate shell for desktop-optimized layout)
      ShellRoute(
        builder: (context, state, child) => OrganizerShell(child: child),
        routes: [
          GoRoute(
            path: '/organizer',
            name: RouteNames.organizerDashboard,
            builder: (context, state) => const OrganizerDashboardScreen(),
            routes: [
              GoRoute(
                path: 'events',
                name: RouteNames.organizerEvents,
                builder: (context, state) => const OrganizerEventsScreen(),
              ),
              GoRoute(
                path: 'events/:eventId',
                name: RouteNames.organizerEventDetail,
                builder: (context, state) {
                  final eventId = state.pathParameters['eventId']!;
                  return OrganizerEventDetailScreen(eventId: eventId);
                },
              ),
              GoRoute(
                path: 'templates',
                name: RouteNames.templates,
                builder: (context, state) => const TemplatesScreen(),
              ),
            ],
          ),
        ],
      ),
    ],
    errorBuilder: (context, state) => ErrorScreen(error: state.error),
  );
});
```

---

## Section 3: Offline Architecture

### 3.1 Offline Strategy Overview

RoleKeeper uses a **hybrid offline-first architecture**:

1. **Read operations**: Always attempt local storage first, background sync with Firestore
2. **Write operations**: Write to local first, queue for sync when online
3. **Conflict resolution**: Last-write-wins with user notification for conflicts

```
+------------------+       +------------------+       +------------------+
|   Flutter UI     | <---> |   Repositories   | <---> |   Firestore      |
+------------------+       +------------------+       +------------------+
                                   |
                                   v
                           +------------------+
                           |   Isar (Local)   |
                           +------------------+
                                   ^
                                   |
                           +------------------+
                           |   Sync Engine    |
                           +------------------+
```

### 3.2 Local Database Schema (Isar)

```dart
// Isar collections for offline storage

@collection
class LocalCharacter {
  Id id = Isar.autoIncrement;

  @Index(unique: true)
  late String firestoreId;

  late String ownerId;
  late String name;
  String? pronouns;
  String? description;
  String? portraitPath;  // Local file path for cached image

  @enumerated
  CharacterType characterType = CharacterType.player;  // Default for backward compat

  String? gameSystem;
  String? gameCampaign;
  String? linkedEventId;
  String? templateId;

  late bool isPreGenerated;
  String? preGenStatus;
  String? claimedBy;

  late DateTime createdAt;
  late DateTime updatedAt;
  late DateTime lastViewedAt;

  // Sync metadata
  @enumerated
  late SyncStatus syncStatus;
  DateTime? lastSyncedAt;
  int syncVersion = 0;

  // Embedded quick access data
  late String quickStatsJson;  // Serialized Map
  late List<String> keyAbilities;

  late bool isArchived;
  DateTime? archivedAt;

  // Relationships via backlinks
  final attributes = IsarLinks<LocalAttribute>();
  final abilities = IsarLinks<LocalAbility>();
  final inventory = IsarLinks<LocalInventoryItem>();
  final currencies = IsarLinks<LocalCharacterCurrency>();
  final relationships = IsarLinks<LocalCharacterRelationship>();
  final journal = IsarLinks<LocalJournalEntry>();
}

enum CharacterType { player, npc }

@collection
class LocalAttribute {
  Id id = Isar.autoIncrement;

  @Index(unique: true)
  late String firestoreId;

  @Index()
  late String characterId;

  late String name;
  late String valueJson;  // Serialized dynamic value
  late String valueType;
  int? maxValue;

  String? category;
  late int displayOrder;
  late bool isQuickStat;

  String? templateAttributeId;
  late bool isCustom;

  late DateTime createdAt;
  late DateTime updatedAt;
  late String updatedBy;

  @enumerated
  late SyncStatus syncStatus;

  @Backlink(to: 'attributes')
  final character = IsarLink<LocalCharacter>();
}

@collection
class LocalAbility {
  Id id = Isar.autoIncrement;

  @Index(unique: true)
  late String firestoreId;

  @Index()
  late String characterId;

  late String name;
  late String description;

  @enumerated
  AbilityType abilityType = AbilityType.ability;  // Default for backward compat

  String? category;
  String? tier;
  String? cost;
  String? duration;
  String? range;

  late int displayOrder;
  late bool isKeyAbility;

  String? templateAbilityId;
  late bool isCustom;

  late DateTime createdAt;
  late DateTime updatedAt;
  late String updatedBy;

  @enumerated
  late SyncStatus syncStatus;

  @Backlink(to: 'abilities')
  final character = IsarLink<LocalCharacter>();
}

enum AbilityType { ability, advantage, disadvantage }

@collection
class LocalInventoryItem {
  Id id = Isar.autoIncrement;

  @Index(unique: true)
  late String firestoreId;

  @Index()
  late String characterId;

  late String name;
  String? description;
  late int quantity;

  String? category;
  String? rarity;
  late String propertiesJson;  // Serialized Map

  late String source;
  String? sourceEventId;
  String? catalogItemId;

  String? transferredFrom;
  DateTime? transferredAt;

  late int displayOrder;
  late bool isEquipped;

  late DateTime createdAt;
  late DateTime updatedAt;
  late String updatedBy;

  late bool isDeleted;
  DateTime? deletedAt;

  @enumerated
  late SyncStatus syncStatus;

  @Backlink(to: 'inventory')
  final character = IsarLink<LocalCharacter>();
}

@collection
class LocalCharacterCurrency {
  Id id = Isar.autoIncrement;

  @Index(unique: true)
  late String firestoreId;

  @Index()
  late String characterId;

  late String name;
  String? gameSystemCurrencyId;
  late int amount;
  late int displayOrder;

  late DateTime createdAt;
  late DateTime updatedAt;
  late String updatedBy;

  @enumerated
  late SyncStatus syncStatus;

  @Backlink(to: 'currencies')
  final character = IsarLink<LocalCharacter>();
}

@collection
class LocalCharacterRelationship {
  Id id = Isar.autoIncrement;

  @Index(unique: true)
  late String firestoreId;

  @Index()
  late String characterId;

  late String targetCharacterId;
  String? targetCharacterName;
  late String relationshipType;
  String? description;
  late bool mutual;
  late int displayOrder;

  late DateTime createdAt;
  late DateTime updatedAt;
  late String updatedBy;

  @enumerated
  late SyncStatus syncStatus;

  @Backlink(to: 'relationships')
  final character = IsarLink<LocalCharacter>();
}

@collection
class LocalJournalEntry {
  Id id = Isar.autoIncrement;

  @Index(unique: true)
  late String firestoreId;

  @Index()
  late String characterId;

  String? title;
  late String content;

  String? eventId;
  String? eventName;
  late DateTime entryDate;

  late String entryType;
  late List<String> tags;
  late bool isPrivate;

  late DateTime createdAt;
  late DateTime updatedAt;

  @enumerated
  late SyncStatus syncStatus;

  @Backlink(to: 'journal')
  final character = IsarLink<LocalCharacter>();
}

@collection
class SyncQueue {
  Id id = Isar.autoIncrement;

  late String entityType;  // 'character', 'attribute', etc.
  late String entityId;
  late String operation;   // 'create', 'update', 'delete'
  late String payloadJson; // Serialized change data

  late DateTime queuedAt;
  int retryCount = 0;
  DateTime? lastRetryAt;
  String? lastError;

  @enumerated
  late SyncQueueStatus status;
}

enum SyncStatus {
  synced,
  pending,
  conflict,
  error,
}

enum SyncQueueStatus {
  pending,
  processing,
  failed,
  completed,
}
```

### 3.3 Sync Service Implementation

```dart
// domain/services/sync_service.dart

class SyncService {
  final CharacterRepository _characterRepository;
  final IsarDatasource _localDb;
  final FirestoreDatasource _remoteDb;
  final ConnectivityService _connectivity;

  StreamSubscription? _connectivitySubscription;
  Timer? _syncTimer;

  final _syncStatusController = BehaviorSubject<SyncStatus>.seeded(SyncStatus.idle);
  Stream<SyncStatus> get syncStatus => _syncStatusController.stream;

  /// Initialize sync service and start listeners
  Future<void> initialize() async {
    // Listen for connectivity changes
    _connectivitySubscription = _connectivity.onConnectivityChanged.listen((status) {
      if (status == ConnectivityStatus.online) {
        _triggerSync();
      }
    });

    // Periodic sync check (every 5 minutes when online)
    _syncTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      if (_connectivity.isOnline) {
        _triggerSync();
      }
    });
  }

  /// Sync all pending changes to Firestore
  Future<SyncResult> syncAll() async {
    if (!_connectivity.isOnline) {
      return SyncResult.offline();
    }

    _syncStatusController.add(SyncStatus.syncing);

    try {
      // 1. Process outgoing queue (local changes -> remote)
      final outgoingResult = await _processOutgoingQueue();

      // 2. Fetch incoming changes (remote -> local)
      final incomingResult = await _fetchIncomingChanges();

      // 3. Resolve any conflicts
      final conflictResult = await _resolveConflicts();

      _syncStatusController.add(SyncStatus.synced);

      return SyncResult.success(
        uploaded: outgoingResult.count,
        downloaded: incomingResult.count,
        conflicts: conflictResult.count,
      );
    } catch (e) {
      _syncStatusController.add(SyncStatus.error);
      return SyncResult.error(e.toString());
    }
  }

  /// Queue a local change for sync
  Future<void> queueChange({
    required String entityType,
    required String entityId,
    required String operation,
    required Map<String, dynamic> payload,
  }) async {
    final queueItem = SyncQueue()
      ..entityType = entityType
      ..entityId = entityId
      ..operation = operation
      ..payloadJson = jsonEncode(payload)
      ..queuedAt = DateTime.now()
      ..status = SyncQueueStatus.pending;

    await _localDb.isar.writeTxn(() async {
      await _localDb.isar.syncQueues.put(queueItem);
    });

    // Attempt immediate sync if online
    if (_connectivity.isOnline) {
      _triggerSync();
    }
  }

  Future<OutgoingResult> _processOutgoingQueue() async {
    final pendingItems = await _localDb.isar.syncQueues
        .filter()
        .statusEqualTo(SyncQueueStatus.pending)
        .sortByQueuedAt()
        .findAll();

    int successCount = 0;

    for (final item in pendingItems) {
      try {
        await _localDb.isar.writeTxn(() async {
          item.status = SyncQueueStatus.processing;
          await _localDb.isar.syncQueues.put(item);
        });

        final payload = jsonDecode(item.payloadJson) as Map<String, dynamic>;

        switch (item.operation) {
          case 'create':
            await _remoteDb.createDocument(
              collection: _getCollection(item.entityType),
              documentId: item.entityId,
              data: payload,
            );
            break;
          case 'update':
            await _remoteDb.updateDocument(
              collection: _getCollection(item.entityType),
              documentId: item.entityId,
              data: payload,
            );
            break;
          case 'delete':
            await _remoteDb.deleteDocument(
              collection: _getCollection(item.entityType),
              documentId: item.entityId,
            );
            break;
        }

        // Mark as completed and remove from queue
        await _localDb.isar.writeTxn(() async {
          await _localDb.isar.syncQueues.delete(item.id);
        });

        successCount++;
      } catch (e) {
        // Mark as failed and increment retry count
        await _localDb.isar.writeTxn(() async {
          item.status = SyncQueueStatus.failed;
          item.retryCount++;
          item.lastRetryAt = DateTime.now();
          item.lastError = e.toString();
          await _localDb.isar.syncQueues.put(item);
        });
      }
    }

    return OutgoingResult(count: successCount);
  }

  Future<IncomingResult> _fetchIncomingChanges() async {
    final currentUser = await _getCurrentUser();
    if (currentUser == null) return IncomingResult(count: 0);

    // Get last sync timestamp
    final lastSync = await _getLastSyncTimestamp();

    // Fetch characters modified since last sync
    final remoteCharacters = await _remoteDb.queryDocuments(
      collection: 'characters',
      where: [
        QueryCondition('ownerId', isEqualTo: currentUser.uid),
        QueryCondition('updatedAt', isGreaterThan: lastSync),
      ],
    );

    int downloadCount = 0;

    for (final doc in remoteCharacters) {
      final localChar = await _localDb.isar.localCharacters
          .filter()
          .firestoreIdEqualTo(doc.id)
          .findFirst();

      if (localChar == null) {
        // New character from remote - create locally
        await _createLocalCharacter(doc);
        downloadCount++;
      } else if (localChar.syncStatus == SyncStatus.synced) {
        // No local changes - safe to update
        await _updateLocalCharacter(localChar, doc);
        downloadCount++;
      } else {
        // Local changes exist - mark as conflict
        await _markAsConflict(localChar, doc);
      }
    }

    await _updateLastSyncTimestamp();

    return IncomingResult(count: downloadCount);
  }

  Future<ConflictResult> _resolveConflicts() async {
    // Default strategy: Last-write-wins with user notification
    final conflicts = await _localDb.isar.localCharacters
        .filter()
        .syncStatusEqualTo(SyncStatus.conflict)
        .findAll();

    int resolvedCount = 0;

    for (final conflict in conflicts) {
      // For MVP: Remote wins, but preserve local changes in a backup
      await _backupLocalChanges(conflict);

      // Fetch and apply remote version
      final remoteDoc = await _remoteDb.getDocument(
        collection: 'characters',
        documentId: conflict.firestoreId,
      );

      if (remoteDoc != null) {
        await _updateLocalCharacter(conflict, remoteDoc);
        resolvedCount++;
      }
    }

    return ConflictResult(count: resolvedCount);
  }

  void dispose() {
    _connectivitySubscription?.cancel();
    _syncTimer?.cancel();
    _syncStatusController.close();
  }
}
```

### 3.4 Offline Data Caching Strategy

**What Gets Cached**:

| Data Type | Caching Strategy | Max Age | Priority |
|-----------|-----------------|---------|----------|
| User's characters (list) | Always cached | 7 days | High |
| Character details (attributes, abilities, inventory) | Cached on first view | 7 days | High |
| Character portraits | Cached on download | 30 days | Medium |
| Events user is registered for | Cached on registration | 1 day | Medium |
| Event schedules | Cached on event view | 1 day | Medium |
| Templates | Cached on use | 30 days | Low |
| Other players' public characters | Not cached | - | None |

**Cache Size Management**:

```dart
class CacheManager {
  static const int maxCharacterCount = 50;
  static const int maxTotalSizeBytes = 100 * 1024 * 1024; // 100MB

  Future<void> pruneCache() async {
    final totalSize = await _calculateCacheSize();

    if (totalSize > maxTotalSizeBytes) {
      // Remove oldest accessed characters first
      final characters = await _localDb.isar.localCharacters
          .filter()
          .ownerIdEqualTo(currentUserId)
          .sortByLastViewedAt()
          .findAll();

      for (final char in characters) {
        if (await _calculateCacheSize() <= maxTotalSizeBytes * 0.8) {
          break;
        }

        // Keep recently viewed (last 7 days)
        if (char.lastViewedAt.isAfter(DateTime.now().subtract(Duration(days: 7)))) {
          continue;
        }

        await _removeCharacterFromCache(char);
      }
    }
  }

  Future<void> prioritizeCharacter(String characterId) async {
    // Mark character as high priority for offline access
    final char = await _localDb.isar.localCharacters
        .filter()
        .firestoreIdEqualTo(characterId)
        .findFirst();

    if (char != null) {
      await _localDb.isar.writeTxn(() async {
        char.lastViewedAt = DateTime.now();
        await _localDb.isar.localCharacters.put(char);
      });
    }
  }
}
```

---

### 3.5 Conflict Resolution Strategy

RoleKeeper handles sync conflicts through a combination of automatic resolution rules and user-facing conflict UI. The strategy varies by data type and conflict scenario.

#### 3.5.1 Conflict Detection

A conflict occurs when:
1. **Local pending + Remote changed**: Local has unsynced changes AND remote has been updated since last sync
2. **Concurrent edits**: Two clients edit the same field while both offline, then sync
3. **Delete vs. Modify**: One client deletes a resource while another modifies it

**Detection Logic**:
```dart
enum ConflictType {
  none,
  localPendingRemoteChanged,   // Most common: offline edits meet remote updates
  concurrentEdit,               // Same field edited on multiple devices
  deleteVsModify,               // Resource deleted on one side, modified on other
  parentDeleted,                // Parent resource (character) was deleted
}

ConflictType detectConflict({
  required LocalEntity local,
  required RemoteEntity remote,
}) {
  // No conflict if local is synced
  if (local.syncStatus == SyncStatus.synced) {
    return ConflictType.none;
  }

  // No conflict if remote hasn't changed since our last sync
  if (remote.updatedAt <= local.lastSyncedAt) {
    return ConflictType.none;
  }

  // Check for delete scenarios
  if (remote.isDeleted && local.syncStatus == SyncStatus.pending) {
    return ConflictType.deleteVsModify;
  }

  // Local pending + remote changed = conflict
  return ConflictType.localPendingRemoteChanged;
}
```

#### 3.5.2 Resolution Rules by Data Type

| Data Type | Conflict Rule | Rationale |
|-----------|---------------|-----------|
| **Character core fields** (name, description, pronouns) | Last-write-wins | Low-stakes; user can re-edit |
| **Attributes** | Last-write-wins | Organizer updates should take precedence |
| **Abilities** | Last-write-wins | Organizer updates should take precedence |
| **Inventory (quantity)** | **Additive merge** | Both changes likely intentional |
| **Inventory (new items)** | **Union merge** | Keep all items from both sources |
| **Inventory (removed items)** | Remote wins | Organizer removals are authoritative |
| **Journal entries** | **Keep both** | Personal data; never lose player notes |
| **Quick stats** | Remote wins | Derived from attributes; recalculate |

#### 3.5.3 Detailed Resolution Strategies

##### Character Core Fields (Last-Write-Wins)

```dart
Future<void> resolveCharacterConflict(LocalCharacter local, RemoteCharacter remote) async {
  // Compare timestamps
  if (remote.updatedAt.isAfter(local.updatedAt)) {
    // Remote wins - apply remote changes
    await _applyRemoteCharacter(local, remote);
  } else {
    // Local wins - push local changes (queue for sync)
    await _queueLocalCharacterSync(local);
  }

  // Always preserve local journal entries regardless of winner
  // (handled separately in journal resolution)
}
```

##### Inventory Quantity (Additive Merge)

When both local and remote have modified the same item's quantity:

```dart
Future<void> resolveInventoryQuantityConflict({
  required LocalInventoryItem local,
  required RemoteInventoryItem remote,
  required int lastSyncedQuantity, // Quantity at last successful sync
}) async {
  // Calculate deltas
  final localDelta = local.quantity - lastSyncedQuantity;
  final remoteDelta = remote.quantity - lastSyncedQuantity;

  // Additive merge: apply both deltas
  final mergedQuantity = lastSyncedQuantity + localDelta + remoteDelta;

  // Ensure non-negative
  final finalQuantity = max(0, mergedQuantity);

  // Update both local and queue remote update
  local.quantity = finalQuantity;
  local.syncStatus = SyncStatus.pending;
  await _saveLocal(local);
  await _queueSync(local);
}
```

**Example Scenario**:
- Last synced quantity: 5
- Player uses 2 items offline (local: 3)
- Organizer awards 3 items while player offline (remote: 8)
- Merged result: 5 + (-2) + (+3) = **6 items**

##### Inventory New Items (Union Merge)

```dart
Future<void> resolveInventoryListConflict({
  required List<LocalInventoryItem> localItems,
  required List<RemoteInventoryItem> remoteItems,
}) async {
  final localIds = localItems.map((i) => i.firestoreId).toSet();
  final remoteIds = remoteItems.map((i) => i.firestoreId).toSet();

  // Items only in remote - add to local
  final newRemoteItems = remoteItems.where((i) => !localIds.contains(i.firestoreId));
  for (final item in newRemoteItems) {
    await _createLocalItem(item);
    // Notify user of new items
    await _notifyNewItem(item);
  }

  // Items only in local (created offline) - queue for remote sync
  final newLocalItems = localItems.where((i) => !remoteIds.contains(i.firestoreId));
  for (final item in newLocalItems) {
    await _queueSync(item);
  }

  // Items in both - check for quantity/property conflicts individually
  final sharedIds = localIds.intersection(remoteIds);
  for (final id in sharedIds) {
    final localItem = localItems.firstWhere((i) => i.firestoreId == id);
    final remoteItem = remoteItems.firstWhere((i) => i.firestoreId == id);
    await _resolveItemConflict(localItem, remoteItem);
  }
}
```

##### Journal Entries (Keep Both)

Journal entries are personal data that should never be lost:

```dart
Future<void> resolveJournalConflict({
  required LocalJournalEntry local,
  required RemoteJournalEntry remote,
}) async {
  // Same entry ID with different content = create a duplicate with suffix
  if (local.content != remote.content) {
    // Keep remote version with original ID
    await _updateLocalJournal(local.firestoreId, remote);

    // Create new entry for local version
    final localCopy = LocalJournalEntry()
      ..firestoreId = '${local.firestoreId}_local_${DateTime.now().millisecondsSinceEpoch}'
      ..characterId = local.characterId
      ..title = '${local.title ?? "Entry"} (recovered)'
      ..content = local.content
      ..entryDate = local.entryDate
      ..entryType = local.entryType
      ..tags = [...local.tags, 'conflict-recovered']
      ..isPrivate = local.isPrivate
      ..createdAt = local.createdAt
      ..updatedAt = DateTime.now()
      ..syncStatus = SyncStatus.pending;

    await _saveLocal(localCopy);
    await _queueSync(localCopy);

    // Notify user
    await _notifyConflictResolved(
      message: 'A journal entry was edited on another device. Both versions have been saved.',
    );
  }
}
```

#### 3.5.4 Organizer vs. Organizer Conflicts

When two organizers (or organizer + co-organizer) edit the same resource:

| Scenario | Resolution | Notification |
|----------|------------|--------------|
| Same character attribute | Last-write-wins | Both notified of change |
| Same event details | Last-write-wins | Both notified |
| Conflicting item distributions | Both applied | Audit log shows both |
| Plot thread edits | Last-write-wins | Both notified, backup created |

**Implementation**: Organizer changes always go through Cloud Functions, which use Firestore transactions:

```typescript
// In Cloud Function: pushCharacterUpdate
await db.runTransaction(async (transaction) => {
  const charRef = db.collection('characters').doc(characterId);
  const charDoc = await transaction.get(charRef);

  // Check if another organizer updated since we read
  const currentVersion = charDoc.data()?.updateVersion ?? 0;
  if (currentVersion !== expectedVersion) {
    throw new functions.https.HttpsError(
      'aborted',
      'Character was modified by another organizer. Please refresh and try again.',
      { code: 'CONCURRENT_MODIFICATION', currentVersion }
    );
  }

  // Apply update with incremented version
  transaction.update(charRef, {
    ...updates,
    updateVersion: currentVersion + 1,
    updatedAt: FieldValue.serverTimestamp(),
    updatedBy: context.auth.uid,
  });
});
```

#### 3.5.5 Delete vs. Modify Conflicts

| Scenario | Resolution | User Action |
|----------|------------|-------------|
| Player deletes character locally, organizer updates remotely | Prompt user: "This character was updated. Delete anyway?" | User confirms or cancels |
| Organizer deletes item, player modifies offline | Item removed, player notified | Informational only |
| Player deletes journal entry, different content on remote | Delete proceeds | None (user's intent clear) |

```dart
Future<ConflictResolution> handleDeleteModifyConflict({
  required LocalEntity local,
  required RemoteEntity remote,
  required bool localIsDelete,
}) async {
  if (localIsDelete) {
    // User tried to delete, but remote was modified
    if (remote.updatedAt.isAfter(local.updatedAt)) {
      // Show user the remote changes and confirm delete
      final userConfirmed = await _showDeleteConfirmation(
        entity: remote,
        message: 'This ${local.entityType} was updated on another device. Delete anyway?',
      );

      if (userConfirmed) {
        await _queueDelete(local);
        return ConflictResolution.deleteConfirmed;
      } else {
        // Restore local to match remote
        await _applyRemote(local, remote);
        return ConflictResolution.deleteCancelled;
      }
    }
  } else {
    // Remote deleted, local was modified
    // For player-owned data: recreate on remote
    // For organizer-controlled data: accept deletion, notify user
    if (_isOrganizerControlled(local.entityType)) {
      await _removeLocal(local);
      await _notifyRemoved(local);
      return ConflictResolution.remoteDeleteApplied;
    } else {
      // Recreate - player data wins
      local.firestoreId = _generateNewId();
      await _queueSync(local);
      return ConflictResolution.localRecreated;
    }
  }
}
```

#### 3.5.6 Conflict UI Patterns

Most conflicts resolve automatically. When user input is required:

**Inline Notification** (non-blocking):
```
┌─────────────────────────────────────────────────┐
│ ℹ️  3 items synced from organizer               │
│     • +2 Gold Coins                             │
│     • +1 Healing Potion                         │
│     • Sword damage updated (3 → 4)              │
│                                         [Dismiss]│
└─────────────────────────────────────────────────┘
```

**Modal Confirmation** (blocking, rare):
```
┌─────────────────────────────────────────────────┐
│  ⚠️  Sync Conflict                              │
│                                                 │
│  Your character "Elara" was updated on another  │
│  device while you were offline.                 │
│                                                 │
│  Your version:  Health: 5, Mana: 3              │
│  Other version: Health: 7, Mana: 3              │
│                                                 │
│  [Keep Mine]  [Use Other]  [View Diff]          │
└─────────────────────────────────────────────────┘
```

#### 3.5.7 Conflict Audit Trail

All conflict resolutions are logged for debugging and support:

```dart
@collection
class ConflictLog {
  Id id = Isar.autoIncrement;

  late String entityType;
  late String entityId;
  late String conflictType;
  late String resolution;          // 'auto_remote_wins', 'auto_merge', 'user_chose_local', etc.

  String? localDataJson;           // Snapshot of local state
  String? remoteDataJson;          // Snapshot of remote state
  String? mergedDataJson;          // Result after resolution

  late DateTime occurredAt;
  late DateTime resolvedAt;
  String? userAction;              // If user made a choice
}
```

#### 3.5.8 Conflict Prevention Strategies

To minimize conflicts:

1. **Frequent sync**: Sync every 5 minutes when online (already implemented)
2. **Sync on app foreground**: Trigger sync when app becomes active
3. **Real-time listeners for active views**: Use Firestore snapshots for currently-viewed character
4. **Optimistic locking for organizer operations**: Version numbers on documents
5. **Field-level timestamps**: Track when each field was last modified (future enhancement)

```dart
// Sync on app lifecycle
class AppLifecycleObserver extends WidgetsBindingObserver {
  final SyncService _syncService;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // App came to foreground - sync immediately
      _syncService.syncAll();
    } else if (state == AppLifecycleState.paused) {
      // App going to background - flush pending writes
      _syncService.flushPendingWrites();
    }
  }
}
```

---

## Section 4: API Contracts and Cloud Functions

### 4.1 Direct Firestore Access Patterns

Most read operations use direct Firestore access with security rules enforcement:

**Character Portfolio Query**:
```dart
// Get all characters owned by current user
FirebaseFirestore.instance
    .collection('characters')
    .where('ownerId', isEqualTo: currentUser.uid)
    .where('isArchived', isEqualTo: false)
    .orderBy('lastViewedAt', descending: true)
    .limit(50)
    .snapshots();
```

**Character with Subcollections**:
```dart
// Get character document
final charDoc = await FirebaseFirestore.instance
    .collection('characters')
    .doc(characterId)
    .get();

// Get attributes subcollection
final attributes = await FirebaseFirestore.instance
    .collection('characters')
    .doc(characterId)
    .collection('attributes')
    .orderBy('displayOrder')
    .get();

// Get abilities subcollection
final abilities = await FirebaseFirestore.instance
    .collection('characters')
    .doc(characterId)
    .collection('abilities')
    .orderBy('displayOrder')
    .get();
```

**Public Events Query**:
```dart
// Get upcoming public events
FirebaseFirestore.instance
    .collection('events')
    .where('visibility', isEqualTo: 'public')
    .where('status', isEqualTo: 'published')
    .where('startDate', isGreaterThan: Timestamp.now())
    .orderBy('startDate')
    .limit(20)
    .snapshots();
```

### 4.2 Cloud Functions Specifications

#### Function: claimPreGeneratedCharacter

**Purpose**: Allows a player to claim a pre-generated character for an event.

**Type**: Callable Function

```typescript
// functions/src/characters/claimPreGeneratedCharacter.ts

import * as functions from 'firebase-functions';
import * as admin from 'firebase-admin';

interface ClaimRequest {
  characterId: string;
  eventId: string;
}

interface ClaimResponse {
  success: boolean;
  characterId?: string;
  error?: string;
}

export const claimPreGeneratedCharacter = functions.https.onCall(
  async (data: ClaimRequest, context): Promise<ClaimResponse> => {
    // Auth check
    if (!context.auth) {
      throw new functions.https.HttpsError(
        'unauthenticated',
        'User must be authenticated'
      );
    }

    const userId = context.auth.uid;
    const { characterId, eventId } = data;

    // Validate input
    if (!characterId || !eventId) {
      throw new functions.https.HttpsError(
        'invalid-argument',
        'characterId and eventId are required'
      );
    }

    const db = admin.firestore();

    return db.runTransaction(async (transaction) => {
      // Get character document
      const charRef = db.collection('characters').doc(characterId);
      const charDoc = await transaction.get(charRef);

      if (!charDoc.exists) {
        throw new functions.https.HttpsError('not-found', 'Character not found');
      }

      const charData = charDoc.data()!;

      // Verify character is pre-generated and available
      if (!charData.isPreGenerated) {
        throw new functions.https.HttpsError(
          'failed-precondition',
          'Character is not pre-generated'
        );
      }

      if (charData.preGenStatus !== 'available') {
        throw new functions.https.HttpsError(
          'already-exists',
          'Character has already been claimed'
        );
      }

      if (charData.linkedEventId !== eventId) {
        throw new functions.https.HttpsError(
          'failed-precondition',
          'Character is not associated with this event'
        );
      }

      // Verify user is registered for the event
      const registrationQuery = await db
        .collection('events')
        .doc(eventId)
        .collection('registrations')
        .where('userId', '==', userId)
        .where('status', 'in', ['pending', 'approved'])
        .limit(1)
        .get();

      if (registrationQuery.empty) {
        throw new functions.https.HttpsError(
          'failed-precondition',
          'User must be registered for the event'
        );
      }

      // Claim the character
      transaction.update(charRef, {
        claimedBy: userId,
        ownerId: userId,  // Transfer ownership
        preGenStatus: 'claimed',
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      // Update registration with character link
      const regDoc = registrationQuery.docs[0];
      transaction.update(regDoc.ref, {
        characterId: characterId,
        characterName: charData.name,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      return {
        success: true,
        characterId: characterId,
      };
    });
  }
);
```

**Flutter Invocation**:
```dart
final result = await FirebaseFunctions.instance
    .httpsCallable('claimPreGeneratedCharacter')
    .call({
      'characterId': characterId,
      'eventId': eventId,
    });

if (result.data['success']) {
  // Character claimed successfully
}
```

---

#### Function: pushCharacterUpdate

**Purpose**: Allows organizers to update a player's character (items, attributes, etc.).

**Type**: Callable Function

```typescript
// functions/src/characters/pushCharacterUpdate.ts

interface UpdateRequest {
  characterId: string;
  eventId: string;
  updates: {
    addAttributes?: Array<{
      name: string;
      value: string | number | boolean;
      valueType: string;
      category?: string;
    }>;
    updateAttributes?: Array<{
      attributeId: string;
      value: string | number | boolean;
    }>;
    addItems?: Array<{
      name: string;
      description?: string;
      quantity: number;
      catalogItemId?: string;
    }>;
    removeItems?: Array<{
      itemId: string;
      quantity?: number;  // Remove specific quantity, or all if not specified
    }>;
    addAbilities?: Array<{
      name: string;
      description: string;
      abilityType?: 'ability' | 'advantage' | 'disadvantage';
      category?: string;
    }>;
    updateCurrencies?: Array<{
      currencyId?: string;
      name?: string;
      amount: number;
    }>;
    addRelationships?: Array<{
      targetCharacterId: string;
      targetCharacterName?: string;
      relationshipType: string;
      description?: string;
      mutual?: boolean;
    }>;
    removeRelationships?: Array<{
      relationshipId: string;
    }>;
  };
  notifyPlayer?: boolean;
  notificationMessage?: string;
}

export const pushCharacterUpdate = functions.https.onCall(
  async (data: UpdateRequest, context) => {
    if (!context.auth) {
      throw new functions.https.HttpsError('unauthenticated', 'Must be authenticated');
    }

    const organizerId = context.auth.uid;
    const { characterId, eventId, updates, notifyPlayer, notificationMessage } = data;

    const db = admin.firestore();

    // Verify organizer has permission for this event
    const eventDoc = await db.collection('events').doc(eventId).get();
    if (!eventDoc.exists) {
      throw new functions.https.HttpsError('not-found', 'Event not found');
    }

    const eventData = eventDoc.data()!;
    const isOrganizer = eventData.organizerId === organizerId ||
                        eventData.coOrganizerIds?.includes(organizerId);

    if (!isOrganizer) {
      throw new functions.https.HttpsError(
        'permission-denied',
        'Only organizers can push character updates'
      );
    }

    // Verify character is linked to this event
    const charDoc = await db.collection('characters').doc(characterId).get();
    if (!charDoc.exists || charDoc.data()!.linkedEventId !== eventId) {
      throw new functions.https.HttpsError(
        'failed-precondition',
        'Character is not linked to this event'
      );
    }

    const batch = db.batch();
    const charRef = db.collection('characters').doc(characterId);
    const timestamp = admin.firestore.FieldValue.serverTimestamp();

    // Process attribute additions
    if (updates.addAttributes) {
      for (const attr of updates.addAttributes) {
        const attrRef = charRef.collection('attributes').doc();
        batch.set(attrRef, {
          id: attrRef.id,
          characterId,
          name: attr.name,
          value: attr.value,
          valueType: attr.valueType,
          category: attr.category || null,
          displayOrder: 999, // Will be sorted later
          isQuickStat: false,
          isCustom: false,
          createdAt: timestamp,
          updatedAt: timestamp,
          updatedBy: organizerId,
        });
      }
    }

    // Process item additions
    if (updates.addItems) {
      for (const item of updates.addItems) {
        const itemRef = charRef.collection('inventory').doc();
        batch.set(itemRef, {
          id: itemRef.id,
          characterId,
          name: item.name,
          description: item.description || null,
          quantity: item.quantity,
          source: 'organizer',
          sourceEventId: eventId,
          catalogItemId: item.catalogItemId || null,
          displayOrder: 999,
          isEquipped: false,
          isDeleted: false,
          createdAt: timestamp,
          updatedAt: timestamp,
          updatedBy: organizerId,
        });
      }
    }

    // Process item removals
    if (updates.removeItems) {
      for (const removal of updates.removeItems) {
        const itemRef = charRef.collection('inventory').doc(removal.itemId);
        const itemDoc = await itemRef.get();

        if (itemDoc.exists) {
          const currentQty = itemDoc.data()!.quantity;
          const removeQty = removal.quantity || currentQty;

          if (removeQty >= currentQty) {
            // Remove entirely (soft delete)
            batch.update(itemRef, {
              isDeleted: true,
              deletedAt: timestamp,
              updatedBy: organizerId,
            });
          } else {
            // Reduce quantity
            batch.update(itemRef, {
              quantity: currentQty - removeQty,
              updatedAt: timestamp,
              updatedBy: organizerId,
            });
          }
        }
      }
    }

    // Process ability additions
    if (updates.addAbilities) {
      for (const ab of updates.addAbilities) {
        const abRef = charRef.collection('abilities').doc();
        batch.set(abRef, {
          id: abRef.id,
          characterId,
          name: ab.name,
          description: ab.description,
          abilityType: ab.abilityType || 'ability',
          category: ab.category || null,
          displayOrder: 999,
          isKeyAbility: false,
          isCustom: false,
          createdAt: timestamp,
          updatedAt: timestamp,
          updatedBy: organizerId,
        });
      }
    }

    // Process currency updates
    if (updates.updateCurrencies) {
      for (const curr of updates.updateCurrencies) {
        if (curr.currencyId) {
          const currRef = charRef.collection('currencies').doc(curr.currencyId);
          batch.update(currRef, { amount: curr.amount, updatedAt: timestamp, updatedBy: organizerId });
        } else if (curr.name) {
          const currRef = charRef.collection('currencies').doc();
          batch.set(currRef, {
            id: currRef.id,
            characterId,
            name: curr.name,
            amount: curr.amount,
            displayOrder: 999,
            createdAt: timestamp,
            updatedAt: timestamp,
            updatedBy: organizerId,
          });
        }
      }
    }

    // Process relationship additions
    if (updates.addRelationships) {
      for (const rel of updates.addRelationships) {
        const relRef = charRef.collection('relationships').doc();
        batch.set(relRef, {
          id: relRef.id,
          characterId,
          targetCharacterId: rel.targetCharacterId,
          targetCharacterName: rel.targetCharacterName || null,
          relationshipType: rel.relationshipType,
          description: rel.description || null,
          mutual: rel.mutual || false,
          displayOrder: 999,
          createdAt: timestamp,
          updatedAt: timestamp,
          updatedBy: organizerId,
        });
      }
    }

    // Process relationship removals
    if (updates.removeRelationships) {
      for (const rel of updates.removeRelationships) {
        batch.delete(charRef.collection('relationships').doc(rel.relationshipId));
      }
    }

    // Update character's updatedAt
    batch.update(charRef, { updatedAt: timestamp });

    await batch.commit();

    // Send notification if requested
    if (notifyPlayer) {
      const ownerId = charDoc.data()!.ownerId;
      await db.collection('users').doc(ownerId).collection('notifications').add({
        type: 'character_update',
        title: 'Character Updated',
        message: notificationMessage || `Your character has been updated by the organizer.`,
        characterId,
        eventId,
        read: false,
        createdAt: timestamp,
      });

      // Trigger FCM push notification
      // (Implementation depends on FCM setup)
    }

    return { success: true };
  }
);
```

---

#### Function: initiateItemTransfer

**Purpose**: Player initiates a transfer of an item to another player's character.

**Type**: Callable Function

```typescript
// functions/src/inventory/initiateItemTransfer.ts

interface TransferRequest {
  itemId: string;
  fromCharacterId: string;
  toCharacterId: string;
  quantity: number;
  eventId?: string;
}

export const initiateItemTransfer = functions.https.onCall(
  async (data: TransferRequest, context) => {
    if (!context.auth) {
      throw new functions.https.HttpsError('unauthenticated', 'Must be authenticated');
    }

    const userId = context.auth.uid;
    const { itemId, fromCharacterId, toCharacterId, quantity, eventId } = data;

    const db = admin.firestore();

    // Verify sender owns the source character
    const fromCharDoc = await db.collection('characters').doc(fromCharacterId).get();
    if (!fromCharDoc.exists || fromCharDoc.data()!.ownerId !== userId) {
      throw new functions.https.HttpsError('permission-denied', 'Not your character');
    }

    // Verify item exists and has sufficient quantity
    const itemRef = db.collection('characters').doc(fromCharacterId)
                      .collection('inventory').doc(itemId);
    const itemDoc = await itemRef.get();

    if (!itemDoc.exists || itemDoc.data()!.isDeleted) {
      throw new functions.https.HttpsError('not-found', 'Item not found');
    }

    if (itemDoc.data()!.quantity < quantity) {
      throw new functions.https.HttpsError('failed-precondition', 'Insufficient quantity');
    }

    // Get recipient character and owner
    const toCharDoc = await db.collection('characters').doc(toCharacterId).get();
    if (!toCharDoc.exists) {
      throw new functions.https.HttpsError('not-found', 'Recipient character not found');
    }

    const toUserId = toCharDoc.data()!.ownerId;

    // Create transfer request
    const transferRef = db.collection('itemTransfers').doc();
    const itemData = itemDoc.data()!;

    await transferRef.set({
      id: transferRef.id,
      itemId,
      itemName: itemData.name,
      quantity,
      fromCharacterId,
      fromCharacterName: fromCharDoc.data()!.name,
      fromUserId: userId,
      toCharacterId,
      toCharacterName: toCharDoc.data()!.name,
      toUserId,
      eventId: eventId || null,
      status: 'pending',
      initiatedAt: admin.firestore.FieldValue.serverTimestamp(),
      expiresAt: admin.firestore.Timestamp.fromDate(
        new Date(Date.now() + 7 * 24 * 60 * 60 * 1000) // 7 days
      ),
    });

    // Notify recipient
    await db.collection('users').doc(toUserId).collection('notifications').add({
      type: 'item_transfer_request',
      title: 'Item Transfer Request',
      message: `${fromCharDoc.data()!.name} wants to give you ${quantity}x ${itemData.name}`,
      transferId: transferRef.id,
      read: false,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    return { success: true, transferId: transferRef.id };
  }
);
```

---

#### Function: acceptItemTransfer

**Purpose**: Recipient accepts or rejects an item transfer.

```typescript
// functions/src/inventory/acceptItemTransfer.ts

interface AcceptRequest {
  transferId: string;
  accept: boolean;
}

export const acceptItemTransfer = functions.https.onCall(
  async (data: AcceptRequest, context) => {
    if (!context.auth) {
      throw new functions.https.HttpsError('unauthenticated', 'Must be authenticated');
    }

    const userId = context.auth.uid;
    const { transferId, accept } = data;

    const db = admin.firestore();

    const transferRef = db.collection('itemTransfers').doc(transferId);
    const transferDoc = await transferRef.get();

    if (!transferDoc.exists) {
      throw new functions.https.HttpsError('not-found', 'Transfer not found');
    }

    const transfer = transferDoc.data()!;

    // Verify recipient
    if (transfer.toUserId !== userId) {
      throw new functions.https.HttpsError('permission-denied', 'Not the recipient');
    }

    // Verify still pending
    if (transfer.status !== 'pending') {
      throw new functions.https.HttpsError('failed-precondition', 'Transfer already processed');
    }

    // Check expiration
    if (transfer.expiresAt.toDate() < new Date()) {
      await transferRef.update({ status: 'expired' });
      throw new functions.https.HttpsError('failed-precondition', 'Transfer has expired');
    }

    if (!accept) {
      // Reject transfer
      await transferRef.update({
        status: 'rejected',
        respondedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      return { success: true, status: 'rejected' };
    }

    // Accept transfer - use transaction for atomicity
    return db.runTransaction(async (transaction) => {
      // Re-fetch transfer in transaction
      const txTransferDoc = await transaction.get(transferRef);
      const txTransfer = txTransferDoc.data()!;

      // Verify source item still exists with sufficient quantity
      const sourceItemRef = db.collection('characters').doc(txTransfer.fromCharacterId)
                              .collection('inventory').doc(txTransfer.itemId);
      const sourceItemDoc = await transaction.get(sourceItemRef);

      if (!sourceItemDoc.exists || sourceItemDoc.data()!.quantity < txTransfer.quantity) {
        throw new functions.https.HttpsError(
          'failed-precondition',
          'Source item no longer available'
        );
      }

      const sourceItem = sourceItemDoc.data()!;
      const timestamp = admin.firestore.FieldValue.serverTimestamp();

      // Reduce quantity from source (or soft delete if depleted)
      const remainingQty = sourceItem.quantity - txTransfer.quantity;
      if (remainingQty <= 0) {
        transaction.update(sourceItemRef, {
          isDeleted: true,
          deletedAt: timestamp,
          quantity: 0,
        });
      } else {
        transaction.update(sourceItemRef, {
          quantity: remainingQty,
          updatedAt: timestamp,
        });
      }

      // Create item in recipient's inventory
      const destItemRef = db.collection('characters').doc(txTransfer.toCharacterId)
                            .collection('inventory').doc();
      transaction.set(destItemRef, {
        id: destItemRef.id,
        characterId: txTransfer.toCharacterId,
        name: sourceItem.name,
        description: sourceItem.description,
        quantity: txTransfer.quantity,
        category: sourceItem.category,
        rarity: sourceItem.rarity,
        properties: sourceItem.properties || {},
        source: 'transfer',
        sourceEventId: txTransfer.eventId,
        catalogItemId: sourceItem.catalogItemId,
        transferredFrom: txTransfer.fromCharacterId,
        transferredAt: timestamp,
        displayOrder: 999,
        isEquipped: false,
        isDeleted: false,
        createdAt: timestamp,
        updatedAt: timestamp,
        updatedBy: userId,
      });

      // Update transfer status
      transaction.update(transferRef, {
        status: 'accepted',
        respondedAt: timestamp,
      });

      return { success: true, status: 'accepted', newItemId: destItemRef.id };
    });
  }
);
```

---

### 4.3 Scheduled Functions

#### Function: expireTransfers

**Purpose**: Clean up expired item transfers (runs daily).

```typescript
// functions/src/scheduled/expireTransfers.ts

export const expireTransfers = functions.pubsub
  .schedule('every 24 hours')
  .onRun(async (context) => {
    const db = admin.firestore();

    const expiredQuery = await db.collection('itemTransfers')
      .where('status', '==', 'pending')
      .where('expiresAt', '<', admin.firestore.Timestamp.now())
      .get();

    const batch = db.batch();
    let count = 0;

    for (const doc of expiredQuery.docs) {
      batch.update(doc.ref, {
        status: 'expired',
        respondedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      count++;

      // Firestore batch limit is 500
      if (count >= 500) {
        await batch.commit();
        count = 0;
      }
    }

    if (count > 0) {
      await batch.commit();
    }

    console.log(`Expired ${expiredQuery.size} transfers`);
    return null;
  });
```

---

## Section 5: Authentication and Authorization

### 5.1 Authentication Flow

**Supported Auth Methods**:
1. Email/Password (primary)
2. Google Sign-In
3. Apple Sign-In (iOS)

```dart
// features/auth/providers/auth_provider.dart

final authServiceProvider = Provider<AuthService>((ref) {
  return AuthService(FirebaseAuth.instance);
});

class AuthService {
  final FirebaseAuth _auth;

  AuthService(this._auth);

  Stream<User?> get authStateChanges => _auth.authStateChanges();

  User? get currentUser => _auth.currentUser;

  /// Email/password sign up
  Future<UserCredential> signUpWithEmail({
    required String email,
    required String password,
    required String displayName,
  }) async {
    final credential = await _auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );

    // Update display name
    await credential.user?.updateDisplayName(displayName);

    // Create user document in Firestore
    await _createUserDocument(credential.user!, displayName);

    return credential;
  }

  /// Email/password sign in
  Future<UserCredential> signInWithEmail({
    required String email,
    required String password,
  }) async {
    return _auth.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
  }

  /// Google sign in
  Future<UserCredential> signInWithGoogle() async {
    final googleUser = await GoogleSignIn().signIn();
    if (googleUser == null) throw Exception('Google sign in cancelled');

    final googleAuth = await googleUser.authentication;
    final credential = GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );

    final userCredential = await _auth.signInWithCredential(credential);

    // Create user document if new user
    if (userCredential.additionalUserInfo?.isNewUser ?? false) {
      await _createUserDocument(
        userCredential.user!,
        googleUser.displayName ?? 'Player',
      );
    }

    return userCredential;
  }

  /// Apple sign in
  Future<UserCredential> signInWithApple() async {
    final appleCredential = await SignInWithApple.getAppleIDCredential(
      scopes: [
        AppleIDAuthorizationScopes.email,
        AppleIDAuthorizationScopes.fullName,
      ],
    );

    final oauthCredential = OAuthProvider('apple.com').credential(
      idToken: appleCredential.identityToken,
      accessToken: appleCredential.authorizationCode,
    );

    final userCredential = await _auth.signInWithCredential(oauthCredential);

    if (userCredential.additionalUserInfo?.isNewUser ?? false) {
      final displayName = [
        appleCredential.givenName,
        appleCredential.familyName,
      ].where((s) => s != null).join(' ').trim();

      await _createUserDocument(
        userCredential.user!,
        displayName.isNotEmpty ? displayName : 'Player',
      );
    }

    return userCredential;
  }

  /// Password reset
  Future<void> sendPasswordResetEmail(String email) async {
    await _auth.sendPasswordResetEmail(email: email);
  }

  /// Sign out
  Future<void> signOut() async {
    await GoogleSignIn().signOut();
    await _auth.signOut();
  }

  Future<void> _createUserDocument(User user, String displayName) async {
    await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
      'uid': user.uid,
      'email': user.email,
      'displayName': displayName,
      'avatarUrl': user.photoURL,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'lastActiveAt': FieldValue.serverTimestamp(),
      'settings': {
        'theme': 'system',
        'notificationsEnabled': true,
        'offlineCharacterLimit': 20,
        'defaultCharacterView': 'full',
      },
      'isOrganizer': false,
      'isPremium': false,
      'characterCount': 0,
      'eventCount': 0,
    });
  }
}
```

### 5.2 Role and Permission Model

**Roles**:

| Role | Description | Source |
|------|-------------|--------|
| Player | Default role for all authenticated users | Firebase Auth (authenticated) |
| Organizer | Users who have created events | Firestore `events.organizerId` |
| Co-Organizer | Users granted organizer access to specific events | Firestore `events.coOrganizerIds` |
| Staff | Users assigned staff roles for specific events | Firestore `events/{eventId}/staff` |

**Permission Matrix**:

| Resource | Player | Organizer (own events) | Co-Organizer | Staff |
|----------|--------|------------------------|--------------|-------|
| Own characters | CRUD | CRUD | - | - |
| Other characters (linked to event) | Read (if public) | Read/Update | Read/Update | Read |
| Pre-gen characters (available) | Claim | CRUD | CRUD | Read |
| Events (own) | - | CRUD | Read/Update | Read |
| Events (registered) | Read | Read | Read | Read |
| Registrations (own) | CRUD | - | - | - |
| Registrations (event) | - | Read | Read | Read |
| Templates (own) | - | CRUD | - | - |
| Item Catalog (event) | Read | CRUD | CRUD | Read |
| Plot Threads | - | CRUD | CRUD | Read |

### 5.3 Custom Claims (Future Enhancement)

For Phase 3 with complex staff permissions, custom claims can be added:

```typescript
// Cloud Function to set custom claims
export const setUserRole = functions.https.onCall(async (data, context) => {
  // Verify caller is admin
  if (!context.auth?.token.admin) {
    throw new functions.https.HttpsError('permission-denied', 'Not an admin');
  }

  const { userId, role, eventId } = data;

  const claims: Record<string, any> = {};

  if (role === 'organizer') {
    claims.organizer = true;
  }

  if (eventId) {
    // Event-specific role
    claims[`event_${eventId}`] = role;
  }

  await admin.auth().setCustomUserClaims(userId, claims);

  return { success: true };
});
```

---

## Section 6: Security Architecture

### 6.1 Firestore Security Rules

```javascript
// firestore.rules

rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {

    // ============================================
    // HELPER FUNCTIONS
    // ============================================

    // Check if user is authenticated
    function isAuthenticated() {
      return request.auth != null;
    }

    // Check if user is the owner of a resource
    function isOwner(userId) {
      return isAuthenticated() && request.auth.uid == userId;
    }

    // Check if user is organizer of an event
    function isEventOrganizer(eventId) {
      let event = get(/databases/$(database)/documents/events/$(eventId));
      return isAuthenticated() && (
        request.auth.uid == event.data.organizerId ||
        request.auth.uid in event.data.coOrganizerIds
      );
    }

    // Check if user is staff of an event
    function isEventStaff(eventId) {
      return isAuthenticated() && exists(
        /databases/$(database)/documents/events/$(eventId)/staff/$(request.auth.uid)
      );
    }

    // Check if user is registered for an event
    function isRegisteredForEvent(eventId) {
      return isAuthenticated() && exists(
        /databases/$(database)/documents/events/$(eventId)/registrations/$(request.auth.uid)
      );
    }

    // Validate required string fields
    function hasRequiredString(field) {
      return field in request.resource.data &&
             request.resource.data[field] is string &&
             request.resource.data[field].size() > 0;
    }

    // Validate string length
    function isValidLength(field, maxLen) {
      return !(field in request.resource.data) ||
             request.resource.data[field] == null ||
             request.resource.data[field].size() <= maxLen;
    }

    // Validate field is not being modified (immutable)
    function isUnchanged(field) {
      return !(field in request.resource.data) ||
             request.resource.data[field] == resource.data[field];
    }

    // Validate timestamp is server time (not client-provided)
    function isServerTimestamp(field) {
      return request.resource.data[field] == request.time;
    }

    // Validate enum values
    function isValidEnum(field, allowedValues) {
      return !(field in request.resource.data) ||
             request.resource.data[field] in allowedValues;
    }

    // Validate non-negative number
    function isNonNegativeInt(field) {
      return !(field in request.resource.data) ||
             (request.resource.data[field] is int &&
              request.resource.data[field] >= 0);
    }

    // ============================================
    // USERS COLLECTION
    // ============================================

    match /users/{userId} {
      // Users can read their own profile
      allow read: if isOwner(userId);

      // Users can create their own profile (on signup)
      allow create: if isOwner(userId) &&
                       hasRequiredString('displayName') &&
                       hasRequiredString('email');

      // Users can update their own profile (limited fields)
      allow update: if isOwner(userId) &&
                       !('uid' in request.resource.data) &&
                       !('createdAt' in request.resource.data);

      // Users cannot delete their profile (handled by Cloud Function)
      allow delete: if false;

      // Notifications subcollection
      match /notifications/{notificationId} {
        allow read: if isOwner(userId);
        allow update: if isOwner(userId) &&
                         request.resource.data.keys().hasOnly(['read']);
        allow delete: if isOwner(userId);
      }
    }

    // ============================================
    // CHARACTERS COLLECTION
    // ============================================

    match /characters/{characterId} {
      // Read rules
      allow read: if isAuthenticated() && (
        // Owner can always read
        resource.data.ownerId == request.auth.uid ||
        // Organizers can read characters linked to their events
        (resource.data.linkedEventId != null &&
         isEventOrganizer(resource.data.linkedEventId)) ||
        // Available pre-gen characters for events user is registered for
        (resource.data.isPreGenerated == true &&
         resource.data.preGenStatus == 'available' &&
         resource.data.linkedEventId != null &&
         isRegisteredForEvent(resource.data.linkedEventId))
      );

      // Create rules - only owner can create their own characters
      allow create: if isAuthenticated() &&
                       request.resource.data.ownerId == request.auth.uid &&
                       hasRequiredString('name') &&
                       isValidLength('name', 100) &&
                       isValidLength('description', 10000) &&
                       isValidLength('pronouns', 50) &&
                       request.resource.data.isPreGenerated == false &&
                       (!('characterType' in request.resource.data) ||
                        request.resource.data.characterType in ['player', 'npc']) &&
                       isServerTimestamp('createdAt');

      // Update rules
      allow update: if isAuthenticated() && (
        // Owner can update own characters
        (resource.data.ownerId == request.auth.uid &&
         request.resource.data.ownerId == request.auth.uid &&
         // Validate immutable fields
         isUnchanged('ownerId') &&
         isUnchanged('createdAt') &&
         isUnchanged('isPreGenerated') &&
         // Validate lengths
         isValidLength('name', 100) &&
         isValidLength('description', 10000)) ||
        // Organizers can update characters linked to their events
        (resource.data.linkedEventId != null &&
         isEventOrganizer(resource.data.linkedEventId) &&
         // Organizers cannot change ownership
         isUnchanged('ownerId'))
      );

      // Delete rules - soft delete only
      allow delete: if false;

      // ----------------------------------------
      // Attributes subcollection
      // ----------------------------------------
      match /attributes/{attributeId} {
        allow read: if isAuthenticated() && (
          get(/databases/$(database)/documents/characters/$(characterId)).data.ownerId == request.auth.uid ||
          isEventOrganizer(get(/databases/$(database)/documents/characters/$(characterId)).data.linkedEventId)
        );

        allow create, update: if isAuthenticated() && (
          get(/databases/$(database)/documents/characters/$(characterId)).data.ownerId == request.auth.uid ||
          isEventOrganizer(get(/databases/$(database)/documents/characters/$(characterId)).data.linkedEventId)
        );

        allow delete: if isAuthenticated() &&
          get(/databases/$(database)/documents/characters/$(characterId)).data.ownerId == request.auth.uid;
      }

      // ----------------------------------------
      // Abilities subcollection
      // ----------------------------------------
      match /abilities/{abilityId} {
        allow read: if isAuthenticated() && (
          get(/databases/$(database)/documents/characters/$(characterId)).data.ownerId == request.auth.uid ||
          isEventOrganizer(get(/databases/$(database)/documents/characters/$(characterId)).data.linkedEventId)
        );

        allow create, update: if isAuthenticated() && (
          get(/databases/$(database)/documents/characters/$(characterId)).data.ownerId == request.auth.uid ||
          isEventOrganizer(get(/databases/$(database)/documents/characters/$(characterId)).data.linkedEventId)
        );

        allow delete: if isAuthenticated() &&
          get(/databases/$(database)/documents/characters/$(characterId)).data.ownerId == request.auth.uid;
      }

      // ----------------------------------------
      // Inventory subcollection
      // ----------------------------------------
      match /inventory/{itemId} {
        allow read: if isAuthenticated() && (
          get(/databases/$(database)/documents/characters/$(characterId)).data.ownerId == request.auth.uid ||
          isEventOrganizer(get(/databases/$(database)/documents/characters/$(characterId)).data.linkedEventId)
        );

        // Players can add items (from player source)
        allow create: if isAuthenticated() &&
          get(/databases/$(database)/documents/characters/$(characterId)).data.ownerId == request.auth.uid &&
          request.resource.data.source == 'player';

        // Players can update own items, organizers can update any
        allow update: if isAuthenticated() && (
          get(/databases/$(database)/documents/characters/$(characterId)).data.ownerId == request.auth.uid ||
          isEventOrganizer(get(/databases/$(database)/documents/characters/$(characterId)).data.linkedEventId)
        );

        // Soft delete only
        allow delete: if false;
      }

      // ----------------------------------------
      // Currencies subcollection
      // ----------------------------------------
      match /currencies/{currencyId} {
        allow read: if isAuthenticated() && (
          get(/databases/$(database)/documents/characters/$(characterId)).data.ownerId == request.auth.uid ||
          isEventOrganizer(get(/databases/$(database)/documents/characters/$(characterId)).data.linkedEventId)
        );

        allow create, update: if isAuthenticated() && (
          get(/databases/$(database)/documents/characters/$(characterId)).data.ownerId == request.auth.uid ||
          isEventOrganizer(get(/databases/$(database)/documents/characters/$(characterId)).data.linkedEventId)
        );

        allow delete: if isAuthenticated() &&
          get(/databases/$(database)/documents/characters/$(characterId)).data.ownerId == request.auth.uid;
      }

      // ----------------------------------------
      // Relationships subcollection
      // ----------------------------------------
      match /relationships/{relationshipId} {
        allow read: if isAuthenticated() && (
          get(/databases/$(database)/documents/characters/$(characterId)).data.ownerId == request.auth.uid ||
          isEventOrganizer(get(/databases/$(database)/documents/characters/$(characterId)).data.linkedEventId)
        );

        allow create, update: if isAuthenticated() && (
          get(/databases/$(database)/documents/characters/$(characterId)).data.ownerId == request.auth.uid ||
          isEventOrganizer(get(/databases/$(database)/documents/characters/$(characterId)).data.linkedEventId)
        );

        allow delete: if isAuthenticated() &&
          get(/databases/$(database)/documents/characters/$(characterId)).data.ownerId == request.auth.uid;
      }

      // ----------------------------------------
      // Journal subcollection
      // ----------------------------------------
      match /journal/{entryId} {
        // Only owner can read/write journal (private)
        allow read, write: if isAuthenticated() &&
          get(/databases/$(database)/documents/characters/$(characterId)).data.ownerId == request.auth.uid;
      }
    }

    // ============================================
    // EVENTS COLLECTION
    // ============================================

    match /events/{eventId} {
      // Read rules
      allow read: if isAuthenticated() && (
        // Public events can be read by anyone
        resource.data.visibility == 'public' ||
        // Organizers can read
        resource.data.organizerId == request.auth.uid ||
        request.auth.uid in resource.data.coOrganizerIds ||
        // Registered players can read
        isRegisteredForEvent(eventId)
      );

      // Create - authenticated users can create events
      allow create: if isAuthenticated() &&
                       request.resource.data.organizerId == request.auth.uid &&
                       hasRequiredString('name');

      // Update - only organizers
      allow update: if isAuthenticated() && (
        resource.data.organizerId == request.auth.uid ||
        request.auth.uid in resource.data.coOrganizerIds
      );

      // Delete - only primary organizer
      allow delete: if isAuthenticated() &&
        resource.data.organizerId == request.auth.uid;

      // ----------------------------------------
      // Registrations subcollection
      // ----------------------------------------
      match /registrations/{registrationId} {
        // Players can read their own, organizers can read all
        allow read: if isAuthenticated() && (
          resource.data.userId == request.auth.uid ||
          isEventOrganizer(eventId)
        );

        // Players can create their own registration
        allow create: if isAuthenticated() &&
          request.resource.data.userId == request.auth.uid;

        // Players can update their own (limited fields), organizers can update all
        allow update: if isAuthenticated() && (
          (resource.data.userId == request.auth.uid &&
           request.resource.data.userId == request.auth.uid) ||
          isEventOrganizer(eventId)
        );

        // Players can cancel their own, organizers can remove any
        allow delete: if isAuthenticated() && (
          resource.data.userId == request.auth.uid ||
          isEventOrganizer(eventId)
        );
      }

      // ----------------------------------------
      // Schedule subcollection
      // ----------------------------------------
      match /schedule/{itemId} {
        allow read: if isAuthenticated() && (
          get(/databases/$(database)/documents/events/$(eventId)).data.visibility == 'public' ||
          isEventOrganizer(eventId) ||
          isRegisteredForEvent(eventId)
        );

        allow create, update, delete: if isEventOrganizer(eventId);
      }

      // ----------------------------------------
      // Item Catalog subcollection
      // ----------------------------------------
      match /itemCatalog/{itemId} {
        allow read: if isAuthenticated() && (
          isEventOrganizer(eventId) ||
          isRegisteredForEvent(eventId)
        );

        allow create, update, delete: if isEventOrganizer(eventId);
      }

      // ----------------------------------------
      // Staff subcollection
      // ----------------------------------------
      match /staff/{staffId} {
        allow read: if isAuthenticated() && (
          isEventOrganizer(eventId) ||
          resource.data.userId == request.auth.uid
        );

        allow create, update, delete: if isEventOrganizer(eventId);
      }
    }

    // ============================================
    // TEMPLATES COLLECTION
    // ============================================

    match /templates/{templateId} {
      allow read: if isAuthenticated() && (
        // Creator can read
        resource.data.creatorId == request.auth.uid ||
        // Public templates
        resource.data.visibility == 'public' ||
        // Event-specific templates for registered users
        (resource.data.visibility == 'event' &&
         resource.data.eventId != null &&
         isRegisteredForEvent(resource.data.eventId))
      );

      allow create: if isAuthenticated() &&
        request.resource.data.creatorId == request.auth.uid;

      allow update, delete: if isAuthenticated() &&
        resource.data.creatorId == request.auth.uid;

      // Template subcollections
      match /attributeDefinitions/{defId} {
        allow read: if isAuthenticated();
        allow write: if isAuthenticated() &&
          get(/databases/$(database)/documents/templates/$(templateId)).data.creatorId == request.auth.uid;
      }

      match /abilityDefinitions/{defId} {
        allow read: if isAuthenticated();
        allow write: if isAuthenticated() &&
          get(/databases/$(database)/documents/templates/$(templateId)).data.creatorId == request.auth.uid;
      }
    }

    // ============================================
    // ITEM TRANSFERS COLLECTION
    // ============================================

    match /itemTransfers/{transferId} {
      // Sender and recipient can read
      allow read: if isAuthenticated() && (
        resource.data.fromUserId == request.auth.uid ||
        resource.data.toUserId == request.auth.uid
      );

      // Only Cloud Functions can write (for atomicity)
      allow write: if false;
    }

    // ============================================
    // PLOT THREADS COLLECTION (Phase 3)
    // ============================================

    match /plotThreads/{threadId} {
      allow read: if isAuthenticated() &&
        isEventOrganizer(resource.data.eventId);

      allow create: if isAuthenticated() &&
        isEventOrganizer(request.resource.data.eventId);

      allow update, delete: if isAuthenticated() &&
        isEventOrganizer(resource.data.eventId);

      match /secrets/{secretId} {
        allow read, write: if isAuthenticated() &&
          isEventOrganizer(get(/databases/$(database)/documents/plotThreads/$(threadId)).data.eventId);
      }

      match /scenes/{sceneId} {
        allow read, write: if isAuthenticated() &&
          isEventOrganizer(get(/databases/$(database)/documents/plotThreads/$(threadId)).data.eventId);
      }
    }

    // ============================================
    // CHANGELOG COLLECTION (Audit Trail)
    // ============================================

    match /characters/{characterId}/changelog/{entryId} {
      // Character owner and event organizers can read audit trail
      allow read: if isAuthenticated() && (
        get(/databases/$(database)/documents/characters/$(characterId)).data.ownerId == request.auth.uid ||
        isEventOrganizer(get(/databases/$(database)/documents/characters/$(characterId)).data.linkedEventId)
      );

      // Only Cloud Functions can write changelog entries
      // This ensures audit integrity - clients cannot forge entries
      allow write: if false;
    }

    // ============================================
    // CONFLICT LOGS COLLECTION (Sync Debugging)
    // ============================================

    match /conflictLogs/{logId} {
      // Only the user who experienced the conflict can read their logs
      allow read: if isAuthenticated() &&
        resource.data.userId == request.auth.uid;

      // Clients can create conflict logs for debugging
      allow create: if isAuthenticated() &&
        request.resource.data.userId == request.auth.uid &&
        hasRequiredString('entityType') &&
        hasRequiredString('conflictType') &&
        hasRequiredString('resolution') &&
        isServerTimestamp('occurredAt');

      // No updates or deletes - logs are immutable
      allow update, delete: if false;
    }

    // ============================================
    // RATE LIMIT TRACKING (Anti-Abuse)
    // ============================================

    match /rateLimits/{userId} {
      // Only Cloud Functions can read/write rate limit data
      // Clients should not be able to reset their own limits
      allow read, write: if false;
    }
  }
}
```

### 6.2 Firebase Storage Security Rules

```javascript
// storage.rules

rules_version = '2';
service firebase.storage {
  match /b/{bucket}/o {

    // Helper function to check auth
    function isAuthenticated() {
      return request.auth != null;
    }

    // ============================================
    // USER AVATARS
    // ============================================

    match /avatars/{userId}/{fileName} {
      // Users can read any avatar (for display)
      allow read: if isAuthenticated();

      // Users can only upload their own avatar
      allow write: if isAuthenticated() &&
                      request.auth.uid == userId &&
                      request.resource.size < 5 * 1024 * 1024 && // 5MB max
                      request.resource.contentType.matches('image/.*');
    }

    // ============================================
    // CHARACTER PORTRAITS
    // ============================================

    match /characters/{characterId}/{fileName} {
      // Read: anyone authenticated (for display in event lists)
      allow read: if isAuthenticated();

      // Write: only character owner (validated in client, enforced loosely here)
      // Full validation would require Firestore lookup which is not supported
      allow write: if isAuthenticated() &&
                      request.resource.size < 10 * 1024 * 1024 && // 10MB max
                      request.resource.contentType.matches('image/.*');
    }

    // ============================================
    // EVENT MEDIA
    // ============================================

    match /events/{eventId}/{allPaths=**} {
      // Read: registered users or organizers
      allow read: if isAuthenticated();

      // Write: only organizers (validated loosely)
      allow write: if isAuthenticated() &&
                      request.resource.size < 50 * 1024 * 1024; // 50MB max
    }

    // ============================================
    // EXPORTS (temporary downloads)
    // ============================================

    match /exports/{userId}/{fileName} {
      // Only owner can read/write
      allow read, write: if isAuthenticated() &&
                            request.auth.uid == userId;
    }
  }
}
```

### 6.3 Input Validation

All client-side input is validated before submission and validated again in security rules or Cloud Functions:

```dart
// core/utils/validators.dart

class Validators {
  static const int maxCharacterNameLength = 100;
  static const int maxDescriptionLength = 10000;
  static const int maxAttributeNameLength = 50;
  static const int maxAbilityDescriptionLength = 5000;
  static const int maxJournalEntryLength = 50000;

  static String? validateCharacterName(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Character name is required';
    }
    if (value.length > maxCharacterNameLength) {
      return 'Name must be less than $maxCharacterNameLength characters';
    }
    return null;
  }

  static String? validateDescription(String? value) {
    if (value != null && value.length > maxDescriptionLength) {
      return 'Description must be less than $maxDescriptionLength characters';
    }
    return null;
  }

  static String? validateAttributeName(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Attribute name is required';
    }
    if (value.length > maxAttributeNameLength) {
      return 'Name must be less than $maxAttributeNameLength characters';
    }
    return null;
  }

  static String? validateEmail(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Email is required';
    }
    final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
    if (!emailRegex.hasMatch(value)) {
      return 'Please enter a valid email address';
    }
    return null;
  }

  static String? validatePassword(String? value) {
    if (value == null || value.isEmpty) {
      return 'Password is required';
    }
    if (value.length < 8) {
      return 'Password must be at least 8 characters';
    }
    return null;
  }

  /// Sanitize user input to prevent XSS and injection
  static String sanitize(String input) {
    // Remove potentially dangerous characters
    return input
        .replaceAll(RegExp(r'<[^>]*>'), '') // Remove HTML tags
        .replaceAll(RegExp(r'javascript:', caseSensitive: false), '')
        .trim();
  }
}
```

### 6.4 Data Privacy Considerations

| Data Type | Sensitivity | Protection Measures |
|-----------|-------------|---------------------|
| Email addresses | Medium | Only visible to user and event organizers they register with |
| Character names | Low | Visible to organizers of linked events |
| Character content | Low | Only visible to owner and linked event organizers |
| Journal entries | Medium | Private by default; marked entries never visible to organizers |
| Event registrations | Low | Visible to organizers |
| Plot threads/secrets | High | Only visible to organizers |

### 6.5 Rate Limiting and Abuse Prevention

#### 6.5.1 Client-Side Rate Limiting

```dart
// core/services/rate_limiter.dart

class RateLimiter {
  final Map<String, List<DateTime>> _requestLog = {};

  /// Check if action is allowed under rate limit
  /// Returns true if allowed, false if rate limited
  bool checkLimit({
    required String action,
    required int maxRequests,
    required Duration window,
  }) {
    final now = DateTime.now();
    final windowStart = now.subtract(window);

    // Get or create request log for this action
    _requestLog[action] ??= [];
    final log = _requestLog[action]!;

    // Remove old entries outside the window
    log.removeWhere((time) => time.isBefore(windowStart));

    // Check if under limit
    if (log.length >= maxRequests) {
      return false;
    }

    // Record this request
    log.add(now);
    return true;
  }

  /// Wait until rate limit allows the action
  Future<void> waitForLimit({
    required String action,
    required int maxRequests,
    required Duration window,
  }) async {
    while (!checkLimit(action: action, maxRequests: maxRequests, window: window)) {
      await Future.delayed(const Duration(seconds: 1));
    }
  }
}

// Usage in repositories
class CharacterRepository {
  final RateLimiter _rateLimiter;

  static const _createLimit = (maxRequests: 10, window: Duration(minutes: 1));
  static const _updateLimit = (maxRequests: 60, window: Duration(minutes: 1));

  Future<void> createCharacter(Character character) async {
    if (!_rateLimiter.checkLimit(
      action: 'character.create',
      maxRequests: _createLimit.maxRequests,
      window: _createLimit.window,
    )) {
      throw RateLimitException('Too many characters created. Please wait.');
    }
    // ... proceed with creation
  }
}
```

#### 6.5.2 Server-Side Rate Limiting (Cloud Functions)

```typescript
// functions/src/middleware/rateLimiter.ts

import * as admin from 'firebase-admin';

interface RateLimitConfig {
  maxRequests: number;
  windowMs: number;
}

const RATE_LIMITS: Record<string, RateLimitConfig> = {
  'pushCharacterUpdate': { maxRequests: 30, windowMs: 60000 },
  'distributeItems': { maxRequests: 10, windowMs: 60000 },
  'claimPreGenCharacter': { maxRequests: 5, windowMs: 60000 },
  'sendStaffMessage': { maxRequests: 20, windowMs: 3600000 },
  'initiateItemTransfer': { maxRequests: 20, windowMs: 60000 },
};

export async function checkRateLimit(
  userId: string,
  action: string
): Promise<{ allowed: boolean; retryAfter?: number }> {
  const config = RATE_LIMITS[action];
  if (!config) return { allowed: true };

  const db = admin.firestore();
  const now = Date.now();
  const windowStart = now - config.windowMs;

  const rateLimitRef = db.collection('rateLimits').doc(userId);

  return db.runTransaction(async (transaction) => {
    const doc = await transaction.get(rateLimitRef);
    const data = doc.data() || {};
    const actionLog: number[] = data[action] || [];

    // Filter to requests within window
    const recentRequests = actionLog.filter((ts: number) => ts > windowStart);

    if (recentRequests.length >= config.maxRequests) {
      const oldestInWindow = Math.min(...recentRequests);
      const retryAfter = Math.ceil((oldestInWindow + config.windowMs - now) / 1000);
      return { allowed: false, retryAfter };
    }

    // Add current request
    recentRequests.push(now);
    transaction.set(rateLimitRef, { [action]: recentRequests }, { merge: true });

    return { allowed: true };
  });
}

// Usage in Cloud Function
export const pushCharacterUpdate = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'Must be authenticated');
  }

  const rateCheck = await checkRateLimit(context.auth.uid, 'pushCharacterUpdate');
  if (!rateCheck.allowed) {
    throw new functions.https.HttpsError(
      'resource-exhausted',
      `Rate limit exceeded. Try again in ${rateCheck.retryAfter} seconds.`,
      { retryAfter: rateCheck.retryAfter }
    );
  }

  // ... proceed with update
});
```

#### 6.5.3 Abuse Prevention Measures

| Attack Vector | Mitigation |
|---------------|------------|
| **Spam character creation** | Client + server rate limits; max 100 characters per user |
| **Large payload attacks** | Field length validation in security rules; max document size enforced |
| **Enumeration attacks** | No public user listings; event discovery requires authentication |
| **Unauthorized data access** | Security rules verify ownership/role for every read |
| **Privilege escalation** | Immutable fields (ownerId, createdAt); organizer actions via Cloud Functions |
| **Replay attacks** | Server timestamps for critical operations; transaction-based updates |
| **Denial of service** | Firebase built-in DDoS protection; per-user rate limits |

### 6.6 Security Testing

#### 6.6.1 Security Rules Unit Tests

```javascript
// firestore.rules.test.js (using @firebase/rules-unit-testing)

const { initializeTestEnvironment, assertSucceeds, assertFails } = require('@firebase/rules-unit-testing');
const fs = require('fs');

let testEnv;

beforeAll(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: 'rolekeeper-test',
    firestore: {
      rules: fs.readFileSync('firestore.rules', 'utf8'),
    },
  });
});

afterAll(async () => {
  await testEnv.cleanup();
});

beforeEach(async () => {
  await testEnv.clearFirestore();
});

describe('Characters Collection', () => {
  describe('Read Rules', () => {
    it('allows owner to read their own character', async () => {
      const userId = 'user123';
      const characterId = 'char456';

      // Setup: Create character owned by user
      await testEnv.withSecurityRulesDisabled(async (context) => {
        await context.firestore().collection('characters').doc(characterId).set({
          ownerId: userId,
          name: 'Test Character',
          isPreGenerated: false,
        });
      });

      // Test: User can read their character
      const userContext = testEnv.authenticatedContext(userId);
      await assertSucceeds(
        userContext.firestore().collection('characters').doc(characterId).get()
      );
    });

    it('denies non-owner from reading private character', async () => {
      const ownerId = 'user123';
      const attackerId = 'attacker456';
      const characterId = 'char789';

      await testEnv.withSecurityRulesDisabled(async (context) => {
        await context.firestore().collection('characters').doc(characterId).set({
          ownerId: ownerId,
          name: 'Private Character',
          isPreGenerated: false,
          linkedEventId: null,
        });
      });

      const attackerContext = testEnv.authenticatedContext(attackerId);
      await assertFails(
        attackerContext.firestore().collection('characters').doc(characterId).get()
      );
    });

    it('allows organizer to read character linked to their event', async () => {
      const organizerId = 'organizer123';
      const playerId = 'player456';
      const eventId = 'event789';
      const characterId = 'char101';

      await testEnv.withSecurityRulesDisabled(async (context) => {
        // Create event
        await context.firestore().collection('events').doc(eventId).set({
          organizerId: organizerId,
          coOrganizerIds: [],
          name: 'Test Event',
        });
        // Create character linked to event
        await context.firestore().collection('characters').doc(characterId).set({
          ownerId: playerId,
          name: 'Linked Character',
          linkedEventId: eventId,
          isPreGenerated: false,
        });
      });

      const organizerContext = testEnv.authenticatedContext(organizerId);
      await assertSucceeds(
        organizerContext.firestore().collection('characters').doc(characterId).get()
      );
    });
  });

  describe('Write Rules', () => {
    it('allows user to create character with themselves as owner', async () => {
      const userId = 'user123';
      const userContext = testEnv.authenticatedContext(userId);

      await assertSucceeds(
        userContext.firestore().collection('characters').add({
          ownerId: userId,
          name: 'New Character',
          isPreGenerated: false,
          createdAt: new Date(),
        })
      );
    });

    it('denies creating character with different owner', async () => {
      const userId = 'user123';
      const victimId = 'victim456';
      const userContext = testEnv.authenticatedContext(userId);

      await assertFails(
        userContext.firestore().collection('characters').add({
          ownerId: victimId, // Attempting to create as someone else
          name: 'Malicious Character',
          isPreGenerated: false,
        })
      );
    });

    it('denies changing ownerId on update', async () => {
      const originalOwner = 'user123';
      const attackerId = 'attacker456';
      const characterId = 'char789';

      await testEnv.withSecurityRulesDisabled(async (context) => {
        await context.firestore().collection('characters').doc(characterId).set({
          ownerId: originalOwner,
          name: 'Original Character',
          isPreGenerated: false,
        });
      });

      // Owner tries to transfer ownership (not allowed)
      const ownerContext = testEnv.authenticatedContext(originalOwner);
      await assertFails(
        ownerContext.firestore().collection('characters').doc(characterId).update({
          ownerId: attackerId,
        })
      );
    });

    it('enforces character name length limit', async () => {
      const userId = 'user123';
      const userContext = testEnv.authenticatedContext(userId);
      const longName = 'A'.repeat(101); // Over 100 char limit

      await assertFails(
        userContext.firestore().collection('characters').add({
          ownerId: userId,
          name: longName,
          isPreGenerated: false,
          createdAt: new Date(),
        })
      );
    });
  });
});

describe('Inventory Subcollection', () => {
  it('players can only add items with source=player', async () => {
    const userId = 'user123';
    const characterId = 'char456';

    await testEnv.withSecurityRulesDisabled(async (context) => {
      await context.firestore().collection('characters').doc(characterId).set({
        ownerId: userId,
        name: 'Test Character',
      });
    });

    const userContext = testEnv.authenticatedContext(userId);

    // Allowed: source = 'player'
    await assertSucceeds(
      userContext.firestore()
        .collection('characters').doc(characterId)
        .collection('inventory').add({
          name: 'Player Item',
          quantity: 1,
          source: 'player',
        })
    );

    // Denied: source = 'organizer' (only Cloud Functions can do this)
    await assertFails(
      userContext.firestore()
        .collection('characters').doc(characterId)
        .collection('inventory').add({
          name: 'Fake Organizer Item',
          quantity: 1,
          source: 'organizer',
        })
    );
  });
});

describe('Changelog Collection', () => {
  it('denies direct client writes to changelog', async () => {
    const userId = 'user123';
    const characterId = 'char456';

    await testEnv.withSecurityRulesDisabled(async (context) => {
      await context.firestore().collection('characters').doc(characterId).set({
        ownerId: userId,
        name: 'Test Character',
      });
    });

    const userContext = testEnv.authenticatedContext(userId);

    // Even owner cannot write directly to changelog
    await assertFails(
      userContext.firestore()
        .collection('characters').doc(characterId)
        .collection('changelog').add({
          operation: 'fake_update',
          performedBy: userId,
          timestamp: new Date(),
        })
    );
  });
});
```

#### 6.6.2 Security Testing Checklist

Before each release, verify:

**Authentication & Authorization**
- [ ] Unauthenticated users cannot read any data
- [ ] Users cannot read other users' private characters
- [ ] Users cannot modify other users' data
- [ ] Organizers can only access characters linked to their events
- [ ] Co-organizers have same access as primary organizer
- [ ] Staff cannot access organizer-only features

**Data Integrity**
- [ ] Users cannot forge ownerId on character creation
- [ ] Users cannot change ownerId on updates
- [ ] Users cannot set source='organizer' on inventory items
- [ ] Timestamp fields use server time, not client time
- [ ] Field length limits are enforced

**Privilege Escalation**
- [ ] Users cannot promote themselves to organizer role
- [ ] Users cannot add themselves to coOrganizerIds
- [ ] Users cannot claim already-claimed pre-gen characters
- [ ] Rate limits prevent brute-force operations

**Data Exposure**
- [ ] Journal entries are never visible to organizers
- [ ] Plot secrets are never visible to players
- [ ] User emails are only visible to relevant organizers
- [ ] Changelog entries are read-only to clients

---

## Section 7: Scalability and Cost Optimization

### 7.1 Firestore Collection Design for Scale

**Sharding Strategy**:
- Characters are naturally sharded by `ownerId`
- Events are naturally sharded by `organizerId`
- No hot partitions expected at target scale (100K users)

**Denormalization Decisions**:

| Denormalized Field | Location | Reason |
|-------------------|----------|--------|
| `userDisplayName` | Registration | Avoid user lookup for every registration display |
| `characterName` | Registration | Quick display in event dashboard |
| `eventName` | Journal entry | Offline display without event lookup |
| `quickStats` | Character | Avoid attribute subcollection query for list view |
| `keyAbilities` | Character | Quick view without abilities query |

### 7.2 Query Patterns and Indexing

**High-Frequency Queries**:

| Query | Frequency | Index Required |
|-------|-----------|----------------|
| User's characters (portfolio) | Very High | `(ownerId, isArchived, lastViewedAt)` |
| Character by game system | High | `(ownerId, gameSystem, lastViewedAt)` |
| Public upcoming events | Medium | `(visibility, status, startDate)` |
| Event registrations | Medium | Collection scope (no custom index) |
| User's registrations across events | Medium | Collection group `(userId, status)` |

### 7.3 Cost Optimization Strategies

**Read Optimization**:
1. **Local caching**: Isar database reduces Firestore reads significantly
2. **Pagination**: All list views use cursor-based pagination (limit 20-50)
3. **Selective sync**: Only sync characters viewed in last 7 days
4. **Denormalization**: Avoid joins by denormalizing frequently-accessed data

**Write Optimization**:
1. **Batch writes**: Group related writes (e.g., character + attributes) into batches
2. **Debounce**: Auto-save with 2-second debounce on text fields
3. **Queue coalescence**: Merge rapid edits to same field before sync

**Storage Optimization**:
1. **Image compression**: Compress portraits before upload (max 1024px)
2. **Storage quotas**: Limit per-user storage (100MB free tier)
3. **Cleanup jobs**: Scheduled function to remove orphaned files

**Estimated Monthly Costs** (at Year 1 targets):

| Service | Usage Estimate | Cost Estimate |
|---------|----------------|---------------|
| Firestore reads | 10M reads/month | $3.00 |
| Firestore writes | 2M writes/month | $3.60 |
| Firestore storage | 5GB | $0.90 |
| Cloud Functions | 100K invocations | $0.40 |
| Storage | 20GB | $0.50 |
| Auth | 5K MAU | Free |
| **Total** | | **~$8-10/month** |

---

## Section 8: Testing Strategy

### 8.1 Testing Pyramid and Coverage Requirements

```
                    /\
                   /  \
                  / E2E \          <- 10% - Critical user flows
                 /--------\
                /Integration\      <- 20% - Repository + API tests
               /--------------\
              /   Unit Tests    \  <- 70% - Models, services, validators
             /--------------------\
```

**Coverage Requirements**:

| Category | Minimum Coverage | Critical Paths |
|----------|------------------|----------------|
| Unit Tests | 80% line coverage | Models, validators, business logic |
| Integration Tests | 60% of repositories | All data access patterns |
| E2E Tests | 100% of critical flows | Auth, character CRUD, offline viewing |
| Security Rules | 100% of rules | All allow/deny conditions |

### 8.2 Testing Tools and Setup

```yaml
# pubspec.yaml - dev_dependencies
dev_dependencies:
  flutter_test:
    sdk: flutter
  mocktail: ^1.0.0               # Modern mocking library
  fake_cloud_firestore: ^2.4.0    # Firestore emulator
  firebase_auth_mocks: ^0.12.0    # Auth mocking
  isar_test: ^3.1.0               # Local database testing
  integration_test:
    sdk: flutter
  patrol: ^2.3.0                  # Advanced E2E testing
  golden_toolkit: ^0.15.0         # Visual regression testing
```

```dart
// test/test_utils/test_setup.dart

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:isar/isar.dart';
import 'package:mocktail/mocktail.dart';

/// Global test setup for consistent mocking
class TestSetup {
  static late FakeFirebaseFirestore fakeFirestore;
  static late MockFirebaseAuth mockAuth;
  static late Isar testIsar;
  static late MockConnectivityService mockConnectivity;

  static Future<void> initialize() async {
    fakeFirestore = FakeFirebaseFirestore();
    mockAuth = MockFirebaseAuth(
      signedIn: true,
      mockUser: MockUser(uid: 'test-user-123', email: 'test@example.com'),
    );

    // Initialize in-memory Isar for testing
    await Isar.initializeIsarCore(download: true);
    testIsar = await Isar.open(
      [LocalCharacterSchema, LocalAttributeSchema, /* ... */],
      directory: '',
      name: 'test_db_${DateTime.now().millisecondsSinceEpoch}',
    );

    mockConnectivity = MockConnectivityService();
  }

  static Future<void> tearDown() async {
    await testIsar.close(deleteFromDisk: true);
  }

  /// Create a test user with specific ID
  static MockUser createTestUser({
    String uid = 'test-user-123',
    String email = 'test@example.com',
    String displayName = 'Test User',
  }) {
    return MockUser(uid: uid, email: email, displayName: displayName);
  }

  /// Seed Firestore with test character
  static Future<String> seedCharacter({
    required String ownerId,
    String name = 'Test Character',
    String? linkedEventId,
  }) async {
    final docRef = await fakeFirestore.collection('characters').add({
      'ownerId': ownerId,
      'name': name,
      'linkedEventId': linkedEventId,
      'isPreGenerated': false,
      'isArchived': false,
      'createdAt': DateTime.now(),
      'updatedAt': DateTime.now(),
    });
    return docRef.id;
  }
}

// Mocks
class MockConnectivityService extends Mock implements ConnectivityService {}
class MockSyncService extends Mock implements SyncService {}
class MockCharacterRepository extends Mock implements CharacterRepository {}
```

### 8.3 Unit Tests

#### 8.3.1 Model Serialization Tests

```dart
// test/domain/models/character_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:rolekeeper/domain/models/character.dart';

void main() {
  group('Character Model', () {
    test('fromFirestore correctly deserializes document', () {
      final data = {
        'ownerId': 'user123',
        'name': 'Elara Nightwhisper',
        'pronouns': 'she/her',
        'description': 'A cunning diplomat',
        'gameSystem': 'Chronicles of Darkness',
        'linkedEventId': 'event456',
        'isPreGenerated': false,
        'preGenStatus': null,
        'createdAt': Timestamp.fromDate(DateTime(2025, 1, 15)),
        'updatedAt': Timestamp.fromDate(DateTime(2025, 12, 8)),
        'quickStats': {'Health': 7, 'Willpower': 5},
        'keyAbilities': ['Dominate', 'Presence'],
        'isArchived': false,
      };

      final character = Character.fromFirestore('char789', data);

      expect(character.id, 'char789');
      expect(character.ownerId, 'user123');
      expect(character.name, 'Elara Nightwhisper');
      expect(character.pronouns, 'she/her');
      expect(character.gameSystem, 'Chronicles of Darkness');
      expect(character.quickStats['Health'], 7);
      expect(character.keyAbilities, contains('Dominate'));
      expect(character.isArchived, false);
    });

    test('fromFirestore handles missing optional fields', () {
      final minimalData = {
        'ownerId': 'user123',
        'name': 'Minimal Character',
        'isPreGenerated': false,
        'isArchived': false,
        'createdAt': Timestamp.now(),
        'updatedAt': Timestamp.now(),
      };

      final character = Character.fromFirestore('char123', minimalData);

      expect(character.pronouns, isNull);
      expect(character.description, isNull);
      expect(character.linkedEventId, isNull);
      expect(character.quickStats, isEmpty);
    });

    test('toFirestore correctly serializes for create', () {
      final character = Character(
        id: 'char789',
        ownerId: 'user123',
        name: 'New Character',
        pronouns: 'they/them',
        isPreGenerated: false,
        isArchived: false,
      );

      final data = character.toFirestore();

      expect(data['ownerId'], 'user123');
      expect(data['name'], 'New Character');
      expect(data['pronouns'], 'they/them');
      expect(data['isPreGenerated'], false);
      expect(data.containsKey('createdAt'), true);
    });

    test('copyWith creates new instance with updated fields', () {
      final original = Character(
        id: 'char789',
        ownerId: 'user123',
        name: 'Original Name',
        isPreGenerated: false,
        isArchived: false,
      );

      final updated = original.copyWith(name: 'Updated Name');

      expect(original.name, 'Original Name'); // Original unchanged
      expect(updated.name, 'Updated Name');
      expect(updated.ownerId, 'user123'); // Other fields preserved
    });
  });
}
```

#### 8.3.2 Validator Tests

```dart
// test/core/utils/validators_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:rolekeeper/core/utils/validators.dart';

void main() {
  group('Validators', () {
    group('validateCharacterName', () {
      test('returns error for null input', () {
        expect(Validators.validateCharacterName(null), isNotNull);
      });

      test('returns error for empty string', () {
        expect(Validators.validateCharacterName(''), isNotNull);
        expect(Validators.validateCharacterName('   '), isNotNull);
      });

      test('returns error for name exceeding 100 characters', () {
        final longName = 'A' * 101;
        expect(Validators.validateCharacterName(longName), isNotNull);
      });

      test('returns null for valid name', () {
        expect(Validators.validateCharacterName('Elara'), isNull);
        expect(Validators.validateCharacterName('A' * 100), isNull);
      });
    });

    group('validateEmail', () {
      test('returns error for invalid email formats', () {
        expect(Validators.validateEmail('notanemail'), isNotNull);
        expect(Validators.validateEmail('missing@domain'), isNotNull);
        expect(Validators.validateEmail('@nodomain.com'), isNotNull);
      });

      test('returns null for valid emails', () {
        expect(Validators.validateEmail('user@example.com'), isNull);
        expect(Validators.validateEmail('user.name@sub.domain.com'), isNull);
      });
    });

    group('sanitize', () {
      test('removes HTML tags', () {
        expect(
          Validators.sanitize('<script>alert("xss")</script>Hello'),
          'Hello',
        );
        expect(
          Validators.sanitize('<b>Bold</b> text'),
          'Bold text',
        );
      });

      test('removes javascript: protocol', () {
        expect(
          Validators.sanitize('javascript:void(0)'),
          'void(0)',
        );
      });

      test('trims whitespace', () {
        expect(Validators.sanitize('  hello  '), 'hello');
      });
    });
  });
}
```

#### 8.3.3 Business Logic Tests

```dart
// test/domain/services/character_service_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:rolekeeper/domain/services/character_service.dart';

void main() {
  late CharacterService characterService;
  late MockCharacterRepository mockRepository;
  late MockSyncService mockSyncService;

  setUp(() {
    mockRepository = MockCharacterRepository();
    mockSyncService = MockSyncService();
    characterService = CharacterService(
      repository: mockRepository,
      syncService: mockSyncService,
    );
  });

  group('CharacterService', () {
    group('createCharacter', () {
      test('sets ownerId to current user', () async {
        when(() => mockRepository.create(any())).thenAnswer((_) async => 'char123');
        when(() => mockSyncService.queueChange(any())).thenAnswer((_) async {});

        final result = await characterService.createCharacter(
          name: 'New Character',
          currentUserId: 'user456',
        );

        verify(() => mockRepository.create(
          argThat(predicate<Character>((c) => c.ownerId == 'user456')),
        )).called(1);
      });

      test('validates name before creation', () async {
        expect(
          () => characterService.createCharacter(name: '', currentUserId: 'user123'),
          throwsA(isA<ValidationException>()),
        );
      });
    });

    group('archiveCharacter', () {
      test('sets isArchived flag instead of deleting', () async {
        final character = Character(
          id: 'char123',
          ownerId: 'user456',
          name: 'To Archive',
          isPreGenerated: false,
          isArchived: false,
        );

        when(() => mockRepository.getById(any())).thenAnswer((_) async => character);
        when(() => mockRepository.update(any())).thenAnswer((_) async {});

        await characterService.archiveCharacter('char123');

        verify(() => mockRepository.update(
          argThat(predicate<Character>((c) => c.isArchived == true)),
        )).called(1);
      });
    });
  });
}
```

### 8.4 Integration Tests

#### 8.4.1 Repository Tests with Mock Firestore

```dart
// test/data/repositories/character_repository_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:rolekeeper/data/repositories/character_repository_impl.dart';

void main() {
  late FakeFirebaseFirestore fakeFirestore;
  late CharacterRepositoryImpl repository;

  setUp(() {
    fakeFirestore = FakeFirebaseFirestore();
    repository = CharacterRepositoryImpl(firestore: fakeFirestore);
  });

  group('CharacterRepositoryImpl', () {
    test('create adds document and returns ID', () async {
      final character = Character(
        id: '', // Will be assigned by Firestore
        ownerId: 'user123',
        name: 'Test Character',
        isPreGenerated: false,
        isArchived: false,
      );

      final id = await repository.create(character);

      expect(id, isNotEmpty);

      // Verify document exists in Firestore
      final doc = await fakeFirestore.collection('characters').doc(id).get();
      expect(doc.exists, true);
      expect(doc.data()!['name'], 'Test Character');
    });

    test('getByOwner returns only user characters', () async {
      // Seed multiple characters
      await fakeFirestore.collection('characters').add({
        'ownerId': 'user123',
        'name': 'My Character',
        'isArchived': false,
      });
      await fakeFirestore.collection('characters').add({
        'ownerId': 'other-user',
        'name': 'Other Character',
        'isArchived': false,
      });

      final characters = await repository.getByOwner('user123');

      expect(characters.length, 1);
      expect(characters.first.name, 'My Character');
    });

    test('getByOwner excludes archived characters', () async {
      await fakeFirestore.collection('characters').add({
        'ownerId': 'user123',
        'name': 'Active Character',
        'isArchived': false,
      });
      await fakeFirestore.collection('characters').add({
        'ownerId': 'user123',
        'name': 'Archived Character',
        'isArchived': true,
      });

      final characters = await repository.getByOwner('user123');

      expect(characters.length, 1);
      expect(characters.first.name, 'Active Character');
    });

    test('update modifies existing document', () async {
      final docRef = await fakeFirestore.collection('characters').add({
        'ownerId': 'user123',
        'name': 'Original Name',
        'isArchived': false,
      });

      final character = Character(
        id: docRef.id,
        ownerId: 'user123',
        name: 'Updated Name',
        isPreGenerated: false,
        isArchived: false,
      );

      await repository.update(character);

      final doc = await docRef.get();
      expect(doc.data()!['name'], 'Updated Name');
    });

    test('watchCharacter emits updates in real-time', () async {
      final docRef = await fakeFirestore.collection('characters').add({
        'ownerId': 'user123',
        'name': 'Initial Name',
        'isArchived': false,
      });

      final stream = repository.watchCharacter(docRef.id);

      // Expect initial value and then update
      expectLater(
        stream.map((c) => c?.name),
        emitsInOrder(['Initial Name', 'Updated Name']),
      );

      // Trigger update
      await docRef.update({'name': 'Updated Name'});
    });
  });
}
```

#### 8.4.2 Sync Service Integration Tests

```dart
// test/domain/services/sync_service_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:isar/isar.dart';

void main() {
  late SyncService syncService;
  late FakeFirebaseFirestore fakeFirestore;
  late Isar testIsar;
  late MockConnectivityService mockConnectivity;

  setUp(() async {
    fakeFirestore = FakeFirebaseFirestore();
    testIsar = await Isar.open(
      [LocalCharacterSchema, SyncQueueSchema],
      directory: '',
      name: 'test_sync_${DateTime.now().millisecondsSinceEpoch}',
    );
    mockConnectivity = MockConnectivityService();

    syncService = SyncService(
      remoteDb: FirestoreDatasource(fakeFirestore),
      localDb: IsarDatasource(testIsar),
      connectivity: mockConnectivity,
    );
  });

  tearDown(() async {
    await testIsar.close(deleteFromDisk: true);
  });

  group('SyncService', () {
    test('queues changes when offline', () async {
      when(() => mockConnectivity.isOnline).thenReturn(false);

      await syncService.queueChange(
        entityType: 'character',
        entityId: 'char123',
        operation: 'update',
        payload: {'name': 'Updated'},
      );

      final queue = await testIsar.syncQueues.where().findAll();
      expect(queue.length, 1);
      expect(queue.first.status, SyncQueueStatus.pending);
    });

    test('processes queue when connectivity returns', () async {
      // Start offline
      when(() => mockConnectivity.isOnline).thenReturn(false);

      await syncService.queueChange(
        entityType: 'character',
        entityId: 'char123',
        operation: 'create',
        payload: {'ownerId': 'user123', 'name': 'Offline Character'},
      );

      // Go online
      when(() => mockConnectivity.isOnline).thenReturn(true);
      await syncService.syncAll();

      // Verify created in Firestore
      final doc = await fakeFirestore.collection('characters').doc('char123').get();
      expect(doc.exists, true);

      // Verify queue is empty
      final queue = await testIsar.syncQueues.where().findAll();
      expect(queue.where((q) => q.status == SyncQueueStatus.pending).length, 0);
    });

    test('detects conflicts when remote has newer data', () async {
      // Local has pending changes
      await testIsar.writeTxn(() async {
        await testIsar.localCharacters.put(LocalCharacter()
          ..firestoreId = 'char123'
          ..ownerId = 'user123'
          ..name = 'Local Version'
          ..syncStatus = SyncStatus.pending
          ..lastSyncedAt = DateTime(2025, 1, 1));
      });

      // Remote has newer version
      await fakeFirestore.collection('characters').doc('char123').set({
        'ownerId': 'user123',
        'name': 'Remote Version',
        'updatedAt': DateTime(2025, 1, 15),
      });

      when(() => mockConnectivity.isOnline).thenReturn(true);
      final result = await syncService.syncAll();

      expect(result.conflicts, greaterThan(0));
    });
  });
}
```

### 8.5 Offline Testing

#### 8.5.1 Offline Testing Methodology

Testing offline functionality requires simulating network conditions and verifying data integrity:

```dart
// test/offline/offline_test_utils.dart

class OfflineTestUtils {
  final MockConnectivityService mockConnectivity;
  final Isar testIsar;
  final FakeFirebaseFirestore fakeFirestore;

  OfflineTestUtils({
    required this.mockConnectivity,
    required this.testIsar,
    required this.fakeFirestore,
  });

  /// Simulate going offline
  void goOffline() {
    when(() => mockConnectivity.isOnline).thenReturn(false);
    when(() => mockConnectivity.status).thenReturn(ConnectivityStatus.offline);
  }

  /// Simulate coming back online
  void goOnline() {
    when(() => mockConnectivity.isOnline).thenReturn(true);
    when(() => mockConnectivity.status).thenReturn(ConnectivityStatus.online);
  }

  /// Seed local cache with character data
  Future<void> cacheCharacter(Character character) async {
    await testIsar.writeTxn(() async {
      await testIsar.localCharacters.put(LocalCharacter()
        ..firestoreId = character.id
        ..ownerId = character.ownerId
        ..name = character.name
        ..syncStatus = SyncStatus.synced
        ..lastSyncedAt = DateTime.now());
    });
  }

  /// Verify local cache contains expected data
  Future<void> verifyLocalCache({
    required String characterId,
    required String expectedName,
  }) async {
    final local = await testIsar.localCharacters
        .filter()
        .firestoreIdEqualTo(characterId)
        .findFirst();
    expect(local, isNotNull);
    expect(local!.name, expectedName);
  }
}
```

#### 8.5.2 Offline Scenario Tests

```dart
// test/offline/offline_scenarios_test.dart

void main() {
  late OfflineTestUtils offlineUtils;
  late CharacterRepository repository;

  setUp(() async {
    // Initialize test infrastructure
    offlineUtils = OfflineTestUtils(/* ... */);
    repository = CharacterRepositoryImpl(/* ... */);
  });

  group('Offline Scenarios', () {
    test('Scenario: View character while offline', () async {
      // Given: Character is cached locally
      final character = Character(
        id: 'char123',
        ownerId: 'user123',
        name: 'Cached Character',
        isPreGenerated: false,
        isArchived: false,
      );
      await offlineUtils.cacheCharacter(character);

      // When: Device goes offline
      offlineUtils.goOffline();

      // Then: Character is still accessible
      final retrieved = await repository.getById('char123');
      expect(retrieved, isNotNull);
      expect(retrieved!.name, 'Cached Character');
    });

    test('Scenario: Edit character offline then sync', () async {
      // Given: Character exists and is cached
      await offlineUtils.cacheCharacter(testCharacter);

      // When: User edits while offline
      offlineUtils.goOffline();
      await repository.update(testCharacter.copyWith(name: 'Edited Offline'));

      // Then: Change is queued
      final queue = await testIsar.syncQueues.where().findAll();
      expect(queue.any((q) => q.entityId == testCharacter.id), true);

      // When: Device comes back online
      offlineUtils.goOnline();
      await syncService.syncAll();

      // Then: Remote is updated
      final remoteDoc = await fakeFirestore
          .collection('characters')
          .doc(testCharacter.id)
          .get();
      expect(remoteDoc.data()!['name'], 'Edited Offline');
    });

    test('Scenario: Organizer update while player offline', () async {
      // Given: Player has cached character
      await offlineUtils.cacheCharacter(testCharacter);
      offlineUtils.goOffline();

      // When: Organizer updates character on server
      await fakeFirestore.collection('characters').doc(testCharacter.id).update({
        'name': 'Organizer Updated',
        'updatedAt': DateTime.now(),
      });

      // Then: Player still sees cached version
      final cached = await repository.getById(testCharacter.id);
      expect(cached!.name, 'Original Name');

      // When: Player comes back online and syncs
      offlineUtils.goOnline();
      await syncService.syncAll();

      // Then: Player sees organizer's update
      final synced = await repository.getById(testCharacter.id);
      expect(synced!.name, 'Organizer Updated');
    });

    test('Scenario: Conflict - player and organizer edit same field', () async {
      // Given: Character is cached
      await offlineUtils.cacheCharacter(testCharacter);

      // When: Player edits offline
      offlineUtils.goOffline();
      await repository.update(testCharacter.copyWith(
        description: 'Player description',
      ));

      // And: Organizer edits on server
      await fakeFirestore.collection('characters').doc(testCharacter.id).update({
        'description': 'Organizer description',
        'updatedAt': DateTime.now().add(Duration(seconds: 1)),
      });

      // When: Player comes online
      offlineUtils.goOnline();
      final result = await syncService.syncAll();

      // Then: Conflict is detected and resolved (remote wins for description)
      expect(result.conflicts, 1);

      final resolved = await repository.getById(testCharacter.id);
      expect(resolved!.description, 'Organizer description');

      // And: Player's change is backed up
      final backups = await testIsar.conflictBackups.where().findAll();
      expect(backups.any((b) => b.characterId == testCharacter.id), true);
    });

    test('Scenario: Create character offline', () async {
      offlineUtils.goOffline();

      // When: User creates character offline
      final newCharacter = Character(
        id: '', // Will be generated
        ownerId: 'user123',
        name: 'Offline Created',
        isPreGenerated: false,
        isArchived: false,
      );
      final localId = await repository.create(newCharacter);

      // Then: Character exists locally with temp ID
      expect(localId, startsWith('temp_'));
      await offlineUtils.verifyLocalCache(
        characterId: localId,
        expectedName: 'Offline Created',
      );

      // When: Device comes online
      offlineUtils.goOnline();
      await syncService.syncAll();

      // Then: Character synced with real Firestore ID
      final syncedChars = await repository.getByOwner('user123');
      expect(syncedChars.any((c) => c.name == 'Offline Created'), true);
    });
  });
}
```

### 8.6 Performance Testing

#### 8.6.1 Performance Benchmarks

Based on PRD requirements:

| Operation | Target | Measurement Method |
|-----------|--------|-------------------|
| App launch to portfolio | < 2s | `Stopwatch` from main() to first frame |
| Character sheet load (cached) | < 500ms | Time from tap to render complete |
| Character sheet load (network) | < 3s | Time from tap to render with fresh data |
| Search/filter response | < 200ms | Time from input to results displayed |
| Offline mode activation | Seamless | No visible delay or error |
| Sync completion (10 characters) | < 5s | Time from online to synced state |

#### 8.6.2 Performance Test Implementation

```dart
// test/performance/performance_benchmarks_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Performance Benchmarks', () {
    testWidgets('Character sheet loads from cache under 500ms', (tester) async {
      // Setup: Ensure character is cached
      await TestSetup.seedLocalCharacter('char123');

      await tester.pumpWidget(const RoleKeeperApp());
      await tester.pumpAndSettle();

      // Navigate to portfolio
      await tester.tap(find.byKey(Key('portfolio_tab')));
      await tester.pumpAndSettle();

      // Measure character sheet load time
      final stopwatch = Stopwatch()..start();

      await tester.tap(find.text('Test Character'));
      await tester.pumpAndSettle();

      stopwatch.stop();

      expect(
        stopwatch.elapsedMilliseconds,
        lessThan(500),
        reason: 'Character sheet should load from cache in under 500ms',
      );
    });

    testWidgets('Portfolio search responds under 200ms', (tester) async {
      // Setup: Create 50 characters for realistic search
      for (int i = 0; i < 50; i++) {
        await TestSetup.seedLocalCharacter('char_$i', name: 'Character $i');
      }

      await tester.pumpWidget(const RoleKeeperApp());
      await tester.pumpAndSettle();

      // Find search field
      final searchField = find.byKey(Key('portfolio_search'));

      final stopwatch = Stopwatch()..start();

      await tester.enterText(searchField, 'Character 25');
      await tester.pumpAndSettle();

      stopwatch.stop();

      expect(
        stopwatch.elapsedMilliseconds,
        lessThan(200),
        reason: 'Search should respond in under 200ms',
      );

      // Verify correct result
      expect(find.text('Character 25'), findsOneWidget);
    });

    testWidgets('Large inventory renders without jank', (tester) async {
      // Setup: Character with 100 items
      await TestSetup.seedCharacterWithItems('char123', itemCount: 100);

      await tester.pumpWidget(const RoleKeeperApp());
      await tester.pumpAndSettle();

      // Navigate to character inventory
      await tester.tap(find.text('Test Character'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(Key('inventory_tab')));

      // Measure scroll performance
      final binding = IntegrationTestWidgetsFlutterBinding.instance;
      await binding.traceAction(() async {
        // Scroll through entire list
        await tester.fling(
          find.byType(ListView),
          Offset(0, -5000),
          3000,
        );
        await tester.pumpAndSettle();
      }, reportKey: 'inventory_scroll');

      // Check for dropped frames in the trace
    });
  });
}
```

#### 8.6.3 Continuous Performance Monitoring

```dart
// lib/core/utils/performance_monitor.dart

class PerformanceMonitor {
  static final Map<String, List<int>> _measurements = {};

  /// Measure an async operation
  static Future<T> measure<T>(String operation, Future<T> Function() action) async {
    final stopwatch = Stopwatch()..start();
    try {
      return await action();
    } finally {
      stopwatch.stop();
      _record(operation, stopwatch.elapsedMilliseconds);
    }
  }

  /// Measure a sync operation
  static T measureSync<T>(String operation, T Function() action) {
    final stopwatch = Stopwatch()..start();
    try {
      return action();
    } finally {
      stopwatch.stop();
      _record(operation, stopwatch.elapsedMilliseconds);
    }
  }

  static void _record(String operation, int milliseconds) {
    _measurements.putIfAbsent(operation, () => []);
    _measurements[operation]!.add(milliseconds);

    // Log slow operations
    final threshold = _thresholds[operation] ?? 1000;
    if (milliseconds > threshold) {
      AppLogger.log(
        'Slow operation: $operation took ${milliseconds}ms (threshold: ${threshold}ms)',
        tag: 'PERF',
      );

      // Report to Firebase Performance
      FirebasePerformance.instance
          .newTrace(operation)
          .setMetric('duration_ms', milliseconds)
          .stop();
    }
  }

  static const Map<String, int> _thresholds = {
    'character_load_cached': 500,
    'character_load_network': 3000,
    'portfolio_load': 2000,
    'search_filter': 200,
    'sync_complete': 5000,
  };

  /// Get performance report for debugging
  static Map<String, Map<String, dynamic>> getReport() {
    return _measurements.map((operation, times) {
      times.sort();
      return MapEntry(operation, {
        'count': times.length,
        'min': times.first,
        'max': times.last,
        'median': times[times.length ~/ 2],
        'p95': times[(times.length * 0.95).floor()],
      });
    });
  }
}

// Usage in repository
class CharacterRepositoryImpl implements CharacterRepository {
  @override
  Future<Character?> getById(String id) {
    return PerformanceMonitor.measure(
      'character_load_${_isOnline ? "network" : "cached"}',
      () => _getByIdImpl(id),
    );
  }
}
```

### 8.7 E2E Tests

#### 8.7.1 Critical User Flow Tests

```dart
// integration_test/flows/character_creation_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:patrol/patrol.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  patrolTest('Complete character creation flow', ($) async {
    // Launch app
    await $.pumpWidget(const RoleKeeperApp());
    await $.pumpAndSettle();

    // Login
    await $.tap(find.byKey(Key('login_email_field')));
    await $.enterText(find.byKey(Key('login_email_field')), 'test@example.com');
    await $.enterText(find.byKey(Key('login_password_field')), 'testpass123');
    await $.tap(find.byKey(Key('login_button')));
    await $.pumpAndSettle();

    // Verify on portfolio
    expect(find.text('My Characters'), findsOneWidget);

    // Create new character
    await $.tap(find.byKey(Key('create_character_fab')));
    await $.pumpAndSettle();

    // Fill character details
    await $.enterText(find.byKey(Key('character_name_field')), 'Elara Nightwhisper');
    await $.enterText(find.byKey(Key('character_pronouns_field')), 'she/her');
    await $.enterText(
      find.byKey(Key('character_description_field')),
      'A cunning diplomat from the northern courts.',
    );

    // Add an attribute
    await $.tap(find.byKey(Key('add_attribute_button')));
    await $.enterText(find.byKey(Key('attribute_name_field')), 'Strength');
    await $.enterText(find.byKey(Key('attribute_value_field')), '3');
    await $.tap(find.byKey(Key('save_attribute_button')));

    // Save character
    await $.tap(find.byKey(Key('save_character_button')));
    await $.pumpAndSettle();

    // Verify back on portfolio with new character
    expect(find.text('Elara Nightwhisper'), findsOneWidget);

    // Verify character details
    await $.tap(find.text('Elara Nightwhisper'));
    await $.pumpAndSettle();

    expect(find.text('she/her'), findsOneWidget);
    expect(find.text('Strength'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
  });

  patrolTest('Offline character viewing flow', ($) async {
    // Setup: Login and ensure character is cached
    await $.pumpWidget(const RoleKeeperApp());
    await performLogin($);
    await $.tap(find.text('Test Character'));
    await $.pumpAndSettle();
    await $.native.pressBack();

    // Simulate offline mode
    await $.native.disableWifi();
    await $.native.disableCellular();
    await Future.delayed(Duration(seconds: 1));

    // Navigate to character
    await $.tap(find.text('Test Character'));
    await $.pumpAndSettle();

    // Verify character loads
    expect(find.text('Test Character'), findsOneWidget);

    // Verify offline indicator shown
    expect(find.byKey(Key('offline_banner')), findsOneWidget);

    // Verify can view all tabs
    await $.tap(find.byKey(Key('attributes_tab')));
    expect(find.text('Strength'), findsOneWidget);

    await $.tap(find.byKey(Key('inventory_tab')));
    expect(find.text('Sword'), findsOneWidget);

    // Cleanup
    await $.native.enableWifi();
  });

  patrolTest('Event registration flow', ($) async {
    await $.pumpWidget(const RoleKeeperApp());
    await performLogin($);

    // Navigate to events
    await $.tap(find.byKey(Key('events_tab')));
    await $.pumpAndSettle();

    // Find and tap an event
    await $.tap(find.text('Weekend LARP'));
    await $.pumpAndSettle();

    // Register
    await $.tap(find.byKey(Key('register_button')));
    await $.pumpAndSettle();

    // Select character
    await $.tap(find.text('Elara Nightwhisper'));
    await $.tap(find.byKey(Key('confirm_registration_button')));
    await $.pumpAndSettle();

    // Verify registration
    expect(find.text('Registered'), findsOneWidget);
    expect(find.text('Elara Nightwhisper'), findsOneWidget);
  });
}
```

### 8.8 Test Execution and CI Integration

```yaml
# .github/workflows/test.yml

name: Test Suite

on:
  push:
    branches: [main, develop]
  pull_request:
    branches: [main]

jobs:
  unit-tests:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with:
          flutter-version: '3.16.x'

      - name: Install dependencies
        run: flutter pub get

      - name: Run unit tests with coverage
        run: flutter test --coverage --coverage-path=coverage/lcov.info

      - name: Check coverage threshold
        run: |
          COVERAGE=$(lcov --summary coverage/lcov.info | grep "lines" | awk '{print $2}' | sed 's/%//')
          if (( $(echo "$COVERAGE < 80" | bc -l) )); then
            echo "Coverage $COVERAGE% is below 80% threshold"
            exit 1
          fi

      - name: Upload coverage
        uses: codecov/codecov-action@v3

  integration-tests:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2

      - name: Start Firebase emulators
        run: |
          npm install -g firebase-tools
          firebase emulators:start --only firestore,auth &
          sleep 10

      - name: Run integration tests
        run: flutter test integration_test/

  security-rules-tests:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: '20'

      - name: Install dependencies
        run: npm ci

      - name: Run security rules tests
        run: npm test -- --testPathPattern="firestore.rules.test.js"

  e2e-tests:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2

      - name: Run E2E tests on iOS Simulator
        run: |
          flutter test integration_test/flows/ \
            --device-id=iPhone-15 \
            --dart-define=ENV=test
```

---

## Section 9: Deployment and DevOps

### 9.1 Environment Configuration

**Firebase Projects**:
- `rolekeeper-dev` - Development
- `rolekeeper-staging` - Staging
- `rolekeeper-prod` - Production

**Flutter Environment Config**:

```dart
// lib/core/config/env_config.dart

enum Environment { dev, staging, prod }

class EnvConfig {
  static late Environment environment;

  static void initialize(Environment env) {
    environment = env;
  }

  static bool get isDev => environment == Environment.dev;
  static bool get isStaging => environment == Environment.staging;
  static bool get isProd => environment == Environment.prod;

  static String get firebaseProjectId {
    switch (environment) {
      case Environment.dev:
        return 'rolekeeper-dev';
      case Environment.staging:
        return 'rolekeeper-staging';
      case Environment.prod:
        return 'rolekeeper-prod';
    }
  }
}
```

**Build Flavors**:
```bash
# Development
flutter run --flavor dev --dart-define=ENV=dev

# Staging
flutter run --flavor staging --dart-define=ENV=staging

# Production
flutter run --flavor prod --dart-define=ENV=prod --release
```

### 9.2 CI/CD Pipeline (GitHub Actions)

```yaml
# .github/workflows/ci.yml

name: CI/CD

on:
  push:
    branches: [main, develop]
  pull_request:
    branches: [main]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: subosito/flutter-action@v2
        with:
          flutter-version: '3.16.x'
          channel: 'stable'

      - name: Install dependencies
        run: flutter pub get

      - name: Analyze code
        run: flutter analyze

      - name: Run tests
        run: flutter test --coverage

      - name: Upload coverage
        uses: codecov/codecov-action@v3
        with:
          file: coverage/lcov.info

  build-android:
    needs: test
    runs-on: ubuntu-latest
    if: github.ref == 'refs/heads/main'
    steps:
      - uses: actions/checkout@v4

      - uses: subosito/flutter-action@v2
        with:
          flutter-version: '3.16.x'

      - name: Build APK
        run: flutter build apk --flavor prod --dart-define=ENV=prod --release

      - name: Upload APK
        uses: actions/upload-artifact@v3
        with:
          name: app-release.apk
          path: build/app/outputs/flutter-apk/app-prod-release.apk

  build-ios:
    needs: test
    runs-on: macos-latest
    if: github.ref == 'refs/heads/main'
    steps:
      - uses: actions/checkout@v4

      - uses: subosito/flutter-action@v2
        with:
          flutter-version: '3.16.x'

      - name: Build iOS
        run: flutter build ios --flavor prod --dart-define=ENV=prod --release --no-codesign

      # Additional signing and upload steps...

  deploy-functions:
    needs: test
    runs-on: ubuntu-latest
    if: github.ref == 'refs/heads/main'
    steps:
      - uses: actions/checkout@v4

      - uses: actions/setup-node@v4
        with:
          node-version: '20'

      - name: Install Firebase CLI
        run: npm install -g firebase-tools

      - name: Deploy to Firebase
        env:
          FIREBASE_TOKEN: ${{ secrets.FIREBASE_TOKEN }}
        run: |
          cd functions
          npm ci
          npm run build
          firebase deploy --only functions --project rolekeeper-prod
```

### 9.3 Monitoring and Observability

**Firebase Services**:
- **Crashlytics**: Crash reporting for Flutter apps
- **Performance Monitoring**: App performance traces
- **Cloud Logging**: Function logs and errors
- **Analytics**: User behavior tracking

**Custom Monitoring**:

```dart
// core/utils/logger.dart

class AppLogger {
  static void log(String message, {String? tag, Map<String, dynamic>? data}) {
    if (kDebugMode) {
      print('[${tag ?? 'APP'}] $message');
      if (data != null) print(data);
    }

    // Send to Crashlytics for production
    FirebaseCrashlytics.instance.log('[$tag] $message');
  }

  static void error(dynamic error, StackTrace? stack, {String? tag}) {
    if (kDebugMode) {
      print('[ERROR ${tag ?? 'APP'}] $error');
      if (stack != null) print(stack);
    }

    FirebaseCrashlytics.instance.recordError(error, stack, reason: tag);
  }

  static void setUserContext(String userId) {
    FirebaseCrashlytics.instance.setUserIdentifier(userId);
  }
}
```

---

## Section 10: Migration and Versioning Strategy

### 10.1 Versioning Overview

RoleKeeper uses multiple versioning layers to ensure smooth updates and backward compatibility:

| Layer | Versioning Approach | Location |
|-------|---------------------|----------|
| App Version | Semantic versioning (1.0.0+build) | `pubspec.yaml` |
| Data Schema | Integer version per collection | Document field `_schemaVersion` |
| API Version | Function name suffix (v1, v2) | Cloud Functions |
| Local DB | Isar schema version | `Isar.open()` schema parameter |
| Feature Flags | Remote Config | Firebase Remote Config |

### 10.2 Document Schema Versioning

#### 10.2.1 Schema Version Field

Every document includes a `_schemaVersion` field to track its structure:

```typescript
// Firestore document structure
interface VersionedDocument {
  _schemaVersion: number;  // Current schema version
  _migratedAt?: Timestamp; // When last migrated
  _migratedFrom?: number;  // Previous version (for debugging)
  // ... rest of document fields
}
```

**Current Schema Versions**:

| Collection | Current Version | Last Updated |
|------------|-----------------|--------------|
| `users` | 1 | Initial |
| `characters` | 1 | Initial |
| `events` | 1 | Initial |
| `templates` | 1 | Initial |
| `itemTransfers` | 1 | Initial |

#### 10.2.2 Schema Version Registry

```typescript
// functions/src/migrations/schema_versions.ts

export const SCHEMA_VERSIONS = {
  users: {
    current: 1,
    migrations: {
      // 1 -> 2: Example future migration
      // 2: (doc) => migrateUserV1toV2(doc),
    },
  },
  characters: {
    current: 1,
    migrations: {},
  },
  events: {
    current: 1,
    migrations: {},
  },
} as const;

export function getCurrentVersion(collection: string): number {
  return SCHEMA_VERSIONS[collection]?.current ?? 1;
}
```

#### 10.2.3 Read-Time Migration (Lazy Migration)

Documents are migrated when read if they're outdated:

```dart
// lib/data/datasources/firestore_datasource.dart

class FirestoreDatasource {
  static const int CURRENT_CHARACTER_VERSION = 1;

  Future<Character?> getCharacter(String id) async {
    final doc = await _firestore.collection('characters').doc(id).get();
    if (!doc.exists) return null;

    final data = doc.data()!;
    final schemaVersion = data['_schemaVersion'] as int? ?? 1;

    // Migrate if needed
    if (schemaVersion < CURRENT_CHARACTER_VERSION) {
      final migrated = await _migrateCharacter(doc.id, data, schemaVersion);
      return Character.fromFirestore(doc.id, migrated);
    }

    return Character.fromFirestore(doc.id, data);
  }

  Future<Map<String, dynamic>> _migrateCharacter(
    String id,
    Map<String, dynamic> data,
    int fromVersion,
  ) async {
    var migrated = Map<String, dynamic>.from(data);

    // Apply migrations sequentially
    for (int v = fromVersion; v < CURRENT_CHARACTER_VERSION; v++) {
      migrated = _applyCharacterMigration(migrated, v, v + 1);
    }

    // Update document with migrated data
    migrated['_schemaVersion'] = CURRENT_CHARACTER_VERSION;
    migrated['_migratedAt'] = FieldValue.serverTimestamp();
    migrated['_migratedFrom'] = fromVersion;

    await _firestore.collection('characters').doc(id).update(migrated);

    return migrated;
  }

  Map<String, dynamic> _applyCharacterMigration(
    Map<String, dynamic> data,
    int from,
    int to,
  ) {
    switch ((from, to)) {
      // Migration: Add characterType (default 'player') for documents created before this field
      case (1, 2):
        if (!data.containsKey('characterType')) {
          data['characterType'] = 'player';
        }
        return data;
      default:
        return data;
    }
  }
}
```

#### 10.2.4 Batch Migration (Proactive Migration)

For large changes, use scheduled Cloud Functions:

```typescript
// functions/src/migrations/batch_migrate.ts

import * as functions from 'firebase-functions';
import * as admin from 'firebase-admin';

const BATCH_SIZE = 500;

export const migrateCharactersToV2 = functions
  .runWith({ timeoutSeconds: 540, memory: '1GB' })
  .pubsub.schedule('every 24 hours')
  .onRun(async (context) => {
    const db = admin.firestore();

    // Find documents needing migration
    const query = db.collection('characters')
      .where('_schemaVersion', '<', 2)
      .limit(BATCH_SIZE);

    const snapshot = await query.get();

    if (snapshot.empty) {
      console.log('No documents to migrate');
      return;
    }

    const batch = db.batch();
    let count = 0;

    for (const doc of snapshot.docs) {
      const data = doc.data();
      const migrated = migrateCharacterV1toV2(data);

      batch.update(doc.ref, {
        ...migrated,
        _schemaVersion: 2,
        _migratedAt: admin.firestore.FieldValue.serverTimestamp(),
        _migratedFrom: data._schemaVersion ?? 1,
      });

      count++;
    }

    await batch.commit();
    console.log(`Migrated ${count} characters to v2`);

    // If we hit the batch limit, there are more to process
    if (count === BATCH_SIZE) {
      console.log('More documents remain, will continue next run');
    }
  });

function migrateCharacterV1toV2(data: any): any {
  // Example migration: Split 'name' into 'firstName' and 'lastName'
  // const [firstName, ...rest] = (data.name || '').split(' ');
  // return {
  //   ...data,
  //   firstName,
  //   lastName: rest.join(' '),
  //   name: undefined, // Remove old field
  // };
  return data;
}
```

### 10.3 Local Database (Isar) Migration

#### 10.3.1 Isar Schema Versioning

Isar handles schema changes automatically for compatible changes. For breaking changes:

```dart
// lib/data/datasources/local/isar_migration.dart

class IsarMigration {
  static const int CURRENT_SCHEMA_VERSION = 1;

  static Future<Isar> openWithMigration() async {
    // Check existing version
    final prefs = await SharedPreferences.getInstance();
    final existingVersion = prefs.getInt('isar_schema_version') ?? 0;

    if (existingVersion < CURRENT_SCHEMA_VERSION) {
      // Perform migration before opening with new schema
      await _performMigration(existingVersion, CURRENT_SCHEMA_VERSION);
    }

    final isar = await Isar.open(
      [
        LocalCharacterSchema,
        LocalAttributeSchema,
        LocalAbilitySchema,
        LocalInventoryItemSchema,
        LocalJournalEntrySchema,
        SyncQueueSchema,
        ConflictLogSchema,
      ],
      directory: await getApplicationDocumentsDirectory().then((d) => d.path),
    );

    // Update stored version
    await prefs.setInt('isar_schema_version', CURRENT_SCHEMA_VERSION);

    return isar;
  }

  static Future<void> _performMigration(int from, int to) async {
    for (int v = from; v < to; v++) {
      await _migrate(v, v + 1);
    }
  }

  static Future<void> _migrate(int from, int to) async {
    switch ((from, to)) {
      case (0, 1):
        // Initial schema, no migration needed
        break;
      // case (1, 2):
      //   await _migrateV1toV2();
      //   break;
    }
  }

  // Example migration: Export data, delete DB, reimport with new schema
  static Future<void> _migrateV1toV2() async {
    // 1. Open old database
    final oldIsar = await Isar.open(
      [LocalCharacterSchemaV1], // Old schema
      directory: await getApplicationDocumentsDirectory().then((d) => d.path),
      name: 'old_db',
    );

    // 2. Export all data
    final oldCharacters = await oldIsar.localCharactersV1.where().findAll();
    final exportedData = oldCharacters.map((c) => c.toExportMap()).toList();

    // 3. Close and delete old database
    await oldIsar.close(deleteFromDisk: true);

    // 4. Open new database with new schema
    final newIsar = await Isar.open(
      [LocalCharacterSchema], // New schema
      directory: await getApplicationDocumentsDirectory().then((d) => d.path),
    );

    // 5. Import with transformation
    await newIsar.writeTxn(() async {
      for (final data in exportedData) {
        final newChar = LocalCharacter.fromExportMap(data);
        await newIsar.localCharacters.put(newChar);
      }
    });

    await newIsar.close();
  }
}
```

### 10.4 Cloud Functions API Versioning

#### 10.4.1 Versioned Function Names

```typescript
// functions/src/index.ts

// Version 1 APIs (current)
export { pushCharacterUpdate as pushCharacterUpdateV1 } from './v1/character';
export { claimPreGenCharacter as claimPreGenCharacterV1 } from './v1/pregen';
export { initiateItemTransfer as initiateItemTransferV1 } from './v1/transfer';

// Version 2 APIs (when needed)
// export { pushCharacterUpdate as pushCharacterUpdateV2 } from './v2/character';

// Deprecated aliases (for backward compatibility)
// Remove after all clients updated
export { pushCharacterUpdate } from './v1/character'; // Will be removed in v2.0
```

#### 10.4.2 Client Version Checking

```typescript
// functions/src/middleware/version_check.ts

interface VersionedRequest {
  clientVersion?: string;
  clientPlatform?: string;
}

const MIN_SUPPORTED_VERSIONS = {
  ios: '1.0.0',
  android: '1.0.0',
  web: '1.0.0',
};

const DEPRECATED_VERSIONS = {
  ios: '1.2.0',      // Versions below this show upgrade prompt
  android: '1.2.0',
  web: '1.2.0',
};

export function checkClientVersion(
  data: VersionedRequest,
  context: functions.https.CallableContext
): { supported: boolean; deprecated: boolean; message?: string } {
  const { clientVersion, clientPlatform } = data;

  if (!clientVersion || !clientPlatform) {
    // Legacy client without version info - allow but log
    console.warn('Client request without version info', { uid: context.auth?.uid });
    return { supported: true, deprecated: true };
  }

  const minVersion = MIN_SUPPORTED_VERSIONS[clientPlatform];
  const deprecatedVersion = DEPRECATED_VERSIONS[clientPlatform];

  if (!minVersion) {
    return { supported: false, deprecated: false, message: 'Unknown platform' };
  }

  if (compareVersions(clientVersion, minVersion) < 0) {
    return {
      supported: false,
      deprecated: false,
      message: `Please update to version ${minVersion} or later`,
    };
  }

  if (compareVersions(clientVersion, deprecatedVersion) < 0) {
    return {
      supported: true,
      deprecated: true,
      message: 'This app version will stop working soon. Please update.',
    };
  }

  return { supported: true, deprecated: false };
}

function compareVersions(a: string, b: string): number {
  const partsA = a.split('.').map(Number);
  const partsB = b.split('.').map(Number);

  for (let i = 0; i < 3; i++) {
    if ((partsA[i] || 0) < (partsB[i] || 0)) return -1;
    if ((partsA[i] || 0) > (partsB[i] || 0)) return 1;
  }
  return 0;
}
```

### 10.5 Feature Flags

#### 10.5.1 Firebase Remote Config Setup

```dart
// lib/core/config/feature_flags.dart

class FeatureFlags {
  static final FirebaseRemoteConfig _remoteConfig = FirebaseRemoteConfig.instance;

  // Feature flag keys
  static const String _itemTransferEnabled = 'feature_item_transfer_enabled';
  static const String _plotManagementEnabled = 'feature_plot_management_enabled';
  static const String _staffMessagingEnabled = 'feature_staff_messaging_enabled';
  static const String _newCharacterEditorEnabled = 'feature_new_character_editor';
  static const String _offlineEditingEnabled = 'feature_offline_editing';

  // Rollout percentage flags
  static const String _newSyncEngineRollout = 'rollout_new_sync_engine_percent';

  static Future<void> initialize() async {
    await _remoteConfig.setConfigSettings(RemoteConfigSettings(
      fetchTimeout: const Duration(minutes: 1),
      minimumFetchInterval: const Duration(hours: 1),
    ));

    // Set defaults (used when offline or before first fetch)
    await _remoteConfig.setDefaults({
      _itemTransferEnabled: false,
      _plotManagementEnabled: false,
      _staffMessagingEnabled: false,
      _newCharacterEditorEnabled: false,
      _offlineEditingEnabled: true,
      _newSyncEngineRollout: 0,
    });

    // Fetch and activate
    try {
      await _remoteConfig.fetchAndActivate();
    } catch (e) {
      // Use defaults if fetch fails
      AppLogger.log('Remote config fetch failed, using defaults', tag: 'FLAGS');
    }
  }

  // Feature getters
  static bool get isItemTransferEnabled =>
      _remoteConfig.getBool(_itemTransferEnabled);

  static bool get isPlotManagementEnabled =>
      _remoteConfig.getBool(_plotManagementEnabled);

  static bool get isStaffMessagingEnabled =>
      _remoteConfig.getBool(_staffMessagingEnabled);

  static bool get isNewCharacterEditorEnabled =>
      _remoteConfig.getBool(_newCharacterEditorEnabled);

  static bool get isOfflineEditingEnabled =>
      _remoteConfig.getBool(_offlineEditingEnabled);

  // Percentage rollout check
  static bool get isNewSyncEngineEnabled {
    final rolloutPercent = _remoteConfig.getInt(_newSyncEngineRollout);
    return _isUserInRollout(rolloutPercent);
  }

  /// Deterministic rollout based on user ID
  static bool _isUserInRollout(int percent) {
    if (percent >= 100) return true;
    if (percent <= 0) return false;

    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) return false;

    // Hash user ID to get consistent bucket assignment
    final hash = userId.hashCode.abs();
    final bucket = hash % 100;
    return bucket < percent;
  }

  /// Listen for real-time config updates
  static Stream<void> get onConfigUpdated {
    return _remoteConfig.onConfigUpdated.asyncMap((event) async {
      await _remoteConfig.activate();
    });
  }
}
```

#### 10.5.2 Using Feature Flags in UI

```dart
// lib/presentation/screens/character/character_detail_screen.dart

class CharacterDetailScreen extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: Column(
        children: [
          // Always shown
          CharacterHeader(character: character),

          // Feature-flagged tab
          if (FeatureFlags.isItemTransferEnabled)
            TransferItemButton(character: character),

          // A/B test different editors
          if (FeatureFlags.isNewCharacterEditorEnabled)
            NewCharacterEditor(character: character)
          else
            LegacyCharacterEditor(character: character),
        ],
      ),
    );
  }
}
```

#### 10.5.3 Feature Flag Configuration (Firebase Console)

```json
// Remote Config parameters in Firebase Console
{
  "feature_item_transfer_enabled": {
    "defaultValue": { "value": "false" },
    "conditionalValues": {
      "Beta Testers": { "value": "true" },
      "Internal": { "value": "true" }
    }
  },
  "feature_plot_management_enabled": {
    "defaultValue": { "value": "false" },
    "conditionalValues": {
      "Phase 3 Rollout": { "value": "true" }
    }
  },
  "rollout_new_sync_engine_percent": {
    "defaultValue": { "value": "0" },
    "conditionalValues": {
      "Canary": { "value": "5" },
      "Beta": { "value": "25" },
      "General Availability": { "value": "100" }
    }
  }
}
```

### 10.6 Backward Compatibility Strategies

#### 10.6.1 Model Compatibility Layer

```dart
// lib/domain/models/character.dart

class Character {
  // Current fields
  final String id;
  final String ownerId;
  final String name;
  final String? firstName;  // New in v2
  final String? lastName;   // New in v2

  // Factory that handles old and new formats
  factory Character.fromFirestore(String id, Map<String, dynamic> data) {
    final schemaVersion = data['_schemaVersion'] as int? ?? 1;

    switch (schemaVersion) {
      case 1:
        return Character._fromV1(id, data);
      case 2:
        return Character._fromV2(id, data);
      default:
        // Unknown future version - try to parse what we can
        return Character._fromLatest(id, data);
    }
  }

  factory Character._fromV1(String id, Map<String, dynamic> data) {
    // V1 only had 'name', no firstName/lastName
    final fullName = data['name'] as String? ?? '';
    final parts = fullName.split(' ');

    return Character(
      id: id,
      ownerId: data['ownerId'] as String,
      name: fullName,
      firstName: parts.isNotEmpty ? parts.first : null,
      lastName: parts.length > 1 ? parts.sublist(1).join(' ') : null,
      // ... other fields
    );
  }

  factory Character._fromV2(String id, Map<String, dynamic> data) {
    return Character(
      id: id,
      ownerId: data['ownerId'] as String,
      name: data['name'] as String? ?? '${data['firstName']} ${data['lastName']}',
      firstName: data['firstName'] as String?,
      lastName: data['lastName'] as String?,
      // ... other fields
    );
  }

  // Serialize to current version
  Map<String, dynamic> toFirestore() {
    return {
      'ownerId': ownerId,
      'name': name,  // Keep for backward compat with old clients
      'firstName': firstName,
      'lastName': lastName,
      '_schemaVersion': 2,
      // ... other fields
    };
  }
}
```

#### 10.6.2 Deprecation Timeline

| Version | Status | Support End Date | Notes |
|---------|--------|------------------|-------|
| 1.0.x | Deprecated | 2026-06-01 | Show upgrade prompt |
| 1.1.x | Deprecated | 2026-09-01 | Show upgrade prompt |
| 1.2.x | Supported | - | Current minimum |
| 1.3.x | Current | - | Latest release |

### 10.7 Rollback Strategy

#### 10.7.1 Client Rollback

```dart
// Emergency rollback via Remote Config
// Set 'force_downgrade_version' to trigger

class AppVersionChecker {
  static Future<void> checkForForcedDowngrade() async {
    final forceVersion = FeatureFlags.getString('force_downgrade_version');
    if (forceVersion.isEmpty) return;

    final currentVersion = await PackageInfo.fromPlatform()
        .then((p) => p.version);

    if (compareVersions(currentVersion, forceVersion) > 0) {
      // Current version is newer than forced version
      // Show message directing to older version
      showDialog(
        context: navigatorKey.currentContext!,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
          title: Text('Update Required'),
          content: Text(
            'Please reinstall version $forceVersion from the app store. '
            'A critical issue was found in this version.',
          ),
        ),
      );
    }
  }
}
```

#### 10.7.2 Server-Side Rollback

```typescript
// functions/src/migrations/rollback.ts

export const rollbackCharacterSchema = functions.https.onCall(
  async (data, context) => {
    // Admin only
    if (!await isAdmin(context.auth?.uid)) {
      throw new functions.https.HttpsError('permission-denied', 'Admin only');
    }

    const { fromVersion, toVersion, dryRun } = data;
    const db = admin.firestore();

    const query = db.collection('characters')
      .where('_schemaVersion', '==', fromVersion)
      .limit(500);

    const snapshot = await query.get();
    const rollbackResults: any[] = [];

    for (const doc of snapshot.docs) {
      const original = doc.data();
      const rolledBack = rollbackCharacter(original, fromVersion, toVersion);

      rollbackResults.push({
        id: doc.id,
        before: original,
        after: rolledBack,
      });

      if (!dryRun) {
        await doc.ref.update({
          ...rolledBack,
          _schemaVersion: toVersion,
          _rolledBackAt: admin.firestore.FieldValue.serverTimestamp(),
          _rolledBackFrom: fromVersion,
        });
      }
    }

    return {
      count: rollbackResults.length,
      dryRun,
      samples: rollbackResults.slice(0, 5),
    };
  }
);
```

### 10.8 Migration Runbook

#### Pre-Migration Checklist

- [ ] Schema change documented in `CHANGELOG.md`
- [ ] Migration function written and tested locally
- [ ] Rollback function written and tested
- [ ] Backward compatibility verified (old clients can read new format)
- [ ] Forward compatibility verified (new clients can read old format)
- [ ] Security rules updated for new fields (if any)
- [ ] Feature flag created for gradual rollout
- [ ] Monitoring alerts configured for migration errors

#### Migration Steps

1. **Deploy migration Cloud Function** (disabled)
2. **Deploy new client** with backward-compatible model parsing
3. **Enable lazy migration** in client (migrates on read)
4. **Monitor** error rates and migration progress
5. **Enable batch migration** function (runs nightly)
6. **Wait** for migration to complete (> 95% documents)
7. **Remove** backward compatibility code in next release
8. **Archive** migration functions

#### Rollback Steps

1. **Disable** batch migration function
2. **Deploy** rollback function
3. **Run** rollback in dry-run mode, verify output
4. **Run** rollback for real
5. **Deploy** previous client version (via app stores)
6. **Post-mortem** and fix issues

### 10.9 Data Export Capability

```typescript
// Cloud Function for GDPR data export
export const exportUserData = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'Must be authenticated');
  }

  const userId = context.auth.uid;
  const db = admin.firestore();

  // Gather all user data
  const userData = {
    profile: await db.collection('users').doc(userId).get().then(d => d.data()),
    characters: await db.collection('characters')
      .where('ownerId', '==', userId)
      .get()
      .then(snap => snap.docs.map(d => d.data())),
    // ... gather all related data
  };

  // Upload to storage for download
  const bucket = admin.storage().bucket();
  const file = bucket.file(`exports/${userId}/data-export-${Date.now()}.json`);

  await file.save(JSON.stringify(userData, null, 2), {
    contentType: 'application/json',
  });

  // Generate signed URL (valid 24 hours)
  const [url] = await file.getSignedUrl({
    action: 'read',
    expires: Date.now() + 24 * 60 * 60 * 1000,
  });

  return { downloadUrl: url };
});
```

### 10.3 Future Architecture Considerations

**If Scale Exceeds Firebase Limits**:
1. Consider moving to Cloud SQL for relational data (events, registrations)
2. Keep Firestore for document-heavy data (characters, plot threads)
3. Add Redis cache layer for hot data

**If Real-Time Requirements Increase**:
1. Consider Firebase Realtime Database for high-frequency updates
2. Evaluate WebSocket alternatives for specific features

**If Search Requirements Emerge**:
1. Integrate Algolia or Elasticsearch for full-text search
2. Sync via Cloud Functions triggers

---

## Appendix A: Package Dependencies

```yaml
# pubspec.yaml

name: rolekeeper
description: Rule-agnostic character and event management for LARP

version: 1.0.0+1

environment:
  sdk: '>=3.2.0 <4.0.0'

dependencies:
  flutter:
    sdk: flutter

  # Firebase
  firebase_core: ^2.24.0
  firebase_auth: ^4.16.0
  cloud_firestore: ^4.14.0
  firebase_storage: ^11.6.0
  cloud_functions: ^4.6.0
  firebase_crashlytics: ^3.4.8
  firebase_analytics: ^10.7.4
  firebase_messaging: ^14.7.9

  # State Management
  flutter_riverpod: ^2.4.9
  riverpod_annotation: ^2.3.3

  # Navigation
  go_router: ^13.0.0

  # Local Storage
  isar: ^3.1.0+1
  isar_flutter_libs: ^3.1.0+1
  flutter_secure_storage: ^9.0.0

  # Networking
  dio: ^5.4.0
  connectivity_plus: ^5.0.2

  # UI
  flutter_svg: ^2.0.9
  cached_network_image: ^3.3.1
  shimmer: ^3.0.0

  # Auth
  google_sign_in: ^6.2.1
  sign_in_with_apple: ^5.0.0

  # Utils
  uuid: ^4.2.2
  intl: ^0.18.1
  collection: ^1.18.0
  equatable: ^2.0.5
  freezed_annotation: ^2.4.1
  json_annotation: ^4.8.1

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^3.0.0

  # Code Generation
  build_runner: ^2.4.8
  riverpod_generator: ^2.3.9
  freezed: ^2.4.6
  json_serializable: ^6.7.1
  isar_generator: ^3.1.0+1

  # Testing
  mocktail: ^1.0.1
  fake_cloud_firestore: ^2.4.6
  firebase_auth_mocks: ^0.13.0

  integration_test:
    sdk: flutter

flutter:
  uses-material-design: true

  assets:
    - assets/images/
    - assets/icons/
```

---

## Appendix B: Team Handoff Checklist

### For Flutter Engineers
- [ ] Review Section 2 (Flutter Application Architecture)
- [ ] Review data models in Section 1.2
- [ ] Review offline architecture in Section 3
- [ ] Review state management patterns in Section 2.2
- [ ] Set up development environment with Firebase emulators

### For Backend/Firebase Engineers
- [ ] Review Section 4 (Cloud Functions specifications)
- [ ] Review Firestore collection structure in Section 1.1
- [ ] Review security rules in Section 6.1
- [ ] Set up Firebase projects for dev/staging/prod
- [ ] Deploy initial Firestore indexes

### For QA Engineers
- [ ] Review testing strategy in Section 8
- [ ] Identify critical user flows for E2E testing
- [ ] Plan offline/online transition testing
- [ ] Plan sync conflict testing scenarios

### For Security Analysts
- [ ] Review security rules in Section 6
- [ ] Review authentication flow in Section 5
- [ ] Assess data privacy considerations
- [ ] Plan security rule testing

### For DevOps Engineers
- [ ] Review deployment section (Section 9)
- [ ] Set up CI/CD pipelines
- [ ] Configure Firebase projects and environments
- [ ] Set up monitoring and alerting

---

*Document prepared by System Architect Agent*
*Based on Product Requirements Document v1.0*
*Ready for implementation by engineering teams*