// pi-checks — wires the shared check scripts into Oh My Pi (omp).
//
// omp has no settings.json hook array (hooks are extensions), so this small
// extension subscribes to the events that mirror the PreToolUse + PostToolUse
// + Stop hooks the other CLIs use:
//
//   tool_call    (bash tool)         -> hooks/pre_deploy_check.sh <command>
//                                       (cdk deploy/destroy guard; asks via
//                                        ctx.ui.confirm, blocks on decline)
//   tool_result  (write/edit tools)  -> hooks/post_code_hook.sh <file>
//   agent_end    (turn finished)     -> hooks/post_task_hook.sh, then the
//                                       advisory hooks/lgtmaybe_review_hook.sh
//
// The check scripts are advisory: they print findings, never block. Findings
// are surfaced back into the session via pi.sendMessage. Only the pre-deploy
// guard can block, and only after the user explicitly declines the confirm.
//
// HOOKS_DIR is substituted with the repo's shared/hooks path by install_pi.sh
// (the scripts are referenced in place, not copied).

import type { ExtensionAPI } from "@oh-my-pi/pi-coding-agent";

const HOOKS_DIR = "__PI_HOOKS_DIR__";
const WRITE_TOOL = /(write|edit|create|patch|replace)/i;

export default function (pi: ExtensionAPI) {
  const run = async (script: string, args: string[], signal?: AbortSignal) => {
    try {
      const res = await pi.exec("bash", [`${HOOKS_DIR}/${script}`, ...args], {
        signal,
        timeout: 300_000,
      });
      // lgtmaybe prints its findings to stderr; the deterministic batteries
      // print to stdout — surface both.
      const out = `${res.stdout || ""}\n${res.stderr || ""}`.trim();
      if (out) {
        pi.sendMessage({
          customType: "pi-checks",
          content: out,
          display: true,
        });
      }
    } catch {
      // Advisory only — never let a check failure disrupt the session.
    }
  };

  pi.on("tool_call", async (event: any, ctx: any) => {
    if (!/^bash$/i.test(String(event?.toolName ?? ""))) return;
    const command = String(event?.input?.command ?? "");
    if (!command) return;

    let reason = "";
    try {
      const res = await pi.exec(
        "bash",
        [`${HOOKS_DIR}/pre_deploy_check.sh`, command],
        { signal: ctx?.signal, timeout: 30_000 }
      );
      reason = `${res.stdout || ""}`.trim();
    } catch {
      return; // the guard itself failing must never block normal commands
    }
    if (!reason) return;

    try {
      const ok = await ctx.ui.confirm("cdk deploy/destroy guard", reason);
      if (!ok) {
        return { block: true, reason: "User declined the cdk deploy/destroy confirmation." };
      }
    } catch {
      // No interactive UI (headless run) — stay advisory: surface the
      // warning and let the command proceed rather than wedging the session.
      pi.sendMessage({ customType: "pi-checks", content: reason, display: true });
    }
  });

  pi.on("tool_result", async (event: any, ctx: any) => {
    if (event?.isError || !WRITE_TOOL.test(String(event?.toolName ?? ""))) return;
    const input = event?.input ?? {};
    const file = input.path ?? input.file_path ?? input.filePath ?? "";
    await run("post_code_hook.sh", file ? [String(file)] : [], ctx?.signal);
  });

  pi.on("agent_end", async (_event: any, ctx: any) => {
    await run("post_task_hook.sh", [], ctx?.signal);
    // Advisory LLM review — degrades silently when lgtmaybe is not installed.
    await run("lgtmaybe_review_hook.sh", [], ctx?.signal);
  });
}
