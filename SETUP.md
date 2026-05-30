# TDD Workflow Setup Instructions

Follow these steps in order to get the system running.

---

## Step 1: Install Firebase CLI

```bash
npm install -g firebase-tools
firebase login
```

Verify it works:
```bash
firebase projects:list
# Should show rolekeeper-7ddcc
```

---

## Step 2: Add ESLint to Functions

```bash
cd functions
npm install --save-dev \
  eslint \
  @eslint/js \
  @typescript-eslint/eslint-plugin \
  @typescript-eslint/parser \
  globals
```

Test it works:
```bash
npx eslint src/ --max-warnings 0
```

You'll likely get some existing warnings — fix or configure them before
adding the TDD workflow (the lint gate will block agents until it's clean).

---

## Step 3: Install the TDD MCP server dependencies

```bash
cd tdd-mcp
npm install
```

Test it starts:
```bash
npx tsx src/index.ts
# Should start silently (it's a stdio server — no output means it's working)
# Ctrl+C to stop
```

---

## Step 4: Make scripts executable

```bash
chmod +x scripts/lint.sh scripts/test.sh
```

Test lint manually:
```bash
bash scripts/lint.sh
```

Test tests manually:
```bash
bash scripts/test.sh
```

Both must exit 0 cleanly before agents can use them.

---

## Step 5: Enable the MCP servers in Cursor

Copy `.cursor/` into your project root (if not already there).

In Cursor:
- Open Settings → MCP
- You should see `rolekeeper-tdd` and `firebase` listed
- Enable both

---

## Step 6: Set up GitHub Actions secrets

In your GitHub repo → Settings → Secrets and variables → Actions:

For CI (simpler, temporary):
```
FIREBASE_TOKEN  →  run `firebase login:ci` locally, paste the token
```

For CD (production, recommended — Workload Identity Federation):
```
WIF_PROVIDER         →  projects/{number}/locations/global/workloadIdentityPools/{pool}/providers/{provider}
WIF_SERVICE_ACCOUNT  →  deploy-sa@rolekeeper-7ddcc.iam.gserviceaccount.com
```

See: https://github.com/google-github-actions/auth for WIF setup instructions.

---

## Step 7: Queue your first task

Write a task file following `docs/tasks/TASK_FORMAT.md`:

```bash
cp docs/tasks/TASK_FORMAT.md docs/tasks/ready/001-coder.md
# Edit 001-coder.md with your actual task
```

Then open Cursor Agent and say:
> "Call get_current_task_state and begin work."

---

## Daily Workflow

1. Write task files into `docs/tasks/ready/`
2. Open Cursor Agent → "Call get_current_task_state and begin work"
3. Agent works the TDD loop autonomously
4. When a task completes, agent outputs git commands — run them
5. Open PR on GitHub → CI runs → you review → merge → CD deploys

---

## Monitoring

| Directory | Meaning |
|---|---|
| `docs/tasks/ready/` | Queued, waiting for an agent |
| `docs/tasks/done/` | Completed successfully |
| `docs/tasks/error/` | Failed 3 times — needs human review |
| `docs/tasks/review/` | Blocked — audit failure, needs intervention |
