#!/usr/bin/env zsh
# tests/graph.zsh — FEFO graph over code vault + hand-written notes
emulate -L zsh
setopt local_options extended_glob no_unset pipe_fail

FEFO_ROOT=${0:A:h:h}
export FEFO_HOME=$FEFO_ROOT
FEFO=$FEFO_ROOT/bin/fefo
PASS=0
FAIL=0

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
HOME=$tmp/home
mkdir -p "$HOME/.config" "$HOME/.cache"
export HOME XDG_CONFIG_HOME=$HOME/.config XDG_CACHE_HOME=$HOME/.cache
export FEFO_YES=1 FEFO_SKIP_UPDATE_CHECK=1
export PATH=$FEFO_ROOT/bin:$PATH

t() {
  local name=$1; shift
  if eval "$*"; then ((PASS++)); print "PASS $name"
  else ((FAIL++)); print "FAIL $name" >&2; fi
}

WS=$tmp/ws
mkdir -p "$WS"
cd "$WS"
"$FEFO" init --name GraphTest --cheap --yes >/dev/null 2>&1 || { print FAIL init >&2; exit 1; }

# two hand-written notes
printf '%s\n' '# Note One' '' 'Durable fact about widgets.' > docs/vault/note1.md
printf '%s\n' '# Note Two' '' 'See [[note1]] for the widget rule.' > docs/vault/note2.md

# fake generated module note: symbol, route, wikilink and recent commit
mkdir -p docs/vault/fakerepo-vault/modules
cat > docs/vault/fakerepo-vault/modules/mymod.md <<'EOF'
# mymod
Role: test module

## Files
- fakerepo/models.py

## Definitions
Thing — fakerepo/models.py:12

## Routes
- /things → views.thing_list

## Imports from
- [[modules/other]] (1)

## Used by
- Thing → fakerepo/other.py

## Recent
- abc1234 2026-11-27 fix thing — mymod(1)
EOF

"$FEFO" vault --force >/dev/null 2>&1
G=docs/vault/graph.json
j=$(<"$G")

t 'graph.json exists' '[[ -f $G ]]'
t 'symbol node' '[[ $j == *"symbol:Thing:fakerepo/models.py:12"* ]]'
t 'route node' '[[ $j == *"route:/things"* ]]'
t 'commit node' '[[ $j == *"commit:abc1234"* ]]'
t 'module node' '[[ $j == *"module:mymod"* ]]'
t 'location node' '[[ $j == *"location:note1.md:1"* ]]'
t 'documents edge' '[[ $j == *'"'"'"kind":"documents"'"'"'* ]]'
t 'touches edge' '[[ $j == *'"'"'"kind":"touches"'"'"'* ]]'
t 'used-by edge' '[[ $j == *'"'"'"kind":"used-by"'"'"'* ]]'
t 'imports edge' '[[ $j == *'"'"'"kind":"imports"'"'"'* ]]'
t 'wikilink edge' '[[ $j == *'"'"'"kind":"references"'"'"'* ]]'

q=$( "$FEFO" graph --query Thing )
t 'query finds symbol' '[[ $q == *"symbol"*Thing*"fakerepo/models.py:12"* ]]'
r=$( "$FEFO" graph --query /things )
t 'query finds route' '[[ $r == *"route"*/things* ]]'
c=$( "$FEFO" graph --query "fix thing" )
t 'query finds commit' '[[ $c == *"commit"*abc1234* ]]'
n=$( "$FEFO" graph --query Note )
t 'query finds note' '[[ $n == *"note1.md"* ]]'
t 'query rejects extra flags' '! fefo graph --query Thing --out "$tmp/no.html" >/dev/null 2>&1'

# unchanged refresh must not touch graph.json
cp "$G" "$tmp/before.json"
"$FEFO" vault --changed >/dev/null 2>&1
t 'changed no rewrite' 'cmp -s "$tmp/before.json" "$G"'
mt1=$(command stat -c %Y "$G" 2>/dev/null || command stat -f %m "$G")
sleep 1
touch docs/vault/fakerepo-vault/modules/mymod.md
"$FEFO" vault --changed >/dev/null 2>&1
mt2=$(command stat -c %Y "$G" 2>/dev/null || command stat -f %m "$G")
t 'stale vault note rebuilds graph' '[[ $mt2 -gt $mt1 ]]'

# no external indexer in generated instructions/config
t 'AGENTS.md no codegraph' '! grep -qi codegraph AGENTS.md'
t 'opencode.json no codegraph' '! grep -qi codegraph opencode.json'
t 'no index command' '! fefo index >/dev/null 2>&1'

print -r -- "== RESULT: PASS=$PASS FAIL=$FAIL"
(( FAIL == 0 )) || exit 1
exit 0
