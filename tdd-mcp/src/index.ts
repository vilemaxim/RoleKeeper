/**
 * RoleKeeper TDD Loop MCP Server
 *
 * Enforces the TDD state machine for AI agents working the task queue.
 * Adapted from mike-heckman/ai-project-configuration tdd-loop-manager.ts,
 * replacing the pi.dev ExtensionAPI with MCP tools.
 *
 * Tools exposed:
 *   - get_current_task_state  : called by agent at start of every session
 *   - success                 : advance state (runs verification first)
 *   - failure                 : record failure / route rejection
 */

import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import {
  CallToolRequestSchema,
  ListToolsRequestSchema,
} from "@modelcontextprotocol/sdk/types.js";
import * as fs from "node:fs";
import * as path from "node:path";
import { execSync } from "node:child_process";
import { createRequire } from "node:module";

const require = createRequire(import.meta.url);

// ---------------------------------------------------------------------------
// Configuration
// ---------------------------------------------------------------------------

// Workspace root — Cursor starts MCP servers from the project root,
// so process.cwd() is the RoleKeeper project directory.
const WORKSPACE = process.env.WORKSPACE_PATH ?? process.cwd();
const TASKS_DIR = path.join(WORKSPACE, "docs", "tasks");
const READY_DIR = path.join(TASKS_DIR, "ready");
const DONE_DIR = path.join(TASKS_DIR, "done");
const ERROR_DIR = path.join(TASKS_DIR, "error");
const REVIEW_DIR = path.join(TASKS_DIR, "review");

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

enum MicroStepState {
  TEST_OR_LINTING_FAILED = "TEST_OR_LINTING_FAILED",
  CODER_TEST_CREATION = "CODER_TEST_CREATION",
  CODER_IMPLEMENTATION = "CODER_IMPLEMENTATION",
  CODER_REFACTOR = "CODER_REFACTOR",
  DEBUG_ANALYSIS = "DEBUG_ANALYSIS",
  DEBUG_IMPLEMENTATION = "DEBUG_IMPLEMENTATION",
  REVIEW_AUDIT = "REVIEW_AUDIT",
  SECURITY_AUDIT = "SECURITY_AUDIT",
  PERF_AUDIT = "PERF_AUDIT",
}

interface TaskState {
  current_role: string;
  current_step: MicroStepState;
  consecutive_errors: number;
  task_file: string;
  task_id: string;
}

// ---------------------------------------------------------------------------
// Lockfile helpers
// ---------------------------------------------------------------------------

let lockfile: any = null;
try {
  lockfile = require("proper-lockfile");
} catch {
  // Installed at runtime; fallback allows single-worker operation without it
}

let currentLockRelease: (() => Promise<void>) | null = null;

async function acquireTaskLock(fullPath: string): Promise<boolean> {
  if (!lockfile) return true;
  try {
    currentLockRelease = await lockfile.lock(fullPath, {
      stale: 60_000,
      update: 20_000,
      retries: 0,
    });
    return true;
  } catch {
    return false;
  }
}

async function releaseTaskLock(): Promise<void> {
  if (currentLockRelease) {
    try { await currentLockRelease(); } catch { }
    currentLockRelease = null;
  }
}

// ---------------------------------------------------------------------------
// State persistence
// ---------------------------------------------------------------------------

function stateFilePath(taskId: string): string {
  return path.join(TASKS_DIR, `.${taskId}.state.json`);
}

function loadState(taskId: string, role: string): TaskState {
  const file = stateFilePath(taskId);
  if (fs.existsSync(file)) {
    try { return JSON.parse(fs.readFileSync(file, "utf-8")); } catch { }
  }

  // Determine default starting step based on role
  let defaultStep = MicroStepState.CODER_TEST_CREATION;
  if (role === "reviewer")    defaultStep = MicroStepState.REVIEW_AUDIT;
  if (role === "debugger")    defaultStep = MicroStepState.DEBUG_ANALYSIS;
  if (role === "security")    defaultStep = MicroStepState.SECURITY_AUDIT;
  if (role === "performance") defaultStep = MicroStepState.PERF_AUDIT;

  return {
    current_role: role,
    current_step: defaultStep,
    consecutive_errors: 0,
    task_file: `docs/tasks/ready/${taskId}-${role}.md`,
    task_id: taskId,
  };
}

