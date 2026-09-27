#!/usr/bin/env bash
#
# lib/personas.sh — Persona rendering: config/personas/<name>/SKILL.md into each tool's skills, agents and commands.
#
# Sourced by lib/common.sh, which sets the colours and repo layout variables
# used here. Not meant to be executed directly.
# shellcheck disable=SC2034  # variables here are read by other modules/installers

# ── Persona generation (single source: config/personas/<name>/SKILL.md) ───────
#
# One generator emits each tool's native format from the SAME persona body:
#   • skill mode   → Claude/OpenCode/Pi/Codex/ZCode Agent Skill (<name>/SKILL.md)
#   • command mode → ZCode slash command (<name>.md, description + argument-hint)
#   • agent mode   → Claude/OpenCode agent (<name>.md) or Codex agent (<name>.toml),
#                    only when frontmatter has agent: true
# (Codex custom prompts were removed upstream in favour of Agent Skills, so
# there is no prompt mode any more; command mode is ZCode's own slash-command
# shape.)
#
# A persona body may reference shared partials with {{include: _shared/<file>.md}}
# (paths relative to config/personas/). Partials are inlined before emission so
# every rendered form — skill, command or agent, any tool — is self-contained.
# Directories starting with "_" hold partials, not personas, and need no SKILL.md.
#
# Bundled files: a persona's references/ and scripts/ subdirectories are copied
# next to SKILL.md in every skill output. Single-file outputs (agents, ZCode
# commands) cannot carry folders, so their contents are inlined at the end of
# the body instead — always correct, whatever subset of forms is installed.
#
# tier: light|standard|deep maps to an effort setting where the target has one
# (Claude skill/agent `effort: low|medium|high`, Codex agent TOML
# `model_reasoning_effort`) and is dropped everywhere else. Never a model.
read -r -d '' PERSONA_GEN_JS <<'PERSONA_EOF' || true
const fs = require("fs"), path = require("path");
const mode = process.env.MODE, tool = process.env.TOOL;
const pdir = process.env.PERSONAS_DIR, tdir = process.env.TARGET_DIR;
// Appended to every persona body so agents and skills carry the same response
// rules as the assembled steering. Source: config/steering/response-format.md.
const RESPONSE_FORMAT = fs.readFileSync(process.env.RESPONSE_FORMAT_FILE, "utf8").trim();
const DEFAULT_TOOLS = ["Read", "Write", "Edit", "Bash", "Grep", "Glob"];
const BUNDLED_DIRS = ["references", "scripts"];
const EFFORT = { light: "low", standard: "medium", deep: "high" };

function effortOf(data, name) {
  if (data.tier === undefined) return undefined;
  if (!EFFORT[data.tier]) throw new Error(name + ": unknown tier '" + data.tier + "' (light|standard|deep)");
  return EFFORT[data.tier];
}

function listFiles(dir, rel) {
  let out = [];
  for (const e of fs.readdirSync(path.join(dir, rel), { withFileTypes: true }).sort((a, b) => a.name.localeCompare(b.name))) {
    const r = path.join(rel, e.name);
    if (e.isDirectory()) out = out.concat(listFiles(dir, r));
    else if (e.name !== ".DS_Store") out.push(r);
  }
  return out;
}

// Copy references/ and scripts/ beside a rendered SKILL.md (replacing any
// previous copy so removed files do not linger).
function copyBundled(srcDir, destDir) {
  for (const d of BUNDLED_DIRS) {
    const to = path.join(destDir, d);
    fs.rmSync(to, { recursive: true, force: true });
    const from = path.join(srcDir, d);
    if (fs.existsSync(from)) fs.cpSync(from, to, { recursive: true });
  }
}

// Inline references/ and scripts/ for single-file outputs.
function inlineBundled(srcDir) {
  const files = [];
  for (const d of BUNDLED_DIRS) if (fs.existsSync(path.join(srcDir, d))) files.push(...listFiles(srcDir, d));
  if (!files.length) return "";
  let o = "\n## Bundled files\n\nThe skill form ships these beside SKILL.md; they are inlined here because this form is a single file.\n";
  for (const f of files) {
    const c = fs.readFileSync(path.join(srcDir, f), "utf8").trimEnd();
    o += "\n### " + f + "\n\n" + (f.endsWith(".md") ? c : "```" + (path.extname(f).slice(1) || "text") + "\n" + c + "\n```") + "\n";
  }
  return o;
}

function applyIncludes(body) {
  return body.replace(/\{\{include:\s*([^}\s]+)\s*\}\}/g, (_, rel) => {
    const file = path.join(pdir, rel);
    if (!fs.existsSync(file)) throw new Error("include not found: " + rel);
    return fs.readFileSync(file, "utf8").trim();
  });
}

