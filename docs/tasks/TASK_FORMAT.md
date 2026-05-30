# Task Format Guide

Tasks are markdown files placed in `docs/tasks/ready/`.

## Filename Convention

```
{NNN}-{role}.md
```

- `NNN` — zero-padded number (001, 002, 003...). Lower = higher priority.
- `role` — one of: `coder`, `reviewer`, `debugger`, `security`, `performance`

**Examples:**
```
001-coder.md
002-reviewer.md
003-coder.md
```

## Task File Template

```markdown
# Task {NNN}: {Short Title}

## Objective
One sentence describing what this task accomplishes.

## Requirements
- Bullet list of specific, testable requirements
- Each requirement should be independently verifiable
- Be explicit about edge cases

## Acceptance Criteria
- [ ] Specific measurable outcome 1
- [ ] Specific measurable outcome 2
- [ ] All existing tests still pass
- [ ] New tests cover the new behaviour

## Files Likely Affected
- `functions/src/path/to/file.ts`
- `lib/path/to/widget.dart`
- `firestore.rules` (if security rules change)

## Context
Any background the agent needs — existing patterns to follow,
related task IDs, API contracts, data models, etc.

## Out of Scope
Explicitly list what this task does NOT cover, to prevent scope creep.
```

---

## Example Task

```markdown
# Task 001: Add createGame callable function

## Objective
Implement a Firebase callable function that creates a new game tenant
and returns the game ID.

## Requirements
- Accepts `gameName: string` and `hostUserId: string` as parameters
- Validates that gameName is non-empty and <= 100 characters
- Creates a Firestore document at `games/{gameId}` with status `active`
- Returns `{ gameId: string }` on success
- Throws `invalid-argument` if validation fails
- Throws `unauthenticated` if caller is not authenticated

## Acceptance Criteria
- [ ] Unit tests cover happy path
- [ ] Unit tests cover each validation error case
- [ ] Unit tests cover unauthenticated caller
- [ ] Function is exported from `functions/src/index.ts`
- [ ] All existing tests still pass

## Files Likely Affected
- `functions/src/game/createGame.ts` (new)
- `functions/src/game/createGame.test.ts` (new)
- `functions/src/index.ts` (export)

## Context
Follow the pattern established in `functions/src/gameTenant.ts`.
Game IDs should use the `short_id` utility from the Flutter side —
replicate the same algorithm in TypeScript.

## Out of Scope
- Flutter UI for creating a game
- Game settings or configuration (separate task)
```
