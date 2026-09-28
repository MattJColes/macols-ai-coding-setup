#!/usr/bin/env bash
#
# lib/omp-models.sh — Model and provider setup for Oh My Pi and plain pi.
#
# Sourced by lib/common.sh, which sets the colours and repo layout variables
# used here. Not meant to be executed directly.
# shellcheck disable=SC2034  # variables here are read by other modules/installers

# ── Oh My Pi model + provider setup ──────────────────────────────────────────
#
# omp resolves which model runs from two user-owned YAML files in its agent
# dir (plain pi has no equivalent, so this is omp-only):
#
#   models.yml  {"providers": {"<name>": {baseUrl, api, apiKey, models: [...]}}}
#   config.yml  {"modelRoles": {"default": "<provider>/<model-id>", ...}}
#
# `modelRoles.default` is the model omp starts a session on; `modelRoles.plan`
# is the one it plans with. Both take a `<provider>/<model-id>` selector, and
# the provider is either one omp already ships (anthropic, openai, zai, …) or
# one described in models.yml — an OpenAI-compatible endpoint such as vLLM,
# Ollama, LM Studio or LiteLLM.
#
# Both files are user-owned, so every write here merges: other providers,
# other roles and every unrelated setting survive. YAML comments do not — the
# files are re-serialised, which is also what omp itself does when it saves
# settings.
#
# Secrets never land in the config. An API key is written to a mode-600 file
# under $OMP_KEY_DIR and referenced from models.yml as `!cat '<path>'`, which
# omp resolves by running the command (a bare value is also read as an
# environment variable name before falling back to a literal).
OMP_KEY_DIR="$HOME/.config/macols"

# Bundled providers worth suggesting. Not a closed list — any provider id omp
# knows, or any name already in models.yml, is accepted at the prompt.
OMP_KNOWN_PROVIDERS="anthropic openai openai-codex zai google google-gemini-cli openrouter cerebras groq xai mistral deepseek moonshot github-copilot ollama"

# require_bun — the YAML readers/writers below run on Bun, which omp already
# needs as its runtime (ensure_cli pi installs it), so this adds no dependency.
require_bun() {
    if ! command -v bun &> /dev/null; then
        printf "${RED}bun is required for omp model setup but was not found.${NC}\n"
        return 1
    fi
}

# omp_model_role <agent_dir> <role> — print the model selector currently
# assigned to <role> in config.yml, or nothing when unset.
omp_model_role() {
    local f
    for f in "$1/config.yml" "$1/config.yaml"; do
        [ -f "$f" ] || continue
        OMP_FILE="$f" OMP_ROLE="$2" bun -e '
import { YAML } from "bun";
const doc = YAML.parse(await Bun.file(process.env.OMP_FILE).text()) || {};
const v = doc?.modelRoles?.[process.env.OMP_ROLE];
if (typeof v === "string" && v) process.stdout.write(v);
' 2>/dev/null
        return 0
    done
}

# omp_set_model_role <agent_dir> <role> <selector> — assign one model role in
# config.yml, leaving every other role and setting in place.
omp_set_model_role() {
    require_bun || return 1
    mkdir -p "$1"
    OMP_DIR="$1" OMP_ROLE="$2" OMP_SELECTOR="$3" bun -e '
import { YAML } from "bun";
import * as fs from "node:fs";
import * as path from "node:path";
const dir = process.env.OMP_DIR;
// omp reads config.yml first and falls back to config.yaml, so edit whichever
// one it would actually load.
const file = fs.existsSync(path.join(dir, "config.yml")) || !fs.existsSync(path.join(dir, "config.yaml"))
    ? path.join(dir, "config.yml")
    : path.join(dir, "config.yaml");
let doc = {};
if (fs.existsSync(file)) { try { doc = YAML.parse(fs.readFileSync(file, "utf8")) || {}; } catch (e) {} }
doc.modelRoles = { ...(doc.modelRoles ?? {}), [process.env.OMP_ROLE]: process.env.OMP_SELECTOR };
fs.writeFileSync(file, YAML.stringify(doc, null, 2) + "\n");
' || return 1
    printf "${GREEN}  ✓ modelRoles.%s = %s${NC}\n" "$2" "$3"
}