function saveState(state: TaskState): void {
  fs.writeFileSync(stateFilePath(state.task_id), JSON.stringify(state, null, 2));
}

function clearState(taskId: string): void {
  const file = stateFilePath(taskId);
  if (fs.existsSync(file)) fs.unlinkSync(file);
}

// ---------------------------------------------------------------------------
// Task queue
// ---------------------------------------------------------------------------

async function getNextTask(): Promise<{ file: string; taskId: string; role: string } | null> {
  if (!fs.existsSync(READY_DIR)) return null;

  const files = fs.readdirSync(READY_DIR)
    .filter(f => f.endsWith(".md") && /^\d+-/.test(f))
    .sort((a, b) => {
      const numA = parseInt(a.split("-")[0], 10);
      const numB = parseInt(b.split("-")[0], 10);
      return numA - numB;
    });

  for (const f of files) {
    const fullPath = path.join(READY_DIR, f);
    if (await acquireTaskLock(fullPath)) {
      const match = f.match(/^(\d+)-([a-zA-Z]+)\.md$/);
      const taskId = match ? match[1] : f.split("-")[0];
      const role = match ? match[2].toLowerCase() : "coder";
      return { file: `docs/tasks/ready/${f}`, taskId, role };
    }
  }
  return null;
}

function readTaskContent(relativeFile: string): string {
  const fullPath = path.resolve(WORKSPACE, relativeFile);
  if (fs.existsSync(fullPath)) {
    return fs.readFileSync(fullPath, "utf-8");
  }
  return "(task file not found)";
}

// ---------------------------------------------------------------------------
// Verification
// ---------------------------------------------------------------------------

function runVerification(): { pass: boolean; output: string } {
  let output = "";

  // Lint
  try {
    output = execSync("bash scripts/lint.sh", {
      cwd: WORKSPACE,
      timeout: 120_000,
    }).toString();
  } catch (e: any) {
    return {
      pass: false,
      output: `LINT FAILED:\n${e.stdout?.toString() ?? ""}\n${e.stderr?.toString() ?? ""}`,
    };
  }

  // Test
  try {
    output += "\n" + execSync("bash scripts/test.sh", {
      cwd: WORKSPACE,
      timeout: 300_000,
    }).toString();
  } catch (e: any) {
    return {
      pass: false,
      output: `TEST FAILED:\n${e.stdout?.toString() ?? ""}\n${e.stderr?.toString() ?? ""}`,
    };
  }

  return { pass: true, output };
}

// ---------------------------------------------------------------------------
// Phase instructions (same content as original tdd-loop-manager)
// ---------------------------------------------------------------------------

function getStepInstructions(step: MicroStepState): string {
  switch (step) {
    case MicroStepState.TEST_OR_LINTING_FAILED:
      return "Errors found or linting reported an issue. Run `scripts/lint.sh` and `scripts/test.sh` and resolve any issues found. Re-run until all issues are resolved. Call `success` when clean.";
    case MicroStepState.CODER_TEST_CREATION:
      return "Write the needed unit tests to test the requirements. Do not implement the feature yet. Verify they fail (Red phase). Call `success` when done.";
    case MicroStepState.CODER_IMPLEMENTATION:
      return "Failing tests have been written. Implement the code to make them pass. Call `success` when tests pass.";
    case MicroStepState.CODER_REFACTOR:
      return "Tests pass. Clean and optimize the code without altering functionality. Call `success` when done.";
    case MicroStepState.DEBUG_ANALYSIS:
      return "Tests are failing or code was rejected. Analyze the logs and codebase. Form a hypothesis and plan. Call `success` when done.";
    case MicroStepState.DEBUG_IMPLEMENTATION:
      return "Apply the fix based on your analysis. Verify locally. Call `success`.";
    case MicroStepState.REVIEW_AUDIT:
      return "Audit the implemented code against the original task requirements. You may NOT modify code. Call `success` to approve, or `failure` to reject.";
    case MicroStepState.SECURITY_AUDIT:
      return "Audit the code for security vulnerabilities. You may NOT modify code. Call `success` to approve, or `failure` to reject.";
    case MicroStepState.PERF_AUDIT:
      return "Audit the code for performance bottlenecks. You may NOT modify code. Call `success` to approve, or `failure` to reject.";
    default:
      return "UNKNOWN STEP — call failure immediately.";
  }
}

