# macols-configs — agent notes

Shell installers here run from various working directories and `cd` around
(e.g. `cd /tmp` before downloading a tarball). Path resolution must not depend
on the current working directory.

## Rule: resolve script paths from `${BASH_SOURCE[0]}`, never `$0` after a `cd`

Set an absolute script dir once at the top of every installer and derive all
sibling/parent paths from it:

```sh
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"   # absolute, cwd-independent
CONFIGS_ROOT="$(dirname "$SCRIPT_DIR")"
"$CONFIGS_ROOT/install.sh"
```

Do **not** re-resolve later with `"$(cd "$(dirname "$0")/.." && pwd)"`. `$0` is
relative to the *current* cwd, so after an earlier `cd /tmp` it resolves against
`/tmp`: `dirname` → `/tmp`, `/tmp/..` → `/`, and the path becomes `//install.sh`
(No such file). This exact regression bit `Terminal/install_ubuntu26.sh` — keep
it fixed.