# omp_register_provider <agent_dir> — merge one provider into models.yml from
# the OMP_PROVIDER_* environment. Fields:
#   OMP_PROVIDER_NAME            provider id (required)
#   OMP_PROVIDER_BASE_URL        endpoint, required when a model is defined
#   OMP_PROVIDER_API             wire protocol, e.g. openai-completions
#   OMP_PROVIDER_KEY_REF         apiKey value (a `!cat …` command, an env var
#                                name or a literal); empty means `auth: none`
#   OMP_PROVIDER_MODEL_ID        model to add; empty registers the key alone,
#                                which is how a bundled provider is credentialed
#   OMP_PROVIDER_CONTEXT_WINDOW  optional context window in tokens
#   OMP_PROVIDER_REASONING       "true" to mark the model as a reasoning model
#   OMP_PROVIDER_FREE            "true" to record zero cost (self-hosted)
# An existing provider keeps its other models and settings; a model with the
# same id is replaced rather than duplicated, so re-runs converge.
omp_register_provider() {
    require_bun || return 1
    mkdir -p "$1"
    OMP_DIR="$1" bun -e '
import { YAML, JSONC } from "bun";
import * as fs from "node:fs";
import * as path from "node:path";
const env = process.env;
const dir = env.OMP_DIR;
const yml = path.join(dir, "models.yml");
const yaml = path.join(dir, "models.yaml");
const file = fs.existsSync(yml) || !fs.existsSync(yaml) ? yml : yaml;
let doc = {};
if (fs.existsSync(file)) {
    try { doc = YAML.parse(fs.readFileSync(file, "utf8")) || {}; } catch (e) {}
} else if (fs.existsSync(path.join(dir, "models.json"))) {
    // omp migrates a legacy models.json to models.yml on first load. Writing
    // models.yml here pre-empts that migration, so carry the old file over
    // instead of orphaning it.
    try { doc = JSONC.parse(fs.readFileSync(path.join(dir, "models.json"), "utf8")) || {}; } catch (e) {}
}
doc.providers ??= {};
const provider = (doc.providers[env.OMP_PROVIDER_NAME] ??= {});
if (env.OMP_PROVIDER_BASE_URL) provider.baseUrl = env.OMP_PROVIDER_BASE_URL;
if (env.OMP_PROVIDER_API) provider.api = env.OMP_PROVIDER_API;
if (env.OMP_PROVIDER_KEY_REF) {
    provider.apiKey = env.OMP_PROVIDER_KEY_REF;
    delete provider.auth;
} else if (env.OMP_PROVIDER_MODEL_ID && !provider.apiKey) {
    // Defining models without a key is only valid when auth is opted out of.
    provider.auth = "none";
}
if (env.OMP_PROVIDER_MODEL_ID) {
    const model = { id: env.OMP_PROVIDER_MODEL_ID };
    if (env.OMP_PROVIDER_REASONING === "true") model.reasoning = true;
    if (env.OMP_PROVIDER_CONTEXT_WINDOW) model.contextWindow = Number(env.OMP_PROVIDER_CONTEXT_WINDOW);
    if (env.OMP_PROVIDER_FREE === "true") model.cost = { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 };
    provider.models = [...(provider.models ?? []).filter(m => m?.id !== model.id), model];
}
fs.writeFileSync(file, YAML.stringify(doc, null, 2) + "\n");
' || return 1
    printf "${GREEN}  ✓ provider %s written${NC}\n" "$OMP_PROVIDER_NAME"
}

# omp_merge_models_config <agent_dir> <file> — merge the providers from a
# models.yml-shaped YAML or JSON file. The unattended path: point
# OMP_MODELS_CONFIG at a file and no questions are asked.
omp_merge_models_config() {
    require_bun || return 1
    [ -f "$2" ] || { printf "${RED}models config not found: %s${NC}\n" "$2"; return 1; }
    mkdir -p "$1"
    OMP_DIR="$1" OMP_SRC="$2" bun -e '
import { YAML, JSONC } from "bun";
import * as fs from "node:fs";
import * as path from "node:path";
const parse = (p) => (p.endsWith(".json") || p.endsWith(".jsonc") ? JSONC : YAML).parse(fs.readFileSync(p, "utf8")) || {};
const dir = process.env.OMP_DIR;
const yml = path.join(dir, "models.yml");
const yaml = path.join(dir, "models.yaml");
const file = fs.existsSync(yml) || !fs.existsSync(yaml) ? yml : yaml;
let doc = {};
if (fs.existsSync(file)) { try { doc = YAML.parse(fs.readFileSync(file, "utf8")) || {}; } catch (e) {} }
const src = parse(process.env.OMP_SRC);
doc.providers = { ...(doc.providers ?? {}), ...(src.providers ?? {}) };
fs.writeFileSync(file, YAML.stringify(doc, null, 2) + "\n");
' || return 1
    printf "${GREEN}  ✓ providers from %s merged${NC}\n" "$2"
}