// ---------------------------------------------------------------------------
// Task completion helpers
// ---------------------------------------------------------------------------

function appendReportAndComplete(state: TaskState, report: string): void {
  const absPath = path.resolve(WORKSPACE, state.task_file);
  if (fs.existsSync(absPath)) {
    fs.appendFileSync(absPath, `\n\n# 📊 Agent Report\n\n${report}\n\n---\nDONE\n`);
  }
  const dest = path.join(DONE_DIR, path.basename(state.task_file));
  if (fs.existsSync(absPath)) {
    fs.renameSync(absPath, dest);
  }
  clearState(state.task_id);
}

function handleFailureThreshold(state: TaskState, report: string): void {
  const absPath = path.resolve(WORKSPACE, state.task_file);
  if (fs.existsSync(absPath)) {
    fs.appendFileSync(absPath, `\n\n# ❌ Agent Error Report\n\n${report}\n\nTask moved to error/ due to 3 consecutive failures.\n`);
  }
  const dest = path.join(ERROR_DIR, path.basename(state.task_file));
  if (fs.existsSync(absPath)) {
    fs.renameSync(absPath, dest);
  }
  clearState(state.task_id);
}

// ---------------------------------------------------------------------------
// Active session state (in-memory, single worker)
// ---------------------------------------------------------------------------

let activeTask: { file: string; taskId: string; role: string } | null = null;
let activeState: TaskState | null = null;

// ---------------------------------------------------------------------------
// Detect changed files for git handoff
// ---------------------------------------------------------------------------

function getChangedFiles(): string {
  try {
    return execSync("git diff --name-only HEAD", { cwd: WORKSPACE }).toString().trim();
  } catch {
    return "(unable to determine — run: git diff --name-only HEAD)";
  }
}

// ---------------------------------------------------------------------------
// MCP Server
// ---------------------------------------------------------------------------

const server = new Server(
  { name: "rolekeeper-tdd", version: "1.0.0" },
  { capabilities: { tools: {} } }
);

// List tools
server.setRequestHandler(ListToolsRequestSchema, async () => ({
  tools: [
    {
      name: "get_current_task_state",
      description:
        "Call this at the start of every session to get your current task, role, and phase instructions. Returns everything you need to begin work.",
      inputSchema: { type: "object", properties: {}, required: [] },
    },
    {
      name: "success",
      description:
        "Mark the current TDD phase as complete. Runs lint and test verification. Advances to the next phase if verification passes. When the final phase is complete, outputs git commands for you to run.",
      inputSchema: {
        type: "object",
        properties: {
          report_summary: {
            type: "string",
            description: "Summary of what was accomplished in this phase.",
          },
          context_dump: {
            type: "string",
            description: "Any context needed for the next phase.",
          },
          learnings: {
            type: "string",
            description: "Optional: implementation challenges, API quirks, or architectural friction encountered.",
          },
        },
        required: ["report_summary", "context_dump"],
      },
    },
    {
      name: "failure",
      description:
        "Mark the current phase as failed. Use when you cannot complete the phase or a reviewer rejects the work.",
      inputSchema: {
        type: "object",
        properties: {
          report_summary: {
            type: "string",
            description: "Summary of what failed.",
          },
          error_details: {
            type: "string",
            description: "Detailed failure context.",
          },
          context_dump: {
            type: "string",
            description: "Any context needed for the next attempt.",
          },
        },
        required: ["report_summary", "error_details", "context_dump"],
      },
    },
  ],
}));

