#!/usr/bin/env zsh
emulate -L zsh
setopt local_options extended_glob no_unset pipe_fail

FEFO_ROOT=${0:A:h:h}
PASS=0
FAIL=0

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

HOME=$tmp/home; mkdir -p "$HOME/.config" "$HOME/.cache" "$HOME/.local/share" "$HOME/.local/bin"
export HOME
export XDG_CONFIG_HOME=$HOME/.config
export XDG_CACHE_HOME=$HOME/.cache
export XDG_DATA_HOME=$HOME/.local/share
export FEFO_SKIP_UPDATE_CHECK=1
export FEFO_YES=1
export FEFO_HOME=$FEFO_ROOT
FEFO_TEST_LOG=$tmp/codegraph.log
: > "$FEFO_TEST_LOG"
export FEFO_TEST_LOG
SHIMS=$FEFO_ROOT/tests/shims
export PATH=$SHIMS:$FEFO_ROOT/bin:$PATH

mkrepo() {
  local d=$1 kind=$2
  rm -rf "$d"; mkdir -p "$d"
  git -C "$d" init -q >/dev/null 2>&1
  git -C "$d" config user.email t@t >/dev/null 2>&1
  git -C "$d" config user.name t >/dev/null 2>&1
  case "$kind" in
    django) printf '%s\n' '#!/usr/bin/env python' > "$d/manage.py"; printf 'django\n' > "$d/requirements.txt" ;;
    next) printf '%s\n' '{"scripts":{"test":"vitest","lint":"eslint .","build":"next build"},"dependencies":{"next":"16","react":"19"}}' > "$d/package.json" ;;
    flutter) printf '%s\n' 'name: app' 'dependencies:' '  flutter:' '    sdk: flutter' > "$d/pubspec.yaml" ;;
    docs) printf '%s\n' '# docs' > "$d/README.md" ;;
  esac
  git -C "$d" add -A >/dev/null 2>&1
  git -C "$d" commit -q -m init >/dev/null 2>&1
}

newws() { rm -rf "$1"; mkdir -p "$1"; }

t() {
  local name=$1; shift
  local cmd="$*"
  if eval "$cmd"; then
    ((PASS++)); print "PASS $name"
  else
    ((FAIL++)); print "FAIL $name" >&2
  fi
}

REPOS=$tmp/repos
mkdir -p "$REPOS"
mkrepo "$REPOS/api" django
mkrepo "$REPOS/web" next
mkrepo "$REPOS/flutter" flutter
mkrepo "$REPOS/docs" docs

