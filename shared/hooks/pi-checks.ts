// pi-checks — wires the shared post-code / post-task check scripts into
// Oh My Pi (omp).
//
// omp has no settings.json hook array (hooks are extensions), so this small
// extension subscribes to the two events that mirror the PostToolUse + Stop
// hooks the other CLIs use:
//
//   tool_result  (write/edit tools)  -> hooks/post_code_hook.sh <file>
//   agent_end    (turn finished)     -> hooks/post_task_hook.sh
//
// Both scripts are advisory: they print findings, never block. Findings are
// surfaced back into the session via pi.sendMessage.
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
      const out = `${res.stdout || ""}`.trim();
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

  pi.on("tool_result", async (event: any, ctx: any) => {
    if (event?.isError || !WRITE_TOOL.test(String(event?.toolName ?? ""))) return;
    const input = event?.input ?? {};
    const file = input.path ?? input.file_path ?? input.filePath ?? "";
    await run("post_code_hook.sh", file ? [String(file)] : [], ctx?.signal);
  });

  pi.on("agent_end", async (_event: any, ctx: any) => {
    await run("post_task_hook.sh", [], ctx?.signal);
  });
}