// Handle tool calls
server.setRequestHandler(CallToolRequestSchema, async (request) => {
  const { name, arguments: args } = request.params;

  // -------------------------------------------------------------------------
  // get_current_task_state
  // -------------------------------------------------------------------------
  if (name === "get_current_task_state") {
    // Check for blocking review failures
    if (fs.existsSync(REVIEW_DIR)) {
      const failures = fs.readdirSync(REVIEW_DIR).filter(f => f.endsWith("-failure.md"));
      if (failures.length > 0) {
        return {
          content: [{
            type: "text",
            text: `🚫 BLOCKED: Critical review failures require human intervention.\n\nFailing audits in docs/tasks/review/:\n${failures.join("\n")}\n\nDo not proceed until the human resolves these.`,
          }],
        };
      }
    }

    // Restore or find task
    if (!activeTask) {
      activeTask = await getNextTask();
      if (!activeTask) {
        return {
          content: [{
            type: "text",
            text: "✅ No tasks in docs/tasks/ready/. Mission complete — or queue a new task.",
          }],
        };
      }
      activeState = loadState(activeTask.taskId, activeTask.role);
      saveState(activeState);
    } else if (!activeState) {
      activeState = loadState(activeTask.taskId, activeTask.role);
    }

    const taskContent = readTaskContent(activeTask.file);

    const injection = `
[TDD STATE — READ THIS CAREFULLY]

Active Role  : ${activeTask.role.toUpperCase()}
Task ID      : ${activeTask.taskId}
Task File    : ${activeTask.file}
Current Phase: ${activeState.current_step}
Errors so far: ${activeState.consecutive_errors}/3

TASK SPECIFICATION:
\`\`\`
${taskContent}
\`\`\`

PHASE GOAL:
${getStepInstructions(activeState.current_step)}

RULES:
- Do not skip phases. Complete the phase goal, then call \`success\`.
- If you cannot complete the phase, call \`failure\`.
- During REVIEW_AUDIT, SECURITY_AUDIT, PERF_AUDIT: you may NOT modify any code.
- Verification (lint + test) runs automatically when you call \`success\` on coding phases.
`;

    return { content: [{ type: "text", text: injection }] };
  }

  // -------------------------------------------------------------------------
  // success
  // -------------------------------------------------------------------------
  if (name === "success") {
    if (!activeTask || !activeState) {
      return {
        content: [{
          type: "text",
          text: "No active task. Call get_current_task_state first.",
        }],
      };
    }

    const { report_summary, context_dump, learnings } = args as any;
    const prevStep = activeState.current_step;

    // Phases that require verification
    const verifyPhases = [
      MicroStepState.TEST_OR_LINTING_FAILED,
      MicroStepState.CODER_IMPLEMENTATION,
      MicroStepState.CODER_REFACTOR,
      MicroStepState.DEBUG_IMPLEMENTATION,
    ];

    // CODER_TEST_CREATION expects tests to FAIL (red phase)
    if (activeState.current_step === MicroStepState.CODER_TEST_CREATION) {
      const verify = runVerification();
      if (verify.pass) {
        return {
          content: [{
            type: "text",
            text: `❌ RED PHASE VIOLATION: Tests passed when they should fail.\n\nIn CODER_TEST_CREATION (Red Phase), your new tests must FAIL — that proves they actually test something. Write failing tests first, then call success.\n\nVerification output:\n${verify.output}`,
          }],
        };
      }
      // Expected failure — proceed to implementation
      activeState.current_step = MicroStepState.CODER_IMPLEMENTATION;
      activeState.consecutive_errors = 0;
      saveState(activeState);
      return {
        content: [{
          type: "text",
          text: `✅ Red phase confirmed. Tests are failing as expected.\nAdvanced: ${prevStep} → ${activeState.current_step}\n\nNext: Implement the code to make those tests pass.`,
        }],
      };
    }

    // Run verification for coding phases
    if (verifyPhases.includes(activeState.current_step)) {
      const verify = runVerification();
      if (!verify.pass) {
        activeState.consecutive_errors++;
        if (activeState.consecutive_errors >= 3) {
          const state = activeState;
          await releaseTaskLock();
          activeTask = null;
          activeState = null;
          handleFailureThreshold(state, `Verification failed 3 times.\n\nLast output:\n${verify.output}`);
          return {
            content: [{
              type: "text",
              text: `💀 3 consecutive verification failures. Task moved to docs/tasks/error/.\n\nLast error:\n${verify.output}`,
            }],
          };
        }
        activeState.current_step = MicroStepState.TEST_OR_LINTING_FAILED;
        saveState(activeState);
        return {
          content: [{
            type: "text",
            text: `❌ Verification failed (${activeState.consecutive_errors}/3).\n\nReturned to TEST_OR_LINTING_FAILED. Fix the issues below, then call success again.\n\n${verify.output}`,
          }],
        };
      }
      activeState.consecutive_errors = 0;
    }

    // Save learnings if provided
    if (learnings) {
      if (!fs.existsSync(REVIEW_DIR)) fs.mkdirSync(REVIEW_DIR, { recursive: true });
      const learningsFile = path.join(REVIEW_DIR, `${activeState.task_id}-learnings.md`);
      fs.writeFileSync(
        learningsFile,
        `# 🧠 Task Learnings\n**Task:** ${activeState.task_id}\n**Role:** ${activeState.current_role.toUpperCase()}\n\n${learnings}\n`
      );
    }

    // State transitions
    switch (activeState.current_step) {
      case MicroStepState.TEST_OR_LINTING_FAILED:
        activeState.current_step = MicroStepState.CODER_TEST_CREATION;
        break;

      case MicroStepState.CODER_IMPLEMENTATION:
        activeState.current_step = MicroStepState.CODER_REFACTOR;
        break;

      case MicroStepState.CODER_REFACTOR: {
        // Task complete — output git handoff
        const changedFiles = getChangedFiles();
        const branchName = `feature/${activeState.task_id}-${activeState.current_role}`;
        const taskBasename = path.basename(activeTask.file, ".md");
        appendReportAndComplete(activeState, report_summary);
        await releaseTaskLock();
        activeTask = null;
        activeState = null;
        return {
          content: [{
            type: "text",
            text: `✅ Task complete!\n\n📋 HANDOFF — run these git commands:\n\n\`\`\`bash\ngit checkout -b ${branchName}\ngit add ${changedFiles.split("\n").join(" ")}\ngit commit -m "feat(${taskBasename}): ${report_summary.slice(0, 72)}"\ngit push origin ${branchName}\n\`\`\`\n\nThen open a PR on GitHub from \`${branchName}\` → \`main\`.\nOnce you approve and CI passes, merge — CD deploys automatically.\n\n---\n${context_dump}`,
          }],
        };
      }

      case MicroStepState.DEBUG_ANALYSIS:
        activeState.current_step = MicroStepState.DEBUG_IMPLEMENTATION;
        break;

      case MicroStepState.DEBUG_IMPLEMENTATION: {
        const changedFiles = getChangedFiles();
        const branchName = `fix/${activeState.task_id}`;
        appendReportAndComplete(activeState, report_summary);
        await releaseTaskLock();
        activeTask = null;
        activeState = null;
        return {
          content: [{
            type: "text",
            text: `✅ Debug task complete!\n\n📋 HANDOFF:\n\n\`\`\`bash\ngit checkout -b ${branchName}\ngit add ${changedFiles.split("\n").join(" ")}\ngit commit -m "fix: ${report_summary.slice(0, 72)}"\ngit push origin ${branchName}\n\`\`\`\n\nOpen a PR: \`${branchName}\` → \`main\``,
          }],
        };
      }

      case MicroStepState.REVIEW_AUDIT: {
        appendReportAndComplete(activeState, report_summary);
        await releaseTaskLock();
        activeTask = null;
        activeState = null;
        return {
          content: [{
            type: "text",
            text: `✅ Review approved.\n\n${report_summary}`,
          }],
        };
      }

      case MicroStepState.SECURITY_AUDIT:
      case MicroStepState.PERF_AUDIT: {
        const successFile = path.join(REVIEW_DIR, `${activeState!.task_id}-audit-pass.md`);
        fs.writeFileSync(successFile, `# ✅ Audit Passed\n\n${report_summary}\n`);
        appendReportAndComplete(activeState, report_summary);
        await releaseTaskLock();
        activeTask = null;
        activeState = null;
        return {
          content: [{ type: "text", text: `✅ Audit passed.\n\n${report_summary}` }],
        };
      }
    }

    saveState(activeState!);
    return {
      content: [{
        type: "text",
        text: `✅ Advanced: ${prevStep} → ${activeState!.current_step}\n\nNext phase goal:\n${getStepInstructions(activeState!.current_step)}\n\n${context_dump}`,
      }],
    };
  }

  // -------------------------------------------------------------------------
  // failure
  // -------------------------------------------------------------------------
  if (name === "failure") {
    if (!activeTask || !activeState) {
      return {
        content: [{ type: "text", text: "No active task. Call get_current_task_state first." }],
      };
    }

    const { report_summary, error_details, context_dump } = args as any;
    activeState.consecutive_errors++;

    if (activeState.consecutive_errors >= 3) {
      const state = activeState;
      await releaseTaskLock();
      activeTask = null;
      activeState = null;
      handleFailureThreshold(state, `${report_summary}\n\n${error_details}`);
      return {
        content: [{
          type: "text",
          text: `💀 3 consecutive failures. Task moved to docs/tasks/error/ for human review.`,
        }],
      };
    }

    // Review rejection — route back to coder
    if (activeState.current_step === MicroStepState.REVIEW_AUDIT) {
      const absPath = path.resolve(WORKSPACE, activeTask.file);
      if (fs.existsSync(absPath)) {
        fs.appendFileSync(absPath, `\n\n# ❌ Review Rejection\n\n${report_summary}\n\n${error_details}\n`);
      }
      const newFile = path.join(READY_DIR, `${activeState.task_id}-coder.md`);
      if (fs.existsSync(absPath)) {
        await releaseTaskLock();
        fs.renameSync(absPath, newFile);
      }
      clearState(activeState.task_id);
      activeTask = null;
      activeState = null;
      return {
        content: [{
          type: "text",
          text: `🔄 Review rejected. Task routed back to coder queue.\n\nRejection reason appended to task file.\n\n${error_details}`,
        }],
      };
    }

    // Security / perf audit failure — halt and flag for human
    if (
      activeState.current_step === MicroStepState.SECURITY_AUDIT ||
      activeState.current_step === MicroStepState.PERF_AUDIT
    ) {
      const absPath = path.resolve(WORKSPACE, activeTask.file);
      if (fs.existsSync(absPath)) {
        fs.appendFileSync(absPath, `\n\n# ❌ Critical Audit Failure\n\n${report_summary}\n\n${error_details}\n`);
      }
      const failureFile = path.join(REVIEW_DIR, `${activeState.task_id}-failure.md`);
      fs.writeFileSync(failureFile, `# ❌ Critical Audit Failure\n\n${report_summary}\n\n${error_details}\n`);
      clearState(activeState.task_id);
      activeTask = null;
      activeState = null;
      return {
        content: [{
          type: "text",
          text: `🚨 CRITICAL: Audit failed. Task flagged in docs/tasks/review/ — human intervention required before any further tasks can run.\n\n${error_details}`,
        }],
      };
    }

    // General failure — record and retry
    saveState(activeState);
    return {
      content: [{
        type: "text",
        text: `⚠️ Failure recorded (${activeState.consecutive_errors}/3). Try again.\n\n${error_details}\n\n${context_dump}`,
      }],
    };
  }

  return {
    content: [{ type: "text", text: `Unknown tool: ${name}` }],
  };
});

// ---------------------------------------------------------------------------
// Start server
// ---------------------------------------------------------------------------

const transport = new StdioServerTransport();
await server.connect(transport);