# ensure_omp_provider_key <provider> — ask for an API key and stash it in a
# mode-600 file, setting OMP_KEY_REF to the `!cat …` reference models.yml
# should carry. OMP_KEY_REF is left empty when the user skips (a provider that
# needs no key, or one already authenticated with `omp /login <provider>`).
# An existing key file short-circuits, so re-runs never re-prompt.
ensure_omp_provider_key() {
    OMP_KEY_REF=""
    local provider="$1" key_file="$OMP_KEY_DIR/omp-$1-api-key" key
    if [ -s "$key_file" ]; then
        printf "${GREEN}  ✓ API key already configured (%s)${NC}\n" "$key_file"
        OMP_KEY_REF="!cat '$key_file'"
        return 0
    fi
    read -rsp "$(printf "${YELLOW}  API key for %s (blank to skip — the endpoint needs none, or you use 'omp /login %s'): ${NC}" "$provider" "$provider")" key || true
    echo ""
    key="$(printf '%s' "$key" | tr -d '[:space:]')"
    [ -n "$key" ] || return 0
    mkdir -p "$OMP_KEY_DIR"
    (umask 077; printf '%s\n' "$key" > "$key_file")
    chmod 600 "$key_file"
    OMP_KEY_REF="!cat '$key_file'"
    printf "${GREEN}  ✓ key saved to %s (mode 600) and referenced, not inlined${NC}\n" "$key_file"
}

# omp_configure_role <agent_dir> <role> <label> — ask which model fills one
# role and write it. Three ways out: a provider omp already knows (or one
# configured earlier in this run), a new OpenAI-compatible endpoint, or skip.
# Every `read` ends in `|| true` because the installers run under `set -e`:
# EOF (Ctrl-D) at a prompt should fall through to that prompt's default —
# leaving the role as-is — not abort the install part-way through a provider.
omp_configure_role() {
    local dir="$1" role="$2" label="$3" current choice
    local provider model_id base_url api ctx reasoning
    current="$(omp_model_role "$dir" "$role")"

    printf "\n${CYAN}%s model (modelRoles.%s)${NC}\n" "$label" "$role"
    [ -n "$current" ] && printf "  currently: %s\n" "$current"
    printf "  1) A provider omp knows — %s\n" "$OMP_KNOWN_PROVIDERS"
    printf "  2) An OpenAI-compatible endpoint — vLLM, Ollama, LM Studio, LiteLLM, any gateway\n"
    printf "  3) Leave as-is (omp picks from its own priority list)\n"
    read -rp "$(printf "${YELLOW}  Choice [3]: ${NC}")" choice || true

    case "${choice:-3}" in
        1)
            read -rp "$(printf "${YELLOW}  Provider id: ${NC}")" provider || true
            [ -n "$provider" ] || { printf "${YELLOW}  ⚠ no provider given — %s left as-is${NC}\n" "$role"; return 0; }
            read -rp "$(printf "${YELLOW}  Model id (e.g. claude-opus-4-5, gpt-5.5, glm-5.2): ${NC}")" model_id || true
            [ -n "$model_id" ] || { printf "${YELLOW}  ⚠ no model given — %s left as-is${NC}\n" "$role"; return 0; }
            ensure_omp_provider_key "$provider"
            if [ -n "$OMP_KEY_REF" ]; then
                # Key only: the model itself comes from omp's bundled catalog,
                # so no baseUrl/models entry is needed (or wanted — it would
                # override the catalog's own definition).
                OMP_PROVIDER_NAME="$provider" OMP_PROVIDER_BASE_URL="" OMP_PROVIDER_API="" \
                OMP_PROVIDER_KEY_REF="$OMP_KEY_REF" OMP_PROVIDER_MODEL_ID="" \
                OMP_PROVIDER_CONTEXT_WINDOW="" OMP_PROVIDER_REASONING="" OMP_PROVIDER_FREE="" \
                    omp_register_provider "$dir" || return 1
            fi
            ;;
        2)
            read -rp "$(printf "${YELLOW}  Name for this provider (e.g. vllm-lan, ollama-local): ${NC}")" provider || true
            [ -n "$provider" ] || { printf "${YELLOW}  ⚠ no name given — %s left as-is${NC}\n" "$role"; return 0; }
            read -rp "$(printf "${YELLOW}  Base URL (vLLM http://host:8000/v1, Ollama http://localhost:11434/v1, LM Studio http://localhost:1234/v1): ${NC}")" base_url || true
            [ -n "$base_url" ] || { printf "${YELLOW}  ⚠ no base URL given — %s left as-is${NC}\n" "$role"; return 0; }
            read -rp "$(printf "${YELLOW}  Wire protocol [openai-completions]: ${NC}")" api || true
            read -rp "$(printf "${YELLOW}  Model id (as the endpoint reports it, e.g. unsloth/Qwen3.8-27B-NVFP4): ${NC}")" model_id || true
            [ -n "$model_id" ] || { printf "${YELLOW}  ⚠ no model given — %s left as-is${NC}\n" "$role"; return 0; }
            read -rp "$(printf "${YELLOW}  Context window in tokens (blank to leave to omp): ${NC}")" ctx || true
            read -rp "$(printf "${YELLOW}  Is it a reasoning model? [y/N]: ${NC}")" reasoning || true
            ensure_omp_provider_key "$provider"
            case "$reasoning" in [Yy]*) reasoning=true ;; *) reasoning=false ;; esac
            OMP_PROVIDER_NAME="$provider" OMP_PROVIDER_BASE_URL="$base_url" \
            OMP_PROVIDER_API="${api:-openai-completions}" OMP_PROVIDER_KEY_REF="$OMP_KEY_REF" \
            OMP_PROVIDER_MODEL_ID="$model_id" OMP_PROVIDER_CONTEXT_WINDOW="$ctx" \
            OMP_PROVIDER_REASONING="$reasoning" OMP_PROVIDER_FREE="true" \
                omp_register_provider "$dir" || return 1
            printf "${YELLOW}  ⚠ cost recorded as 0 — edit models.yml if this endpoint bills you${NC}\n"
            ;;
        *)
            printf "  left as-is\n"
            return 0
            ;;
    esac

    omp_set_model_role "$dir" "$role" "$provider/$model_id"
}

