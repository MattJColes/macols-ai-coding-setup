#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
FIXTURE="$(mktemp -d "${TMPDIR:-/tmp}/pi-models.XXXXXX")"
FIXTURE="$(cd "$FIXTURE" && pwd)"
trap 'rm -rf "$FIXTURE"' EXIT
TEST_HOME="$FIXTURE/user's home"
mkdir -p "$TEST_HOME"

TEST_HOME="$TEST_HOME" bun -e '
import { mkdirSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { YAML } from "bun";
const home = process.env.TEST_HOME;
for (const agent of [".pi", ".omp"]) {
    const dir = join(home, agent, "agent");
    mkdirSync(dir, { recursive: true });
    const doc = { providers: {
        other: { baseUrl: "http://other/v1" },
        "vllm-lan": { apiKey: "!cat /missing-key", models: [{ id: "unsloth/Qwen3.8-27B-NVFP4" }, { id: "keep-me" }] }
    }};
    writeFileSync(join(dir, agent === ".pi" ? "models.json" : "models.yaml"),
        agent === ".pi" ? JSON.stringify(doc) : YAML.stringify(doc));
}
writeFileSync(join(home, ".pi/agent/settings.json"), JSON.stringify({
    defaultProvider: "vllm-lan", defaultModel: "unsloth/Qwen3.8-27B-NVFP4", theme: "keep"
}));
writeFileSync(join(home, ".omp/agent/config.yaml"), YAML.stringify({
    modelRoles: { default: "other/default", vision: "other/vision", plan: "other/model", slow: "other/slow" }, theme: "keep"
}));
'

run_models() {
    env HOME="$TEST_HOME" PI_CODING_AGENT_DIR="$TEST_HOME/.omp/agent" \
        OMP_DEFAULT_MODEL= OMP_PLAN_MODEL= OMP_MODELS_CONFIG= \
        bash "$REPO_DIR/install_pi.sh" --models-only </dev/null >"$FIXTURE/install.log" 2>&1
}
run_models
cp -R "$TEST_HOME" "$FIXTURE/once"
run_models
diff -r "$FIXTURE/once" "$TEST_HOME"

TEST_HOME="$TEST_HOME" bun -e '
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { YAML } from "bun";
const home = process.env.TEST_HOME;
const id = "ukisai/Swift-Qwen3.8-27B-NVFP4";
for (const file of [".pi/agent/models.json", ".omp/agent/models.yaml"]) {
    const doc = YAML.parse(readFileSync(`${home}/${file}`, "utf8"));
    const provider = doc.providers["vllm-lan"];
    assert.equal(provider.baseUrl, "http://exodus:8000/v1");
    assert.equal(provider.api, "openai-completions");
    assert.equal(provider.models.length, 2);
    assert.deepEqual(provider.models.find(m => m.id === id), {
        id, reasoning: true, input: ["text", "image"], contextWindow: 262144,
        cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 }
    });
    assert.equal(doc.providers.other.baseUrl, "http://other/v1");
    if (file.endsWith(".yaml")) {
        assert.equal(provider.auth, "none");
        assert.equal(provider.apiKey, undefined);
    } else {
        assert.equal(provider.apiKey, "unused");
    }
}
const pi = JSON.parse(readFileSync(`${home}/.pi/agent/settings.json`, "utf8"));
assert.equal(pi.defaultModel, id);
assert.equal(pi.theme, "keep");
const omp = YAML.parse(readFileSync(`${home}/.omp/agent/config.yaml`, "utf8"));
assert.equal(omp.modelRoles.default, `vllm-lan/${id}`);
assert.equal(omp.modelRoles.vision, `vllm-lan/${id}`);
assert.equal(omp.modelRoles.plan, `vllm-lan/${id}:xhigh`);
assert.equal(omp.modelRoles.slow, "other/slow");
assert.equal(omp.theme, "keep");
'

# Optional model setup fails visibly and leaves both agents untouched.
printf '{bad json' > "$TEST_HOME/.pi/agent/models.json"
cp -R "$TEST_HOME" "$FIXTURE/bad"
run_models
grep -q 'LAN model setup failed' "$FIXTURE/install.log"
diff -r "$FIXTURE/bad" "$TEST_HOME"

# An invalid omp file must not cause the already-parsed pi file to be written.
cp "$FIXTURE/once/.pi/agent/models.json" "$TEST_HOME/.pi/agent/models.json"
printf 'providers: [' > "$TEST_HOME/.omp/agent/models.yaml"
cp -R "$TEST_HOME" "$FIXTURE/bad-omp"
run_models
grep -q 'LAN model setup failed' "$FIXTURE/install.log"
diff -r "$FIXTURE/bad-omp" "$TEST_HOME"

# Carry legacy omp JSON forward when no YAML file exists.
TEST_HOME="$FIXTURE/legacy"
mkdir -p "$TEST_HOME/.omp/agent"
cp "$FIXTURE/once/.pi/agent/models.json" "$TEST_HOME/.omp/agent/models.json"
run_models
test -f "$TEST_HOME/.omp/agent/models.yml"
grep -q 'keep-me' "$TEST_HOME/.omp/agent/models.yml"
TEST_HOME="$TEST_HOME" bun -e '
import assert from "node:assert/strict";
import { YAML } from "bun";
const config = YAML.parse(await Bun.file(`${process.env.TEST_HOME}/.omp/agent/config.yml`).text());
assert.equal(config.modelRoles.default, "vllm-lan/ukisai/Swift-Qwen3.8-27B-NVFP4");
assert.equal(config.modelRoles.vision, config.modelRoles.default);
assert.equal(config.modelRoles.plan, `${config.modelRoles.default}:xhigh`);
'

# Verify the component guards without touching the real home.
mkdir -p "$FIXTURE/empty" "$FIXTURE/project"
for mode in '--models-only --no-models' '--models-only --project'; do
    (
        cd "$FIXTURE/project"
        # shellcheck disable=SC2086
        env HOME="$FIXTURE/empty" PI_CODING_AGENT_DIR="$FIXTURE/empty/.omp/agent" \
            bash "$REPO_DIR/install_pi.sh" $mode </dev/null >"$FIXTURE/skip.log"
    )
    [ ! -e "$FIXTURE/empty/.pi" ] && [ ! -e "$FIXTURE/empty/.omp" ]
done
echo 'PASS: Pi LAN model migration, idempotency, keyless authentication, malformed config and skip flags'