function parse(text) {
  const m = text.match(/^---\r?\n([\s\S]*?)\r?\n---\r?\n?([\s\S]*)$/);
  if (!m) return { data: {}, body: text };
  const data = {}; let cur = null;
  for (const line of m[1].split(/\r?\n/)) {
    const li = line.match(/^\s*-\s+(.*)$/);
    if (li && cur) { (data[cur] = data[cur] || []).push(li[1].trim()); continue; }
    const kv = line.match(/^([A-Za-z0-9_-]+):\s*(.*)$/);
    if (kv) {
      const k = kv[1], v = kv[2];
      if (v === "") { data[k] = []; cur = k; }
      else { data[k] = v === "true" ? true : v === "false" ? false : v; cur = null; }
    }
  }
  return { data, body: m[2] };
}

function fmList(key, items) {
  let o = key + ":\n";
  for (const i of items) o += "  - " + i + "\n";
  return o;
}

function writeDir(dir, name, content, srcDir) {
  const dest = path.join(dir, name);
  fs.mkdirSync(dest, { recursive: true });
  fs.writeFileSync(path.join(dest, "SKILL.md"), content);
  copyBundled(srcDir, dest);
}

let count = 0;
fs.mkdirSync(tdir, { recursive: true });
for (const name of fs.readdirSync(pdir).sort()) {
  const src = path.join(pdir, name, "SKILL.md");
  if (!fs.existsSync(src)) continue;
  const parsed = parse(fs.readFileSync(src, "utf8"));
  const data = parsed.data;
  const srcDir = path.join(pdir, name);
  const own = applyIncludes(parsed.body).trimEnd();
  const body = own + "\n\n" + RESPONSE_FORMAT + "\n";
  // Single-file forms carry the bundled files inline (see header comment),
  // ahead of the response-format block so that block stays last.
  const flatBody = () => own + "\n" + inlineBundled(srcDir) + "\n" + RESPONSE_FORMAT + "\n";
  const effort = effortOf(data, name);
  const pname = data.name || name;
  let label = name;

  if (mode === "command") {
    // ZCode slash command (~/.zcode/commands/<name>.md): the filename is the
    // command name; frontmatter carries description + argument-hint.
    let fm = "---\n";
    if (data.description) fm += "description: " + data.description + "\n";
    fm += "argument-hint: \"[task or context]\"\n";
    fm += "---\n";
    fs.writeFileSync(path.join(tdir, name + ".md"), fm + flatBody());
    console.log("  ✓ /" + name);
    count++;
  } else if (mode === "skill") {
    let fm = "---\n";
    if (tool === "codex") {
      // Codex Agent Skill (~/.codex/skills/<name>/SKILL.md): name + description
      // only — Codex ignores Claude-specific keys like allowed-tools.
      fm += "name: " + pname + "\n";
      if (data.description) fm += "description: " + data.description + "\n";
      fm += "---\n";
      writeDir(tdir, name, fm + body, srcDir);
    } else if (tool === "zcode") {
      // ZCode Agent Skill (~/.zcode/skills/<name>/SKILL.md): name +
      // description only — both are required or ZCode drops the skill, and
      // Claude-specific keys are best avoided.
      fm += "name: " + pname + "\n";
      if (data.description) fm += "description: " + data.description + "\n";
      fm += "---\n";
      writeDir(tdir, name, fm + body, srcDir);
    } else if (tool === "opencode") {
      if (data.name) fm += "name: " + data.name + "\n";
      if (data.description) fm += "description: " + data.description + "\n";
      fm += "compatibility: opencode\n---\n";
      writeDir(tdir, name, fm + body, srcDir);
    } else {
      // claudecode / pi Agent Skill.
      fm += "name: " + pname + "\n";
      if (data.description) fm += "description: " + data.description + "\n";
      if (data["allowed-tools"] && data["allowed-tools"].length) fm += fmList("allowed-tools", data["allowed-tools"]);
      if (tool === "claudecode" && data["user-invocable"] !== undefined) fm += "user-invocable: " + data["user-invocable"] + "\n";
      if (tool === "claudecode" && effort) fm += "effort: " + effort + "\n";
      fm += "---\n";
      writeDir(tdir, name, fm + body, srcDir);
      if (tool === "pi") label = "/skill:" + pname;
    }
    console.log("  ✓ " + label);
    count++;
  } else if (mode === "agent") {
    if (data.agent !== true) continue;
    let fm = "---\n";
    if (tool === "codex") {
      // Codex custom agent (~/.codex/agents/<name>.toml). Required fields:
      // name, description, developer_instructions. As for all rendered
      // agents, model is omitted — personas are model-agnostic and agents
      // inherit the parent session's model. Instructions use a TOML
      // literal block (no escape processing); fall back to an escaped basic
      // string if the body ever contains the ''' delimiter.
      const flat = flatBody();
      const b = flat.endsWith("\n") ? flat : flat + "\n";
      let doc = "name = " + JSON.stringify(pname) + "\n";
      doc += "description = " + JSON.stringify(data.description || "") + "\n";
      if (effort) doc += "model_reasoning_effort = " + JSON.stringify(effort) + "\n";
      if (b.includes("'''")) doc += "developer_instructions = " + JSON.stringify(b) + "\n";
      else doc += "developer_instructions = '''\n" + b + "'''\n";
      fs.writeFileSync(path.join(tdir, pname + ".toml"), doc);
    } else if (tool === "opencode") {
      // No model: (inherits the session's model) and no tools: map — the
      // boolean tool map is deprecated in OpenCode; the default toolset
      // applies, and per-tool restrictions belong in `permission` config.
      fm += "description: " + (data.description || "") + "\n---\n";
      fs.writeFileSync(path.join(tdir, name + ".md"), fm + flatBody());
    } else {
      // claudecode agent.
      const tools = (data["allowed-tools"] && data["allowed-tools"].length) ? data["allowed-tools"] : DEFAULT_TOOLS;
      fm += "name: " + pname + "\n";
      fm += "description: " + data.description + "\n";
      fm += "tools: " + tools.join(", ") + "\n";
      if (effort) fm += "effort: " + effort + "\n";
      fm += "---\n";
      fs.writeFileSync(path.join(tdir, pname + ".md"), fm + flatBody());
    }
    console.log("  ✓ " + pname);
    count++;
  }
}
// Retired or renamed personas: remove what an earlier install rendered so a
// stale copy cannot shadow a built-in (/review, /debug) or linger unused. Only
// files carrying the appended response-format block are ours to delete.
const RETIRED = ["coordinate", "linux", "ponytail", "review", "debug"];
const ours = (f) => fs.existsSync(f) && fs.readFileSync(f, "utf8").includes(RESPONSE_FORMAT.split("\n")[0]);
for (const r of RETIRED) {
  if (fs.existsSync(path.join(pdir, r, "SKILL.md"))) continue;
  const skill = path.join(tdir, r, "SKILL.md");
  if (mode === "skill" && ours(skill)) fs.rmSync(path.join(tdir, r), { recursive: true, force: true });
  for (const ext of [".md", ".toml"]) {
    const f = path.join(tdir, r + ext);
    if (mode !== "skill" && ours(f)) fs.rmSync(f);
  }
}
console.log("__COUNT__" + count);
PERSONA_EOF