# configure_pi_lan_models <pi_dir> <omp_dir> — register the shared LAN model.
configure_pi_lan_models() {
    require_bun || return 1
    PI_MODELS_DIR="$1" OMP_MODELS_DIR="$2" bun -e '
import { YAML, JSONC } from "bun";
import * as fs from "node:fs";
import * as path from "node:path";
const oldId = "unsloth/Qwen3.8-27B-NVFP4";
const id = "ukisai/Swift-Qwen3.8-27B-NVFP4";
const yamlFile = (dir, stem) => {
    const yml = path.join(dir, stem + ".yml");
    const yaml = path.join(dir, stem + ".yaml");
    return fs.existsSync(yml) || !fs.existsSync(yaml) ? yml : yaml;
};
const read = file => {
    if (!fs.existsSync(file)) return {};
    const text = fs.readFileSync(file, "utf8");
    const doc = file.endsWith(".json") ? JSONC.parse(text) : YAML.parse(text);
    if (!doc || typeof doc !== "object" || Array.isArray(doc)) throw new Error(`Invalid configuration object: ${file}`);
    return doc;
};
const writes = [];
for (const [dir, omp] of [[process.env.PI_MODELS_DIR, false], [process.env.OMP_MODELS_DIR, true]]) {
    const file = omp ? yamlFile(dir, "models") : path.join(dir, "models.json");
    const legacy = path.join(dir, "models.json");
    const doc = read(omp && !fs.existsSync(file) && fs.existsSync(legacy) ? legacy : file);
    doc.providers ??= {};
    if (typeof doc.providers !== "object" || Array.isArray(doc.providers)) throw new Error(`Invalid providers: ${file}`);
    const provider = (doc.providers["vllm-lan"] ??= {});
    if (typeof provider !== "object" || Array.isArray(provider)) throw new Error(`Invalid vllm-lan provider: ${file}`);
    Object.assign(provider, { baseUrl: "http://exodus:8000/v1", api: "openai-completions" });
    if (omp) {
        provider.auth = "none";
        delete provider.apiKey;
    } else {
        // Pi requires a non-empty apiKey even for unauthenticated endpoints.
        provider.apiKey = "unused";
        delete provider.auth;
    }
    provider.models = [...(provider.models ?? []).filter(m => m.id !== oldId && m.id !== id), {
        id, reasoning: true, input: ["text", "image"], contextWindow: 262144,
        cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 }
    }];
    writes.push([file, doc, omp]);
    const settingsFile = omp ? yamlFile(dir, "config") : path.join(dir, "settings.json");
    const settings = read(settingsFile);
    let changed = false;
    if (omp) {
        if (settings.modelRoles != null && (typeof settings.modelRoles !== "object" || Array.isArray(settings.modelRoles))) {
            throw new Error(`Invalid modelRoles: ${settingsFile}`);
        }
        for (const [role, model] of Object.entries(settings.modelRoles ?? {})) {
            if (model === `vllm-lan/${oldId}`) {
                settings.modelRoles[role] = `vllm-lan/${id}`;
                changed = true;
            }
        }
        settings.modelRoles = {
            ...settings.modelRoles,
            default: `vllm-lan/${id}:medium`, vision: `vllm-lan/${id}:medium`, plan: `vllm-lan/${id}:xhigh`
        };
        changed = true;
    } else if (settings.defaultProvider === "vllm-lan" && settings.defaultModel === oldId) {
        settings.defaultModel = id;
        changed = true;
    }
    if (changed) writes.push([settingsFile, settings, omp]);
}
// Parse all user files before writing so malformed config is never replaced.
for (const [file, doc, omp] of writes) {
    fs.mkdirSync(path.dirname(file), { recursive: true });
    fs.writeFileSync(file, (omp ? YAML.stringify(doc, null, 2) : JSON.stringify(doc, null, 2)) + "\n");
}
' || return 1
    printf "${GREEN}✓ Swift Qwen LAN model registered for pi and omp${NC}\n"
}

