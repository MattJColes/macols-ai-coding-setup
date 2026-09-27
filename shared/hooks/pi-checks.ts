// pi-checks — wires the shared check scripts into the Pi agents (plain `pi`
// and Oh My Pi `omp`).
//
// The Pi agents have no settings.json hook array (hooks are extensions), so
// this extension subscribes to the events that mirror the PreToolUse +
// PostToolUse + Stop hooks the other CLIs use:
//
//   tool_call            (bash tool)        -> hooks/pre_deploy_check.sh <cmd>
//                                              (cdk deploy/destroy guard; asks
//                                               via ctx.ui.confirm)
//   tool_result          (write/edit tools) -> hooks/post_code_hook.sh <file>
//                        findings are appended to the tool result content, so
//                        the model reads them with the edit (no steer, which
//                        would interrupt the run)
//   agent_before_settle  (pi)               -> hooks/post_task_hook.sh
//   session_stop         (omp)              -> hooks/post_task_hook.sh
//                        findings go back as one continuation. The hook only
//                        re-runs when the tree changed since its last run, and
//                        both agents cap continuations, so it cannot loop.
//
// install_pi.sh substitutes HOOKS_DIR (the repo's shared/hooks, referenced in
// place) and FLAVOUR (pi | omp).

const HOOKS_DIR = "__PI_HOOKS_DIR__";
const FLAVOUR: string = "__PI_FLAVOUR__";
const WRITE_TOOL = /(write|edit|create|patch|replace)/i;

export default function (pi: any) {
  const run = async (script: string, args: string[], signal?: AbortSignal): Promise<string> => {
    try {
      const res = await pi.exec("bash", [`${HOOKS_DIR}/${script}`, "--format", "text", ...args], {
        signal,
        timeout: 600_000,
      });
      return `${res.stdout || ""}`.trim();
    } catch {
      return ""; // advisory — a failing check script must never disrupt the session
    }
  };

  const editedPaths = (input: any): string[] => {
    const paths = [input?.path, input?.file_path, input?.filePath].filter(
      (p) => typeof p === "string" && p
    );
    for (const text of [input?.patch, input?.patchText, input?.input]) {
      if (typeof text !== "string") continue;
      for (const m of text.matchAll(/^\*\*\* (?:Add File|Update File|Move to): (.+)$/gm)) {
        paths.push(m[1].trim());
      }
    }
    return [...new Set(paths)];
  };

  pi.on("tool_call", async (event: any, ctx: any) => {
    if (!/^bash$/i.test(String(event?.toolName ?? ""))) return;
    const command = String(event?.input?.command ?? "");
    if (!command) return;

    let reason = "";
    try {
      const res = await pi.exec("bash", [`${HOOKS_DIR}/pre_deploy_check.sh`, command], {
        signal: ctx?.signal,
        timeout: 30_000,
      });
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
      // No interactive UI (headless run): block with the reason so the model
      // asks the user, rather than deploying unconfirmed.
      return { block: true, reason: `${reason} Ask the user to confirm before retrying.` };
    }
  });

  pi.on("tool_result", async (event: any, ctx: any) => {
    if (event?.isError || !WRITE_TOOL.test(String(event?.toolName ?? ""))) return;
    const files = editedPaths(event?.input ?? {});
    if (files.length === 0) return;
    const findings = await run("post_code_hook.sh", files, ctx?.signal);
    if (!findings) return;
    return { content: [...(event.content ?? []), { type: "text", text: findings }] };
  });

  const turnEnd = async (ctx: any): Promise<string> => run("post_task_hook.sh", [], ctx?.signal);

  if (FLAVOUR === "omp") {
    pi.on("session_stop", async (_event: any, ctx: any) => {
      const findings = await turnEnd(ctx);
      if (findings) return { continue: true, additionalContext: findings };
    });
  } else {
    pi.on("agent_before_settle", async (event: any, ctx: any) => {
      if (event?.outcome && event.outcome !== "completed") return;
      const findings = await turnEnd(ctx);
      if (!findings) return;
      return {
        entries: [{ type: "custom_message", customType: "pi-checks", content: findings, display: true }],
        continue: true,
      };
    });
  }
}
