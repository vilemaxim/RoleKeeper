# RoleKeeper - API Contracts

**Version**: 1.0
**Date**: January 31, 2026
**Status**: Technical Specification
**Based On**: Product Requirements Document v1.0, System Architecture v1.0

---

## Overview

RoleKeeper uses a hybrid data access pattern:

1. **Direct Firestore Access** — Client reads/writes with security rules enforcement
2. **Cloud Functions** — Server-side logic for privileged, atomic, or complex operations

This document defines the contracts for Cloud Functions and documents the expected Firestore access patterns.

---

## Table of Contents

1. [Authentication Context](#1-authentication-context)
2. [Error Handling Standards](#2-error-handling-standards)
3. [Direct Firestore Access Patterns](#3-direct-firestore-access-patterns)
4. [Cloud Functions - MVP](#4-cloud-functions---mvp)
5. [Cloud Functions - Phase 2](#5-cloud-functions---phase-2)
6. [Cloud Functions - Phase 3](#6-cloud-functions---phase-3)
7. [Rate Limiting & Quotas](#7-rate-limiting--quotas)

---

## 1. Authentication Context

All Cloud Functions receive an authentication context from Firebase Auth.

```typescript
interface AuthContext {
  uid: string;                    // Firebase Auth UID
  email: string | null;
  emailVerified: boolean;
  displayName: string | null;
}
```

### Role Determination

Roles are determined per-request based on data relationships, not stored user flags:

| Role | Determination |
|------|---------------|
| **Owner** | `resource.ownerId === auth.uid` |
| **Organizer** | `event.organizerId === auth.uid OR auth.uid IN event.coOrganizerIds` |
| **Staff** | `EXISTS events/{eventId}/staff/{doc} WHERE doc.userId === auth.uid` |
| **Registered Player** | `EXISTS events/{eventId}/registrations/{doc} WHERE doc.userId === auth.uid` |

---

## 2. Error Handling Standards

### Error Response Shape

All Cloud Functions return errors in a consistent format:

```typescript
interface ErrorResponse {
  success: false;
  error: {
    code: string;                 // Machine-readable error code
    message: string;              // Human-readable message
    details?: Record<string, any>; // Additional context
  };
}
```

### Global Error Codes

These error codes can be returned by any function:

| Code | HTTP Status | Description |
|------|-------------|-------------|
| `UNAUTHENTICATED` | 401 | No valid authentication token |
| `PERMISSION_DENIED` | 403 | User lacks required role/permission |
| `NOT_FOUND` | 404 | Requested resource does not exist |
| `INVALID_ARGUMENT` | 400 | Request payload failed validation |
| `FAILED_PRECONDITION` | 400 | Operation invalid in current state |
| `ALREADY_EXISTS` | 409 | Resource already exists (conflict) |
| `RESOURCE_EXHAUSTED` | 429 | Rate limit exceeded |
| `INTERNAL` | 500 | Unexpected server error |

### Function-Specific Error Codes

Each function defines additional codes prefixed with the function context (e.g., `TRANSFER_*`, `CLAIM_*`).

---

## 3. Direct Firestore Access Patterns

These operations are handled client-side with Firestore security rules enforcement.

### 3.1 Character Operations (MVP)

| Operation | Collection | Auth Requirement | Notes |
|-----------|------------|------------------|-------|
| Create character | `characters` | Authenticated | `ownerId` must equal `auth.uid` |
| Read own characters | `characters` | Authenticated | Filter: `ownerId == auth.uid` |
| Update own character | `characters` | Owner | Cannot modify `ownerId` |
| Delete (archive) own character | `characters` | Owner | Soft delete via `isArchived` |
| CRUD attributes | `characters/{id}/attributes` | Character Owner | |
| CRUD abilities | `characters/{id}/abilities` | Character Owner | `abilityType`: ability, advantage, disadvantage |
| CRUD inventory (own items) | `characters/{id}/inventory` | Character Owner | Source must be `player` |
| CRUD currencies | `characters/{id}/currencies` | Character Owner | Gold, Silver, XP, etc. |
| CRUD relationships | `characters/{id}/relationships` | Character Owner | Links to other characters |
| CRUD journal entries | `characters/{id}/journal` | Character Owner | |

### 3.2 Event Operations (Phase 2)

| Operation | Collection | Auth Requirement | Notes |
|-----------|------------|------------------|-------|
| Create event | `events` | Authenticated | `organizerId` set to `auth.uid` |
| Read public events | `events` | Authenticated | Filter: `visibility == 'public'` |
| Read own organized events | `events` | Authenticated | Filter: `organizerId == auth.uid` |
| Update event | `events` | Organizer | |
| Create registration | `events/{id}/registrations` | Authenticated | `userId` must equal `auth.uid` |
| Read own registration | `events/{id}/registrations` | Authenticated | Filter: `userId == auth.uid` |
| Read all registrations | `events/{id}/registrations` | Organizer | |
| CRUD schedule items | `events/{id}/schedule` | Organizer | |
| CRUD item catalog | `events/{id}/itemCatalog` | Organizer | |

### 3.3 Template Operations (Phase 2)

| Operation | Collection | Auth Requirement | Notes |
|-----------|------------|------------------|-------|
| Create template | `templates` | Authenticated | `creatorId` set to `auth.uid` |
| Read public templates | `templates` | Authenticated | Filter: `visibility == 'public'` |
| Read event templates | `templates` | Registered or Organizer | Filter by `eventId` |
| Update template | `templates` | Creator | |
| CRUD attribute definitions | `templates/{id}/attributeDefinitions` | Template Creator | |
| CRUD ability definitions | `templates/{id}/abilityDefinitions` | Template Creator | |

### 3.4 Game System Item Catalog (Phase 2) — Inventory Module

| Operation | Collection | Auth Requirement | Notes |
|-----------|------------|------------------|-------|
| CRUD item definitions | `gameSystems/{id}/itemCatalog` | Game System creator/organizer | Master catalog; items have name, description, optional submodule config (Equipable, Consumables) |
| Read item catalog | `gameSystems/{id}/itemCatalog` | Authenticated (if public) | Players read when creating/linking characters |

Event item catalog (`events/{id}/itemCatalog`) references `gameSystemItemId` and adds event-specific availability (maxPerCharacter, totalAvailable, distributedCount).

---

## 4. Cloud Functions - MVP

### 4.1 `syncOfflineChanges`

**Purpose**: Reconcile changes made while offline with server state.

**Trigger**: Callable function

**Auth Required**: Authenticated user

**When Needed**: When client reconnects after offline edits (journal entries, character notes).

```typescript
// Request
interface SyncOfflineChangesRequest {
  changes: {
    collection: string;           // e.g., "characters/{id}/journal"
    documentId: string;
    operation: 'create' | 'update' | 'delete';
    data: Record<string, any>;
    clientTimestamp: Timestamp;   // When change was made offline
  }[];
}

// Response
interface SyncOfflineChangesResponse {
  success: true;
  results: {
    documentId: string;
    status: 'applied' | 'conflict' | 'rejected';
    serverTimestamp?: Timestamp;
    conflictData?: Record<string, any>; // Server version if conflict
  }[];
}
```

**Error Codes**:
| Code | Description |
|------|-------------|
| `SYNC_PARTIAL_FAILURE` | Some changes failed; check individual results |

**Conflict Resolution Rules**:
- Journal entries: Last-write-wins (no conflicts possible for create)
- Character fields: Server wins if `serverTimestamp > clientTimestamp`
- Inventory quantities: Additive merge (both changes applied)

---

## 5. Cloud Functions - Phase 2

### 5.1 `claimPreGenCharacter`

**Purpose**: Allow a player to claim a pre-generated character for an event.

**Trigger**: Callable function

**Auth Required**: Authenticated user with event registration

**Why Server-Side**: Prevents race conditions where two players claim the same character.

```typescript
// Request
interface ClaimPreGenCharacterRequest {
  eventId: string;
  characterId: string;
}

// Response
interface ClaimPreGenCharacterResponse {
  success: true;
  character: {
    id: string;
    name: string;
    claimedAt: Timestamp;
  };
}
```

**Error Codes**:
| Code | Description |
|------|-------------|
| `CLAIM_NOT_REGISTERED` | User is not registered for this event |
| `CLAIM_ALREADY_CLAIMED` | Character was claimed by another player |
| `CLAIM_NOT_PREGEN` | Character is not a pre-generated character |
| `CLAIM_USER_HAS_CHARACTER` | User already has a character for this event |
| `CLAIM_EVENT_NOT_ACCEPTING` | Event is not in a state that accepts claims |

**Side Effects**:
- Updates `characters/{characterId}`: sets `claimedBy`, `preGenStatus = 'claimed'`
- Updates `events/{eventId}/registrations/{regId}`: sets `characterId`, `characterName`
- Creates notification for organizer (optional based on event settings)

---

### 5.2 `pushCharacterUpdate`

**Purpose**: Allow organizer to modify a player's character (add items, update attributes, grant abilities).

**Trigger**: Callable function

**Auth Required**: Event organizer or co-organizer

**Why Server-Side**: Security (prevents players from self-granting items); audit trail.

```typescript
// Request
interface PushCharacterUpdateRequest {
  characterId: string;
  eventId: string;
  updates: {
    // Inventory changes
    addItems?: {
      gameSystemItemId?: string;  // Reference to Game System master catalog (preferred)
      catalogItemId?: string;     // Reference to event item catalog (for distribution tracking)
      name: string;               // Required if no gameSystemItemId; denormalized for display
      description?: string;
      quantity?: number;          // Default: 1
      properties?: Record<string, any>;
    }[];
    removeItems?: {
      itemId: string;
      quantity?: number;          // Default: remove all
    }[];

    // Attribute changes
    updateAttributes?: {
      attributeId?: string;       // Existing attribute to update
      name?: string;              // For creating new attribute
      value: string | number | boolean;
    }[];

    // Ability changes
    addAbilities?: {
      name: string;
      description: string;
      abilityType?: 'ability' | 'advantage' | 'disadvantage';
      category?: string;
      isKeyAbility?: boolean;
    }[];
    removeAbilities?: {
      abilityId: string;
    }[];

    // Currency changes
    updateCurrencies?: {
      currencyId?: string;
      name?: string;               // For creating new currency entry
      amount: number;
    }[];

    // Relationship changes (organizer can add/update for NPCs)
    addRelationships?: {
      targetCharacterId: string;
      targetCharacterName?: string;
      relationshipType: string;
      description?: string;
      mutual?: boolean;
    }[];
    removeRelationships?: {
      relationshipId: string;
    }[];
  };

  // Notification settings
  notifyPlayer?: boolean;         // Default: true
  notificationMessage?: string;   // Custom message for player

  // Audit
  reason?: string;                // Why this update was made
}

// Response
interface PushCharacterUpdateResponse {
  success: true;
  updatedAt: Timestamp;
  changelogEntryId: string;       // Reference to audit log
  notificationSent: boolean;
}
```

**Error Codes**:
| Code | Description |
|------|-------------|
| `UPDATE_CHARACTER_NOT_FOUND` | Character does not exist |
| `UPDATE_EVENT_NOT_FOUND` | Event does not exist |
| `UPDATE_NOT_ORGANIZER` | User is not organizer of this event |
| `UPDATE_NOT_LINKED` | Character is not linked to this event |
| `UPDATE_ITEM_NOT_IN_CATALOG` | Referenced catalogItemId or gameSystemItemId not found |
| `UPDATE_ITEM_LIMIT_EXCEEDED` | Would exceed maxPerCharacter limit |
| `UPDATE_ATTRIBUTE_NOT_FOUND` | Referenced attributeId not found |
| `UPDATE_ABILITY_NOT_FOUND` | Referenced abilityId not found |

**Side Effects**:
- Creates/updates documents in character subcollections
- Creates changelog entry in `characters/{id}/changelog`
- Sends FCM notification to player (if enabled)
- Updates `character.updatedAt` and `character.quickStats` if applicable

---

### 5.3 `approveRegistration`

**Purpose**: Organizer approves (or rejects) a player's event registration.

**Trigger**: Callable function

**Auth Required**: Event organizer or co-organizer

**Why Server-Side**: Audit trail; notification delivery; prevents organizer impersonation.

```typescript
// Request
interface ApproveRegistrationRequest {
  eventId: string;
  registrationId: string;
  action: 'approve' | 'reject' | 'waitlist';
  organizerNotes?: string;        // Private notes (not sent to player)
  playerMessage?: string;         // Message to include in notification
}

// Response
interface ApproveRegistrationResponse {
  success: true;
  registration: {
    id: string;
    userId: string;
    status: 'approved' | 'rejected' | 'waitlisted';
    updatedAt: Timestamp;
  };
  notificationSent: boolean;
}
```

**Error Codes**:
| Code | Description |
|------|-------------|
| `APPROVE_EVENT_NOT_FOUND` | Event does not exist |
| `APPROVE_NOT_ORGANIZER` | User is not organizer of this event |
| `APPROVE_REGISTRATION_NOT_FOUND` | Registration does not exist |
| `APPROVE_ALREADY_PROCESSED` | Registration already approved/rejected |
| `APPROVE_EVENT_FULL` | Cannot approve; event at max capacity |

**Side Effects**:
- Updates `events/{eventId}/registrations/{registrationId}`
- Updates `events/{eventId}.registrationCount` (if approved)
- Sends FCM notification to player
- Creates audit entry

---

### 5.4 `distributeItems`

**Purpose**: Batch award items to multiple players (treasure distribution, event rewards).

**Trigger**: Callable function

**Auth Required**: Event organizer or co-organizer

**Why Server-Side**: Batch operation; inventory limit enforcement; catalog tracking.

```typescript
// Request
interface DistributeItemsRequest {
  eventId: string;
  distributions: {
    characterId: string;
    items: {
      gameSystemItemId?: string;  // Reference to Game System master catalog (preferred)
      catalogItemId?: string;     // Reference to event catalog (for distribution tracking)
      name: string;
      description?: string;
      quantity?: number;
      properties?: Record<string, any>;
    }[];
  }[];
  notifyPlayers?: boolean;        // Default: true
  notificationMessage?: string;
}

// Response
interface DistributeItemsResponse {
  success: true;
  results: {
    characterId: string;
    itemsAdded: number;
    status: 'success' | 'partial' | 'failed';
    errors?: string[];            // If partial/failed
  }[];
  totalItemsDistributed: number;
  notificationsSent: number;
}
```

**Error Codes**:
| Code | Description |
|------|-------------|
| `DISTRIBUTE_EVENT_NOT_FOUND` | Event does not exist |
| `DISTRIBUTE_NOT_ORGANIZER` | User is not organizer of this event |
| `DISTRIBUTE_EMPTY_REQUEST` | No distributions provided |
| `DISTRIBUTE_PARTIAL_FAILURE` | Some distributions failed; check results |

**Side Effects**:
- Creates inventory items for each character
- Updates `events/{eventId}/itemCatalog/{id}.distributedCount` for event catalog entries
- Sends batch FCM notifications
- Creates changelog entries for each character

---

### 5.5 `releasePreGenCharacter`

**Purpose**: Organizer releases a claimed pre-gen character back to the pool.

**Trigger**: Callable function

**Auth Required**: Event organizer or co-organizer

**Why Server-Side**: Must atomically update character and registration.

```typescript
// Request
interface ReleasePreGenCharacterRequest {
  eventId: string;
  characterId: string;
  notifyPlayer?: boolean;         // Default: true
  reason?: string;                // Included in player notification
}

// Response
interface ReleasePreGenCharacterResponse {
  success: true;
  character: {
    id: string;
    name: string;
    previousClaimant: string;     // User ID
  };
  notificationSent: boolean;
}
```

**Error Codes**:
| Code | Description |
|------|-------------|
| `RELEASE_CHARACTER_NOT_FOUND` | Character does not exist |
| `RELEASE_NOT_ORGANIZER` | User is not organizer of this event |
| `RELEASE_NOT_CLAIMED` | Character is not currently claimed |
| `RELEASE_NOT_PREGEN` | Character is not a pre-generated character |

**Side Effects**:
- Updates character: `claimedBy = null`, `preGenStatus = 'available'`
- Updates registration: `characterId = null`, `characterName = null`
- Sends FCM notification to former claimant

---

## 6. Cloud Functions - Phase 3

### 6.1 `initiateItemTransfer`

**Purpose**: Player initiates transfer of an item to another player's character.

**Trigger**: Callable function

**Auth Required**: Owner of source character

**Why Server-Side**: Creates pending transfer; validates item ownership; prevents double-transfer.

```typescript
// Request
interface InitiateItemTransferRequest {
  fromCharacterId: string;
  toCharacterId: string;
  itemId: string;
  quantity?: number;              // Default: all
  eventId?: string;               // Context for the transfer
  message?: string;               // Message to recipient
}

// Response
interface InitiateItemTransferResponse {
  success: true;
  transfer: {
    id: string;
    status: 'pending';
    expiresAt: Timestamp;         // 7 days from now
  };
  notificationSent: boolean;
}
```

**Error Codes**:
| Code | Description |
|------|-------------|
| `TRANSFER_NOT_OWNER` | User does not own source character |
| `TRANSFER_ITEM_NOT_FOUND` | Item not in source character's inventory |
| `TRANSFER_INSUFFICIENT_QUANTITY` | Not enough quantity to transfer |
| `TRANSFER_SAME_CHARACTER` | Cannot transfer to same character |
| `TRANSFER_TARGET_NOT_FOUND` | Target character does not exist |
| `TRANSFER_ALREADY_PENDING` | Transfer already pending for this item |

**Side Effects**:
- Creates `itemTransfers/{transferId}` document
- Sends FCM notification to recipient
- Marks item as `transferPending = true` (prevents double-transfer)

---

### 6.2 `respondToItemTransfer`

**Purpose**: Recipient accepts or rejects a pending item transfer.

**Trigger**: Callable function

**Auth Required**: Owner of target character

**Why Server-Side**: Atomic move of item between characters.

```typescript
// Request
interface RespondToItemTransferRequest {
  transferId: string;
  action: 'accept' | 'reject';
}

// Response
interface RespondToItemTransferResponse {
  success: true;
  transfer: {
    id: string;
    status: 'accepted' | 'rejected';
    respondedAt: Timestamp;
  };
  item?: {                        // Only if accepted
    id: string;
    name: string;
    quantity: number;
  };
}
```

**Error Codes**:
| Code | Description |
|------|-------------|
| `RESPOND_TRANSFER_NOT_FOUND` | Transfer does not exist |
| `RESPOND_NOT_RECIPIENT` | User is not owner of target character |
| `RESPOND_TRANSFER_EXPIRED` | Transfer has expired |
| `RESPOND_ALREADY_RESPONDED` | Transfer already accepted/rejected |

**Side Effects (Accept)**:
- Removes/decrements item from source character inventory
- Creates item in target character inventory with `source: 'transfer'`
- Updates transfer status to `accepted`
- Sends FCM notification to sender

**Side Effects (Reject)**:
- Updates transfer status to `rejected`
- Clears `transferPending` flag on source item
- Sends FCM notification to sender

---

### 6.3 `sendStaffMessage`

**Purpose**: Organizer sends a message to staff members during an event.

**Trigger**: Callable function

**Auth Required**: Event organizer or co-organizer

**Why Server-Side**: Batch notification delivery; role filtering.

```typescript
// Request
interface SendStaffMessageRequest {
  eventId: string;
  message: string;
  priority: 'normal' | 'urgent';
  targetRoles?: string[];         // Filter by role; empty = all staff
}

// Response
interface SendStaffMessageResponse {
  success: true;
  messageId: string;
  recipientCount: number;
  deliveredCount: number;         // FCM successes
}
```

**Error Codes**:
| Code | Description |
|------|-------------|
| `STAFF_MSG_EVENT_NOT_FOUND` | Event does not exist |
| `STAFF_MSG_NOT_ORGANIZER` | User is not organizer of this event |
| `STAFF_MSG_NO_RECIPIENTS` | No staff match the target roles |
| `STAFF_MSG_EMPTY_MESSAGE` | Message cannot be empty |

**Side Effects**:
- Creates message document in `events/{eventId}/staffMessages`
- Sends FCM notifications to all matching staff
- Logs delivery results

---

### 6.4 `updateSecretKnowledge`

**Purpose**: Mark characters as knowing (or not knowing) a secret.

**Trigger**: Callable function

**Auth Required**: Event organizer, co-organizer, or plot writer with access

**Why Server-Side**: Audit trail; batch updates; cross-collection writes.

```typescript
// Request
interface UpdateSecretKnowledgeRequest {
  secretId: string;
  eventId: string;
  changes: {
    characterId: string;
    knows: boolean;               // true = add knowledge, false = remove
    method?: string;              // How they learned: "scene", "document", "npc", etc.
    notes?: string;               // Additional context
  }[];
}

// Response
interface UpdateSecretKnowledgeResponse {
  success: true;
  secret: {
    id: string;
    title: string;
    knownByCount: number;         // Updated count
  };
  updatedCharacters: string[];
}
```

**Error Codes**:
| Code | Description |
|------|-------------|
| `SECRET_NOT_FOUND` | Secret does not exist |
| `SECRET_EVENT_MISMATCH` | Secret does not belong to this event |
| `SECRET_NOT_AUTHORIZED` | User cannot modify this secret |
| `SECRET_CHARACTER_NOT_FOUND` | One or more characters not found |

**Side Effects**:
- Updates `plotThreads/{threadId}/secrets/{secretId}.knownBy` array
- Creates audit entries for each change
- Updates denormalized counts

---

## 7. Rate Limiting & Quotas

### 7.1 Default Rate Limits

| Scope | Limit | Window |
|-------|-------|--------|
| Per-user callable functions | 100 requests | 1 minute |
| Per-user writes | 500 operations | 1 minute |
| `distributeItems` (batch) | 10 requests | 1 minute |
| `sendStaffMessage` | 20 messages | 1 hour |

### 7.2 Quota Considerations

| Resource | Free Tier Limit | Scaling Notes |
|----------|-----------------|---------------|
| Firestore reads | 50K/day | Character viewing is read-heavy; monitor |
| Firestore writes | 20K/day | Batch operations count per document |
| Cloud Function invocations | 2M/month | Most operations are direct Firestore |
| FCM messages | Unlimited | No practical limit |
| Storage | 5GB | Character portraits main consumer |

### 7.3 Offline Sync Quotas

| Limit | Value | Rationale |
|-------|-------|-----------|
| Max offline characters | 20 (default) | Storage/memory constraints |
| Max pending sync operations | 100 | Prevent sync storms |
| Sync batch size | 20 operations | Rate limit friendly |
| Offline data TTL | 30 days | Auto-purge stale data |

---

## Appendix A: Changelog Entry Schema

All privileged operations create changelog entries for audit:

```typescript
interface ChangelogEntry {
  id: string;
  characterId: string;
  eventId: string | null;

  // Actor
  performedBy: string;            // User ID
  performedByName: string;        // Denormalized
  performedByRole: 'owner' | 'organizer' | 'system';

  // Change details
  operation: string;              // Function name or operation type
  changes: {
    field: string;
    oldValue?: any;
    newValue?: any;
  }[];

  reason?: string;                // User-provided reason

  // Metadata
  timestamp: Timestamp;
  clientInfo?: {
    platform: string;
    version: string;
  };
}
```

---

## Appendix B: FCM Notification Payloads

### Standard Notification Shape

```typescript
interface NotificationPayload {
  notification: {
    title: string;
    body: string;
  };
  data: {
    type: string;                 // 'character_update', 'transfer_request', etc.
    targetId: string;             // Resource ID to navigate to
    eventId?: string;
    characterId?: string;
    actionRequired: 'true' | 'false';
  };
  android: {
    priority: 'normal' | 'high';
    channelId: string;            // 'updates', 'transfers', 'staff', 'urgent'
  };
  apns: {
    payload: {
      aps: {
        sound: 'default' | 'urgent.wav';
        badge?: number;
      };
    };
  };
}
```

### Notification Types

| Type | Title Example | Channel |
|------|---------------|---------|
| `character_update` | "Character Updated" | updates |
| `item_received` | "New Item Received" | updates |
| `transfer_request` | "Item Transfer Request" | transfers |
| `transfer_complete` | "Transfer Accepted" | transfers |
| `registration_approved` | "Registration Approved" | updates |
| `staff_message` | "Staff Alert" | staff |
| `staff_urgent` | "URGENT: Staff Alert" | urgent |

---

*Document prepared for RoleKeeper development team*
*Complements: System Architecture v1.0, Product Requirements v1.0*