# configure_omp_models <agent_dir> — set omp's default and planning models.
#
# Interactive by default. Unattended callers get the same result without
# questions from OMP_MODELS_CONFIG (a models.yml-shaped YAML/JSON file of
# providers) plus OMP_DEFAULT_MODEL / OMP_PLAN_MODEL (`<provider>/<model-id>`
# selectors). Set OMP_RECONFIGURE_MODELS=true to re-ask once the roles are
# already assigned — that is what `--models-only` does.
configure_omp_models() {
    local dir="$1"
    require_bun || return 1

    if [ -n "${OMP_MODELS_CONFIG:-}" ]; then
        omp_merge_models_config "$dir" "$OMP_MODELS_CONFIG" || return 1
    fi
    if [ -n "${OMP_DEFAULT_MODEL:-}" ]; then
        omp_set_model_role "$dir" default "$OMP_DEFAULT_MODEL" || return 1
    fi
    if [ -n "${OMP_PLAN_MODEL:-}" ]; then
        omp_set_model_role "$dir" plan "$OMP_PLAN_MODEL" || return 1
    fi
    # Anything supplied by environment is the whole answer — don't then ask.
    if [ -n "${OMP_MODELS_CONFIG:-}${OMP_DEFAULT_MODEL:-}${OMP_PLAN_MODEL:-}" ]; then
        return 0
    fi

    if [ "${OMP_RECONFIGURE_MODELS:-false}" != true ] && [ -n "$(omp_model_role "$dir" default)" ]; then
        printf "${GREEN}✓ omp models already configured (%s/config.yml) — re-run with --models-only to change them${NC}\n" "$dir"
        return 0
    fi
    if [ ! -t 0 ]; then
        printf "${YELLOW}⚠ Non-interactive install — set OMP_DEFAULT_MODEL / OMP_PLAN_MODEL (and OMP_MODELS_CONFIG for a custom endpoint) to configure omp models${NC}\n"
        return 0
    fi

    printf "${BLUE}Oh My Pi model setup — which model omp runs on, and which it plans with.${NC}\n"
    printf "${BLUE}Both are stored in %s (providers) and %s (roles).${NC}\n" "$dir/models.yml" "$dir/config.yml"
    omp_configure_role "$dir" default "Default" || return 1
    omp_configure_role "$dir" plan "Planning" || return 1
}