# generate_personas <tool> <skill|command|agent> <target_dir>
# Prints a per-item checklist; sets PERSONA_COUNT to the number generated.
generate_personas() {
    require_node || return 1
    local out
    [ -f "$RESPONSE_FORMAT_FILE" ] || {
        printf "${RED}Response-format source missing (%s)${NC}\n" "$RESPONSE_FORMAT_FILE"; return 1
    }
    out=$(TOOL="$1" MODE="$2" PERSONAS_DIR="$PERSONAS_DIR" TARGET_DIR="$3" \
        RESPONSE_FORMAT_FILE="$RESPONSE_FORMAT_FILE" node -e "$PERSONA_GEN_JS")
    # PERSONA_COUNT is read by the installers that source this file.
    # shellcheck disable=SC2034
    PERSONA_COUNT=$(printf "%s" "$out" | sed -n 's/^__COUNT__//p')
    printf "%s\n" "$out" | grep -v '^__COUNT__'
}

# list_personas <claudecode|codex|opencode|pi|zcode>
list_personas() {
    local tool="$1" persona_name description marker
    printf "${BLUE}Available Personas:${NC}\n\n"
    for persona_dir in "$PERSONAS_DIR"/*; do
        [ -d "$persona_dir" ] || continue
        persona_name=$(basename "$persona_dir")
        [ -f "$persona_dir/SKILL.md" ] || continue
        description=$(grep -m1 "^description:" "$persona_dir/SKILL.md" | sed 's/^description: //')
        case "$tool" in
            codex)
                if grep -q "^agent:[[:space:]]*true" "$persona_dir/SKILL.md"; then marker="${CYAN}+agent${NC}"; else marker="      "; fi
                printf "  ${GREEN}/%-24s${NC} %b  %s\n" "$persona_name" "$marker" "$description" ;;
            pi)    printf "  ${GREEN}/skill:%-18s${NC} %s\n" "$persona_name" "$description" ;;
            zcode) printf "  ${GREEN}/%-24s${NC} %s\n" "$persona_name" "$description" ;;
            *)
                if grep -q "^agent:[[:space:]]*true" "$persona_dir/SKILL.md"; then marker="${CYAN}+agent${NC}"; else marker="      "; fi
                printf "  ${GREEN}%-25s${NC} %b  %s\n" "$persona_name" "$marker" "$description" ;;
        esac
    done
    echo ""
}
