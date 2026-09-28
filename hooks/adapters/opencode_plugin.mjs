/**
 * OpenCode Plugin: quality and safety hooks
 *
 * Wires the shared check scripts into OpenCode's plugin API
 * (opencode.ai/docs/plugins):
 *   tool.execute.before -> pre_deploy_check.sh  (cdk deploy/destroy guard)
 *                          pre_commit_check.sh  (checkpoint before git commit)
 *   tool.execute.after  -> post_code_hook.sh    (fast file-scoped checks; the
 *                          findings are appended to the tool output, which is
 *                          what the model reads next)
 *   event session.idle  -> post_task_hook.sh    (turn-end battery; findings are
 *                          sent back into the session as a prompt so the
 *                          agent fixes them)
 *
 * session.idle is a bus event, not a hook key, so it is handled in `event`.
 * The turn-end hook only re-runs when the working tree changed since its last
 * run, so an agent that was sent findings and changed nothing goes idle
 * normally instead of looping.
 *
 * OpenCode has no "ask" permission verb for plugins, so the pre-deploy guard
 * approximates it: the FIRST attempt of a matching command throws with the
 * confirmation reason (blocking that call and telling the model to check with
 * the user); re-running the identical command then passes through.
 *
 * Installed to ~/.config/opencode/plugins/ by installers/opencode.sh, which
 * substitutes the path placeholders with the repo's hooks/ paths.
 */

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

// Commands already blocked once by the pre-deploy guard; a retry of the
// exact same command is treated as user-confirmed and allowed through.
const preDeployConfirmed = new Set();

// Sessions with a turn-end check in flight (session.idle can fire repeatedly).
const taskRunning = new Set();

export const PostCodeHookPlugin = async ({ $, client, directory, worktree }) => {
  const cwd = worktree || directory;

  return {
    "tool.execute.before": async (input, output) => {
      if ((input.tool || "").toLowerCase() !== "bash") return;
      const command = output?.args?.command;
      if (!command) return;

      // Local checkpoint: a failing `git commit` checkpoint blocks the call
      // with the findings, which the model reads as the tool error.
      let checkpoint = "";
      try {
        const res = await $`bash ${PRE_COMMIT_CHECK_SCRIPT} ${command}`.quiet().nothrow().cwd(cwd);
        checkpoint = res.stdout.toString().trim();
      } catch {
        checkpoint = "";
      }
      if (checkpoint) throw new Error(checkpoint);

      // Second attempt of a command the guard blocked: the user confirmed,
      // so let it run without re-running the check (and its cdk diff).
      if (preDeployConfirmed.has(command)) {
        preDeployConfirmed.delete(command);
        return;
      }

      let reason = "";
      try {
        const res = await $`bash ${PRE_DEPLOY_CHECK_SCRIPT} ${command}`.quiet().nothrow().cwd(cwd);
        reason = res.stdout.toString().trim();
      } catch {
        return; // the guard itself failing must never block normal commands
      }
      if (!reason) return;

      preDeployConfirmed.add(command);
      throw new Error(
        `${reason} Ask the user to confirm, then re-run the exact same command to proceed.`
      );
    },

    "tool.execute.after": async (input, output) => {
      if (!WRITE_TOOLS.has((input.tool || "").toLowerCase())) return;
      const files = editedPaths(input.args || output?.metadata?.args);
      if (files.length === 0) return;

      try {
        const res = await $`bash ${HOOK_SCRIPT} --format text ${files}`.quiet().nothrow().cwd(cwd);
        const findings = res.stdout.toString().trim();
        if (findings && output) {
          output.output = `${output.output ?? ""}\n\n${findings}`;
        }
      } catch {
        // Advisory — a failing check script must never break the edit.
      }
    },

    event: async ({ event }) => {
      if (event?.type !== "session.idle") return;
      const sessionID = event.properties?.sessionID;
      if (!sessionID || taskRunning.has(sessionID)) return;
      taskRunning.add(sessionID);
      try {
        const res = await $`bash ${TASK_HOOK_SCRIPT} --format text < /dev/null`.quiet().nothrow().cwd(cwd);
        const findings = res.stdout.toString().trim();
        if (findings) {
          await client.session.prompt({
            path: { id: sessionID },
            body: { parts: [{ type: "text", text: findings }] },
          });
        }
      } catch {
        // Advisory — never let the turn-end battery wedge the session.
      } finally {
        taskRunning.delete(sessionID);
      }
    },
  };
};