# zsh -n all owned zsh files
for f in $FEFO_ROOT/lib/*.zsh(N) $FEFO_ROOT/bin/fefo $FEFO_ROOT/install.zsh $FEFO_ROOT/share/fefo.zsh; do
  if [[ -f "$f" ]]; then
    if zsh -n "$f"; then
      ((PASS++)); print "PASS zsh -n ${f#$FEFO_ROOT/}"
    else
      ((FAIL++)); print "FAIL zsh -n ${f#$FEFO_ROOT/}" >&2
    fi
  else
    ((FAIL++)); print "FAIL missing $f" >&2
  fi
done

# FEFO's own files: tracked + untracked-not-ignored (a template checkout also holds ignored local files)
if git -C "$FEFO_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  scan=(${(f)"$(git -C "$FEFO_ROOT" ls-files --cached --others --exclude-standard)"})
else
  scan=(${(f)"$(cd "$FEFO_ROOT" && find . -type f -not -path './.git/*')"})
fi
scan=(${scan:#(tests/*|./tests/*)})

# no python/jq/node calls outside tests (except vault-graph.mjs and graph.zsh codegraph-node line)
bad=$(cd "$FEFO_ROOT" && grep -n -E 'python3| jq |(^|[^_a-zA-Z])node ' -- ${scan:#*vault-graph.mjs} 2>/dev/null | grep -v 'graph.zsh.*codegraph.*node' || true)
if [[ -z "$bad" ]]; then
  ((PASS++)); print "PASS no python/jq/node calls"
else
  ((FAIL++)); print "FAIL no python/jq/node calls" >&2
  print -r -- "$bad" >&2
fi

# no tool-markup garbage anywhere
lt='<'; pipe='|'
if (cd "$FEFO_ROOT" && grep -I -F -q -e "${lt}${pipe}" -- "${scan[@]}" 2>/dev/null); then
  ((FAIL++)); print "FAIL no <| garbage" >&2
else
  ((PASS++)); print "PASS no <| garbage"
fi

# no stray files in lib/
t "lib has only known files" '[[ -z "$(ls $FEFO_ROOT/lib | grep -v -E "^(core|manifest|scan|gen|cmd|graph|agents)\.zsh$|^vault-graph\.mjs$")" ]]'

# init scan cheap
ws=$tmp/ws_scan; newws "$ws"
mkrepo "$ws/api" django
mkrepo "$ws/web" next
cd "$ws"
t "init scan cheap" 'fefo init --name "ScanWS" --cheap --no-index --yes >/dev/null 2>&1'
t "manifest has api" 'grep -q "api" .fefo/workspace.zsh'
t "manifest has web" 'grep -q "web" .fefo/workspace.zsh'
t "opencode no default_agent" '! grep -q "default_agent" opencode.json'

# manifest round-trip stable
ws=$tmp/ws_rt; newws "$ws"
mkrepo "$ws/api" django
cd "$ws"
t "init rt" 'fefo init --name RT --cheap --no-index --yes >/dev/null 2>&1'
cp .fefo/workspace.zsh "$tmp/before.manifest"
t "sync rt" 'fefo sync >/dev/null 2>&1'
t "manifest stable" 'cmp -s "$tmp/before.manifest" .fefo/workspace.zsh'

# opencode browse on/off
ws=$tmp/ws_br; newws "$ws"
mkrepo "$ws/api" django
cd "$ws"
t "init browse on" 'fefo init --name B --cheap --no-index --yes >/dev/null 2>&1'
t "opencode has codegraph server" 'grep -q "\"codegraph\"" opencode.json'
t "opencode has browse" 'grep -q "browse" opencode.json'

ws=$tmp/ws_nobr; newws "$ws"
mkrepo "$ws/api" django
cd "$ws"
t "init no-browse" 'fefo init --name NB --cheap --no-browse --no-index --yes >/dev/null 2>&1'
t "opencode no browse" '! grep -q "browse" opencode.json'

# AGENTS placeholders cheap/default
ws=$tmp/ws_ch; newws "$ws"
mkrepo "$ws/api" django
cd "$ws"
t "init cheap agents" 'fefo init --name CA --cheap --no-index --yes >/dev/null 2>&1'
t "cheap text" 'grep -qi "cheap" AGENTS.md'

ws=$tmp/ws_def; newws "$ws"
mkrepo "$ws/api" django
cd "$ws"
t "init default agents" 'fefo init --name DA --model opencode-go/beam-free --no-index --yes >/dev/null 2>&1'
t "default text" 'grep -qi "default" AGENTS.md'

# sync idempotent
ws=$tmp/ws_sync; newws "$ws"
mkrepo "$ws/api" django
cd "$ws"
fefo init --name S --cheap --no-index --yes >/dev/null 2>&1
find . -type f -not -path './.git/*' | sort | xargs sha256sum > "$tmp/before_sync.txt" 2>/dev/null
fefo sync >/dev/null 2>&1
find . -type f -not -path './.git/*' | sort | xargs sha256sum > "$tmp/after_sync.txt" 2>/dev/null
t "sync idempotent" 'cmp -s "$tmp/before_sync.txt" "$tmp/after_sync.txt"'

# --check drift exit 3
ws=$tmp/ws_chk; newws "$ws"
mkrepo "$ws/api" django
cd "$ws"
fefo init --name CHK --cheap --no-index --yes >/dev/null 2>&1
t "sync check drift" 'printf x >> opencode.json; fefo sync --check >/dev/null 2>&1; [[ $? -eq 3 ]]'

# add/remove repo
ws=$tmp/ws_ar; newws "$ws"
cd "$ws"
t "init addrepo base" 'fefo init --name AR --repo "$REPOS/api" --cheap --no-index --yes >/dev/null 2>&1'
t "add web" 'fefo add "$REPOS/web" >/dev/null 2>&1'
t "manifest has web after add" 'grep -q "web" .fefo/workspace.zsh'
t "remove web" 'fefo remove web >/dev/null 2>&1'
t "manifest no web after remove" '! grep -q "web" .fefo/workspace.zsh'

# codegraph=off
ws=$tmp/ws_cgoff; newws "$ws"
cd "$ws"
fefo init --name CG --repo "$REPOS/api" --cheap --no-index --yes >/dev/null 2>&1
t "add web no-cg" 'fefo add "$REPOS/web" --no-codegraph >/dev/null 2>&1'
t "cg off readme" 'grep -qi "web" codegraph/README.md'

# mcp add local/remote/list/remove
ws=$tmp/ws_mcp; newws "$ws"
cd "$ws"
fefo init --name M --repo "$REPOS/api" --cheap --no-index --yes >/dev/null 2>&1
t "mcp add local" 'fefo mcp add pg -- echo hi >/dev/null 2>&1'
t "mcp list" '[[ $(fefo mcp list 2>&1) == *pg* ]]'
t "opencode has pg" 'grep -q "pg" opencode.json'
t "mcp add remote" 'fefo mcp add plane --url https://plane.example/mcp --header "Authorization=Bearer {env:PLANE_TOKEN}" >/dev/null 2>&1'
t "opencode has plane" 'grep -q "plane" opencode.json'
t "mcp remove pg" 'fefo mcp remove pg >/dev/null 2>&1'
t "opencode no pg" '! grep -q "\"pg\"" opencode.json'

# model cheap/default/fallback
ws=$tmp/ws_model; newws "$ws"
mkrepo "$ws/api" django
cd "$ws"
fefo init --name MD --cheap --no-index --yes >/dev/null 2>&1
t "model show" 'fefo model show >/dev/null 2>&1'
t "model cheap" 'fefo model cheap >/dev/null 2>&1'
t "model fallback auto" 'fefo model fallback auto >/dev/null 2>&1'
t "model fallback id" 'fefo model fallback opencode-go/beam-free >/dev/null 2>&1'

# handoff
ws=$tmp/ws_handoff; newws "$ws"
cd "$ws"
export FEFO_HANDOFF=$tmp/handoff
fefo init --name "Hand$$" --repo "$REPOS/api" --cheap --no-index --yes >/dev/null 2>&1
t "handoff create" 'fefo handoff t a b >/dev/null 2>&1'
t "handoff readme" '[[ -f $tmp/handoff/hand$$/t/README.md ]]'
t "handoff lanes" '[[ -d $tmp/handoff/hand$$/t/a && -d $tmp/handoff/hand$$/t/b ]]'
t "handoff status" '[[ $(fefo handoff t --status 2>&1) == *"| no |"* ]]'
unset FEFO_HANDOFF

# index args incl worktree seeding
ws=$tmp/ws_index; newws "$ws"
mkdir -p "$REPOS/api/.codegraph"
cd "$ws"
t "init index base" 'fefo init --name I --repo "$REPOS/api" --cheap --no-index --yes >/dev/null 2>&1'
: > "$FEFO_TEST_LOG"
t "index all" 'fefo index >/dev/null 2>&1'
t "index log has api" 'grep -q "api\|'"$REPOS/api"'" "$FEFO_TEST_LOG"'
# worktree
git -C "$REPOS/api" worktree add --detach "$tmp/wtapi" HEAD >/dev/null 2>&1
rm -rf "$tmp/wtapi/.codegraph"
: > "$FEFO_TEST_LOG"
t "index worktree" 'fefo index "api=$tmp/wtapi" >/dev/null 2>&1'
t "worktree seeded" '[[ -d "$tmp/wtapi/.codegraph" ]]'
t "index log has path" 'grep -q "$tmp/wtapi" "$FEFO_TEST_LOG"'

# doctor flags legacy
ws=$tmp/ws_doc; newws "$ws"
cd "$ws"
fefo init --name D --repo "$REPOS/api" --cheap --no-index --yes >/dev/null 2>&1
mkdir -p tools .claude .cursor .opencode/agents
printf '' > tools/fefo.py
printf '{}' > .fefo/workspace.json
printf '{}' > .mcp.json
printf '%s\n' '---' 'mode: primary' > .opencode/agents/fefo.md
printf '{\n  "default_agent": "fefo"\n}\n' > opencode.json
DOCOUT=$(fefo doctor 2>&1)
t "doctor flags fefo.py" 'print -r -- "$DOCOUT" | grep -q "tools/fefo.py"'
t "doctor flags workspace.json" 'print -r -- "$DOCOUT" | grep -q ".fefo/workspace.json"'
t "doctor flags default_agent" 'print -r -- "$DOCOUT" | grep -q "default_agent"'

# template checkout
ws=$tmp/ws_tpl; newws "$ws"
mkdir -p "$ws/.fefo"
touch "$ws/.fefo/template"
cp "$FEFO_ROOT/AGENTS.md" "$ws/AGENTS.md"
hash_before=$(sha256sum < "$ws/AGENTS.md")
cd "$ws"
t "init template" 'fefo init --name TPL --repo "$REPOS/api" --cheap --no-index --yes >/dev/null 2>&1'
hash_after=$(sha256sum < "$ws/AGENTS.md")
t "template AGENTS.md exists" '[[ -f .fefo/AGENTS.md ]]'
t "bootstrap AGENTS.md untouched" '[[ "$hash_before" == "$hash_after" ]]'

# graph --out
ws=$tmp/ws_graph; newws "$ws"
cd "$ws"
fefo init --name G --cheap --no-index --yes >/dev/null 2>&1
mkdir -p docs/vault
printf '%s\n' '# Sample' '' 'See [[other]] and [x](other.md)' > docs/vault/sample.md
printf '%s\n' '# Other' > docs/vault/other.md
t "graph out" 'fefo graph --out "$tmp/know-graph.html" >/dev/null 2>&1'
t "graph html has node id" 'grep -q "sample.md" "$tmp/know-graph.html"'
# vault graph json
t "index vault" 'fefo index --vault >/dev/null 2>&1'
t "vault graph json exists" '[[ -f docs/vault/.codegraph/vault-graph.json ]]'
t "vault graph json nodes" 'grep -q "\"nodes\"" docs/vault/.codegraph/vault-graph.json'
t "vault graph json edges" 'grep -q "\"edges\"" docs/vault/.codegraph/vault-graph.json'
t "vault graph json balanced" '[[ $(tr -cd "{" < docs/vault/.codegraph/vault-graph.json | wc -c) -eq $(tr -cd "}" < docs/vault/.codegraph/vault-graph.json | wc -c) ]]'

# agents --default copies agents
ws=$tmp/ws_agents2; newws "$ws"
cd "$ws"
fefo init --name A --repo "$REPOS/api" --cheap --no-index --yes >/dev/null 2>&1
t "agents default" 'fefo agents --default --force >/dev/null 2>&1'
t "agents copied" '[[ -n "$(ls .opencode/agents/*.md 2>/dev/null)" ]]'

# source share
t "source share" 'zsh -c "source $FEFO_ROOT/share/fefo.zsh; whence -w cmg bng doit" 2>&1 | grep -q "cmg"'

# Claude Code CLI basic support (§16)
ws=$tmp/ws_claude; newws "$ws"
mkrepo "$ws/api" django
cd "$ws"
# add a remote mcp with env var to test rewriting
fefo init --name CL --repo "$REPOS/api" --cheap --no-index --yes >/dev/null 2>&1
fefo mcp add plane --url https://plane.example/mcp --header "Authorization=Bearer {env:PLANE_TOKEN}" >/dev/null 2>&1
t "claude CLAUDE.md exists" '[[ -f CLAUDE.md ]]'
t "claude CLAUDE.md imports" 'grep -q "@AGENTS.md" CLAUDE.md && grep -q "@AGENTS.local.md" CLAUDE.md'
t "claude mcp json exists" '[[ -f .mcp.json ]]'
t "claude mcp same names" 'grep -q "codegraph" .mcp.json && grep -q "plane" .mcp.json'
t "claude mcp env rewritten" 'grep -q "\${PLANE_TOKEN}" .mcp.json'
t "claude skills exist" '[[ -f .claude/skills/codegraph/SKILL.md && -f .claude/skills/vault-search/SKILL.md ]]'

# --no-claude writes none
ws=$tmp/ws_noclaude; newws "$ws"
mkrepo "$ws/api" django
cd "$ws"
t "init no-claude" 'fefo init --name NCL --repo "$REPOS/api" --cheap --no-claude --no-index --yes >/dev/null 2>&1'
t "no-claude no CLAUDE.md" '[[ ! -f CLAUDE.md ]]'
t "no-claude no .mcp.json" '[[ ! -f .mcp.json ]]'
t "no-claude no skills" '[[ ! -f .claude/skills/codegraph/SKILL.md ]]'

# template checkout claude paths
ws=$tmp/ws_tplclaude; newws "$ws"
mkdir -p "$ws/.fefo"; touch "$ws/.fefo/template"
cp "$FEFO_ROOT/AGENTS.md" "$ws/AGENTS.md"
cd "$ws"
fefo init --name TPLC --repo "$REPOS/api" --cheap --no-index --yes >/dev/null 2>&1
t "template CLAUDE.md uses .fefo" 'grep -q "@.fefo/AGENTS.md" CLAUDE.md'

# doctor: claude wrappers not flagged; legacy .claude/agents flagged
ws=$tmp/ws_doc2; newws "$ws"
cd "$ws"
fefo init --name D2 --repo "$REPOS/api" --cheap --no-index --yes >/dev/null 2>&1
mkdir -p .claude/agents .cursor
DOCOUT2=$(fefo doctor 2>&1)
t "doctor flags .claude/agents" 'print -r -- "$DOCOUT2" | grep -q ".claude/agents"'
t "doctor flags .cursor" 'print -r -- "$DOCOUT2" | grep -q ".cursor"'
t "doctor does not flag CLAUDE.md" '! print -r -- "$DOCOUT2" | grep -q "CLAUDE.md"'

export FEFO_HANDOFF=$tmp/handoff

# 1 installer piped from a checkout must honor --dir
ins=$tmp/ins; rm -rf "$ins"
(cd "$FEFO_ROOT" && cat install.zsh | zsh -s -- --from "$FEFO_ROOT" --dir "$ins" --yes --cheap >/dev/null 2>&1)
t "install piped from checkout honors --dir" '[[ -f $ins/bin/fefo ]]'

# 2 gitignore without trailing newline
ws=$tmp/ws_gi; newws "$ws"; cd "$ws"
printf '/keep/' > .gitignore
fefo init --name GI --repo "$REPOS/api" --cheap --no-index --yes >/dev/null 2>&1
t "gitignore missing newline preserved" 'grep -Fxq "/keep/" .gitignore'
t "tracked .gitignore ends with newline" '[[ -z $(tail -c1 "$FEFO_ROOT/.gitignore") ]]'

# 3 doctor on un-migrated legacy dir
ws=$tmp/ws_leg; newws "$ws"; mkdir -p "$ws/.fefo" "$ws/.cursor"; touch "$ws/.fefo/workspace.json"
cd "$ws"
LEGOUT=$(fefo doctor 2>&1); LEGRC=$?
t "doctor flags legacy without workspace" 'print -r -- "$LEGOUT" | grep -q "workspace.json" && print -r -- "$LEGOUT" | grep -q "fefo init --force" && (( LEGRC == 1 ))'

# 4 claude off stale files
ws=$tmp/ws_coff; newws "$ws"; cd "$ws"
fefo init --name CO --repo "$REPOS/api" --cheap --no-index --no-claude --yes >/dev/null 2>&1
touch CLAUDE.md
COOUT=$(fefo doctor 2>&1)
t "doctor warns claude off stale file" 'print -r -- "$COOUT" | grep -q "claude off but CLAUDE.md exists" && [[ -f CLAUDE.md ]]'

# 5 model default exact id / non-TTY query
ws=$tmp/ws_md; newws "$ws"; cd "$ws"
fefo init --name MD --repo "$REPOS/api" --cheap --no-index --yes >/dev/null 2>&1
t "model default exact id" 'fefo model default opencode-go/beam-free </dev/null >/dev/null 2>&1 && fefo model show | grep -q "submodel: opencode-go/beam-free"'
t "model default unknown non-TTY fails" '! fefo model default zzz-nope </dev/null >/dev/null 2>&1'

# 6 model --global keeps other lines
mkdir -p "$XDG_CONFIG_HOME/fefo"
printf '%s\n' 'agents default' 'subagents default old/x' 'mine 1' > "$XDG_CONFIG_HOME/fefo/config.zsh"
fefo model cheap --global >/dev/null 2>&1
t "model --global keeps other lines" 'grep -qx "agents default" "$XDG_CONFIG_HOME/fefo/config.zsh" && grep -qx "mine 1" "$XDG_CONFIG_HOME/fefo/config.zsh" && grep -qx "subagents cheap" "$XDG_CONFIG_HOME/fefo/config.zsh" && ! grep -q "old/x" "$XDG_CONFIG_HOME/fefo/config.zsh"'

# 7 cosmetic: no-claude arm on its own line
t "cmd.zsh no-claude arm split" '! grep -q "no_claude=1; shift ;;.*\*)" "$FEFO_ROOT/lib/cmd.zsh"'

# 8 doctor ponytail from config, no opencode plugin list
ws=$tmp/ws_pt; newws "$ws"; cd "$ws"
fefo init --name PT --repo "$REPOS/api" --cheap --no-index --yes >/dev/null 2>&1
mkdir -p "$XDG_CONFIG_HOME/opencode"; print '{"plugin":["@dietrichgebert/ponytail"]}' > "$XDG_CONFIG_HOME/opencode/opencode.json"
PTOUT=$(fefo doctor 2>&1)
t "doctor ponytail from config" 'print -r -- "$PTOUT" | grep -q "✓ ponytail plugin"'
rm -rf "$XDG_CONFIG_HOME/opencode"
PTOUT=$(fefo doctor 2>&1)
t "doctor ponytail missing" 'print -r -- "$PTOUT" | grep -q "ponytail plugin missing"'
cd "$tmp"
# optional real opencode
if [[ -n "${FEFO_TEST_OPENCODE:-}" && -x "${FEFO_TEST_OPENCODE}" ]]; then
  ws=$tmp/ws_real; newws "$ws"
  mkrepo "$ws/api" django
  cd "$ws"
  fefo init --name R --cheap --no-index --yes >/dev/null 2>&1
  t "real opencode debug config" '(cd "$tmp/ws_real" && "$FEFO_TEST_OPENCODE" debug config) >/dev/null 2>&1'
fi

print "PASS=$PASS FAIL=$FAIL"
[[ $FAIL -eq 0 ]]
