/**
 * OpenCode Plugin: Post-Code Hook
 *
 * Wires the shared check scripts into OpenCode's plugin events:
 *   tool.execute.before -> pre_deploy_check.sh   (cdk deploy/destroy guard)
 *   tool.execute.after  -> post_code_hook.sh     (fast file-scoped lint/type-check)
 *   session.idle        -> post_task_hook.sh     (end-of-session battery)
 *
 * OpenCode has no "ask" permission verb for plugins (permission.ask is not
 * fired for first-encounter commands), so the pre-deploy guard approximates
 * Claude's ask-protocol: the FIRST attempt of a matching command throws with
 * the confirmation reason (blocking that call and telling the model to check
 * with the user); re-running the identical command then passes through.
 *
 * Installed to ~/.config/opencode/plugins/ by install_opencode.sh, which
 * substitutes the path placeholders with the repo's shared/hooks paths.
 */

// Debounce to avoid running on every single tool call in rapid succession
let lastCodeRunTime = 0;
const CODE_DEBOUNCE_MS = 5000;

// Session idle debounce — only run task checks once per idle period
let lastIdleRunTime = 0;
const IDLE_DEBOUNCE_MS = 60000; // 1 minute between idle checks

// Hook script paths (replaced by install_opencode.sh via sed)
const HOOK_SCRIPT = "__HOOK_SCRIPT_PATH__";
const TASK_HOOK_SCRIPT = "__TASK_HOOK_SCRIPT_PATH__";
const PRE_DEPLOY_CHECK_SCRIPT = "__PRE_DEPLOY_CHECK_PATH__";

// Tools that modify files and should trigger the hook
const WRITE_TOOLS = new Set([
  "write",
  "edit",
  "notebook_edit",
  "create",
  "patch",
  "insert",
  "replace",
  "multi_edit",
]);

// Commands already blocked once by the pre-deploy guard; a retry of the
// exact same command is treated as user-confirmed and allowed through.
const preDeployConfirmed = new Set();

export const PostCodeHookPlugin = async ({ $, directory, worktree }) => {
  const cwd = worktree || directory;

  return {
    "tool.execute.before": async (input, output) => {
      const toolName = (input.tool || "").toLowerCase();
      if (toolName !== "bash") {
        return;
      }
      const command = output?.args?.command;
      if (!command) {
        return;
      }

      let reason = "";
      try {
        const res = await $`bash ${PRE_DEPLOY_CHECK_SCRIPT} ${command}`
          .quiet()
          .cwd(cwd);
        reason = res.stdout.toString().trim();
      } catch {
        return; // the guard itself failing must never block normal commands
      }
      if (!reason) {
        return;
      }

      if (preDeployConfirmed.has(command)) {
        preDeployConfirmed.delete(command);
        return; // second attempt — user confirmed, let it run
      }
      preDeployConfirmed.add(command);
      throw new Error(
        `${reason} Ask the user to confirm, then re-run the exact same command to proceed.`
      );
    },

    "tool.execute.after": async (input) => {
      const toolName = (input.tool || "").toLowerCase();

      // Only trigger on file-modifying tools
      if (!WRITE_TOOLS.has(toolName)) {
        return;
      }

      // Debounce rapid consecutive writes
      const now = Date.now();
      if (now - lastCodeRunTime < CODE_DEBOUNCE_MS) {
        return;
      }
      lastCodeRunTime = now;

      try {
        await $`bash ${HOOK_SCRIPT}`.cwd(cwd);
      } catch (err) {
        console.error(
          `[post-code-hook] Hook exited with issues: ${err.message}`
        );
      }
    },

    "session.idle": async () => {
      // Debounce: only run once per idle period
      const now = Date.now();
      if (now - lastIdleRunTime < IDLE_DEBOUNCE_MS) {
        return;
      }
      lastIdleRunTime = now;

      try {
        await $`bash ${TASK_HOOK_SCRIPT}`.cwd(cwd);
      } catch (err) {
        console.error(
          `[post-task-hook] Session validation found issues: ${err.message}`
        );
      }
    },
  };
};
