/**
 * OpenCode Plugin: quality and safety hooks
 *
 * Wires the shared check scripts into OpenCode's plugin API
 * (opencode.ai/v2/docs/build/plugins):
 *   ctx.tool.hook("execute.before") -> pre_deploy_check.sh  (cdk deploy/destroy guard)
 *                                       pre_commit_check.sh  (checkpoint before git commit)
 *   ctx.tool.hook("execute.after")  -> post_code_hook.sh    (fast file-scoped checks; the
 *                                       findings are appended to the tool result content,
 *                                       which is what the model reads next)
 *   ctx.event.subscribe()           -> session.idle          (turn-end battery via
 *                                       post_task_hook.sh; findings are sent back into the
 *                                       session as a prompt so the agent fixes them)
 *
 * V2 plugins must default-export { id, setup } — a V1 named-export function
 * is rejected by the loader ("must export a default definition with an id
 * and an effect or setup function"), so this file is the V2 shape only.
 *
 * The session.idle subscription only re-runs the turn-end hook when the
 * working tree changed since its last run, so an agent that was sent findings
 * and changed nothing goes idle normally instead of looping.
 *
 * OpenCode has no "ask" permission verb for plugins, so the pre-deploy guard
 * approximates it: the FIRST attempt of a matching command throws with the
 * confirmation reason (blocking that call and telling the model to check with
 * the user); re-running the identical command then passes through.
 *
 * Installed to ~/.config/opencode/plugins/ by installers/opencode.sh, which
 * substitutes the path placeholders with the repo's hooks/ paths.
 */

import { spawn } from "node:child_process";

// Hook script paths (replaced by installers/opencode.sh via sed)
const HOOK_SCRIPT = "__HOOK_SCRIPT_PATH__";
const TASK_HOOK_SCRIPT = "__TASK_HOOK_SCRIPT_PATH__";
const PRE_DEPLOY_CHECK_SCRIPT = "__PRE_DEPLOY_CHECK_PATH__";
const PRE_COMMIT_CHECK_SCRIPT = "__PRE_COMMIT_CHECK_PATH__";

// Tools that modify files and should trigger the per-edit checks.
// apply_patch is the edit tool GPT-family models use in OpenCode.
const WRITE_TOOLS = new Set([
  "write",
  "edit",
  "multiedit",
  "multi_edit",
  "patch",
  "apply_patch",
  "notebook_edit",
]);

// Paths a write tool touched: filePath for write/edit, or the file headers of
// an apply_patch patch ("*** Add File: …", "*** Update File: …", "*** Move to: …").
function editedPaths(args = {}) {
  const paths = [args.filePath, args.file_path, args.path].filter(
    (p) => typeof p === "string" && p
  );
  for (const text of [args.patchText, args.patch, args.input]) {
    if (typeof text !== "string") continue;
    for (const m of text.matchAll(/^\*\*\* (?:Add File|Update File|Move to): (.+)$/gm)) {
      paths.push(m[1].trim());
    }
  }
  return [...new Set(paths)];
}

// Run one shared hook script and return its trimmed stdout. A script that
// fails to launch yields nothing, so a broken check can never block work.
function runHook(script, args, cwd) {
  return new Promise((resolve) => {
    let out = "";
    const child = spawn("bash", [script, ...args], {
      cwd,
      stdio: ["ignore", "pipe", "pipe"],
    });
    child.stdout.on("data", (d) => (out += d));
    child.on("error", () => resolve(""));
    child.on("close", () => resolve(out.trim()));
  });
}

// Commands already blocked once by the pre-deploy guard; a retry of the
// exact same command is treated as user-confirmed and allowed through.
const preDeployConfirmed = new Set();

// Sessions with a turn-end check in flight (session.idle can fire repeatedly).
const taskRunning = new Set();

export default {
  id: "macols-post-code-hooks",
  async setup(ctx) {
    const cwd = ctx.location.directory;

    await ctx.tool.hook("execute.before", async (event) => {
      if ((event.tool || "").toLowerCase() !== "bash") return;
      const command = event.input?.command;
      if (!command) return;

      // Local checkpoint: a failing `git commit` checkpoint blocks the call
      // with the findings, which the model reads as the tool error.
      const checkpoint = await runHook(PRE_COMMIT_CHECK_SCRIPT, [command], cwd);
      if (checkpoint) throw new Error(checkpoint);

      // Second attempt of a command the guard blocked: the user confirmed,
      // so let it run without re-running the check (and its cdk diff).
      if (preDeployConfirmed.has(command)) {
        preDeployConfirmed.delete(command);
        return;
      }

      const reason = await runHook(PRE_DEPLOY_CHECK_SCRIPT, [command], cwd);
      if (!reason) return; // the guard itself failing must never block normal commands

      preDeployConfirmed.add(command);
      throw new Error(
        `${reason} Ask the user to confirm, then re-run the exact same command to proceed.`
      );
    });

    await ctx.tool.hook("execute.after", async (event) => {
      if (event.status !== "completed") return;
      if (!WRITE_TOOLS.has((event.tool || "").toLowerCase())) return;
      const files = editedPaths(event.input || {});
      if (files.length === 0) return;

      // Advisory — a failing check script must never break the edit.
      const findings = await runHook(HOOK_SCRIPT, ["--format", "text", ...files], cwd);
      if (!findings || !event.result) return;

      const result = event.result;
      if (typeof result.content === "string") {
        result.content = `${result.content}\n\n${findings}`;
      } else if (Array.isArray(result.content)) {
        result.content = [...result.content, { type: "text", text: findings }];
      } else {
        event.result = { ...result, content: findings };
      }
    });

    const controller = new AbortController();
    void (async () => {
      for await (const event of ctx.event.subscribe({ signal: controller.signal })) {
        if (event.type !== "session.idle") continue;
        const sessionID = event.data?.sessionID;
        if (!sessionID || taskRunning.has(sessionID)) continue;
        taskRunning.add(sessionID);
        try {
          const findings = await runHook(TASK_HOOK_SCRIPT, ["--format", "text"], cwd);
          if (findings) {
            await ctx.session.prompt({ sessionID, text: findings });
          }
        } catch {
          // Advisory — never let the turn-end battery wedge the session.
        } finally {
          taskRunning.delete(sessionID);
        }
      }
    })();
    return () => controller.abort();
  },
};
