#!/usr/bin/env zsh
# FEFO installer tests. Plain zsh; isolated HOME/XDG; no writes outside temp dirs.
emulate -L zsh
setopt extended_glob
FEFO_ROOT=${0:A:h:h}
PASS=0
FAIL=0
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
t() { local n=$1; shift
  if eval "$@"; then ((PASS++)); print "PASS $n"; else ((FAIL++)); print "FAIL $n" >&2; fi
}
env_for() {
  export HOME=$tmp/$1/home XDG_DATA_HOME=$tmp/$1/home/.local/share XDG_CONFIG_HOME=$tmp/$1/home/.config
  export XDG_CACHE_HOME=$tmp/$1/home/.cache
  unset XDG_BIN_HOME FEFO_DIR FEFO_MODE FEFO_MODEL FEFO_AGENTS
  mkdir -p $HOME
}
export PATH=$FEFO_ROOT/tests/shims:$FEFO_ROOT/bin:$PATH
export FEFO_INSTALL_DRY=1 FEFO_SKIP_UPDATE_CHECK=1 FEFO_YES=1
IN="--yes --cheap --default-agents --with-all"

for f in $FEFO_ROOT/install.sh $FEFO_ROOT/install.zsh $FEFO_ROOT/share/fefo.zsh $FEFO_ROOT/tests/install.zsh; do
  t "zsh -n ${f:t}" "zsh -n $f"
done
t "sh -n install.sh" "sh -n $FEFO_ROOT/install.sh"
t "install.sh <=30 lines" '(( $(wc -l < $FEFO_ROOT/install.sh) <= 30 ))'
t "no <| garbage" '! grep -n "<|" $FEFO_ROOT/install.sh $FEFO_ROOT/install.zsh $FEFO_ROOT/share/fefo.zsh $FEFO_ROOT/README.md'

# 1. --from checkout (FEFO checkout as source)
env_for a
zsh $FEFO_ROOT/install.zsh --from $FEFO_ROOT ${=IN} >$tmp/a.out 2>&1
H=$XDG_DATA_HOME/fefo/share
t "from: helper copied" '[[ -f $H/fefo.zsh ]]'
t "from: zshrc sources helper" 'grep -q "source \"$H/fefo.zsh\"" $HOME/.zshrc'
t "from: dry components" 'grep -q "^DRY: .*browse" $tmp/a.out'
t "from: config written" 'grep -qx "subagents cheap" $XDG_CONFIG_HOME/fefo/config.zsh && grep -qx "agents default" $XDG_CONFIG_HOME/fefo/config.zsh'
zsh $FEFO_ROOT/install.zsh --from $FEFO_ROOT ${=IN} >/dev/null 2>&1
t "twice: one zshrc block" '(( $(grep -c "^# >>> fefo >>>" $HOME/.zshrc) == 1 ))'
t "helper functions load" 'zsh -c "source $H/fefo.zsh; whence -w cmg bng doit" | grep -c ":" | grep -q 3'

# cmg/bng/doit with shim
G=$tmp/a/repo; mkdir -p $G; git -C $G init -q; print x > $G/f.txt; git -C $G add f.txt
out=$(cd $G && zsh -c "source $H/fefo.zsh; cmg" 2>&1)
t "cmg suggests commit" '[[ $out == *"git commit -m"* ]]'
out=$(cd $G && zsh -c "source $H/fefo.zsh; bng" 2>&1)
t "bng makes branch" '[[ $out == *"→"* ]]'
out=$(cd $G && zsh -c "source $H/fefo.zsh; doit -C $G do-it" 2>&1)
t "doit runs" '[[ $out == *"doit: opencode model="* ]]'

# 2. piped install.sh (curl | sh shape): downloads FEFO as a tarball (local file:// here)
env_for b; mkdir -p $tmp/b/cwd $tmp/b/pkg/FEFO
cp -R $FEFO_ROOT/install.sh $FEFO_ROOT/install.zsh $FEFO_ROOT/share $FEFO_ROOT/bin $tmp/b/pkg/FEFO/
tar -czf $tmp/b/fefo.tgz -C $tmp/b/pkg FEFO
# a decoy install.zsh in the current directory must never run when piped
print -r -- 'touch "$HOME/DECOY_RAN"' > $tmp/b/cwd/install.zsh
(cd $tmp/b/cwd && cat $FEFO_ROOT/install.sh | FEFO_INSTALL_TARBALL=file://$tmp/b/fefo.tgz sh -s -- --from $FEFO_ROOT --dir $tmp/b/fefo ${=IN} >/dev/null 2>&1)
t "piped sh install" '[[ -L $HOME/.local/bin/fefo && -f $H/fefo.zsh ]]'
t "piped sh ignores cwd install.zsh" '[[ ! -e $HOME/DECOY_RAN ]]'

# 3. tarball download (network)
env_for c
zsh $FEFO_ROOT/install.zsh --ref main --dir $tmp/c/fefo ${=IN} >$tmp/c.out 2>&1
t "tarball: bin/fefo exists" '[[ -f $tmp/c/fefo/bin/fefo ]]'
t "tarball: no .git" '[[ ! -e $tmp/c/fefo/.git ]]'
t "tarball: link to downloaded" '[[ $(readlink $HOME/.local/bin/fefo) == $tmp/c/fefo/bin/fefo ]]'
zsh $FEFO_ROOT/install.zsh --ref main --dir $tmp/c/fefo ${=IN} >/dev/null 2>&1
t "tarball: re-install ok, no leftovers" '[[ -f $tmp/c/fefo/bin/fefo && ! -e $tmp/c/fefo.old ]]'
zsh $FEFO_ROOT/install.zsh --uninstall --yes >/dev/null 2>&1
t "uninstall: downloaded FEFO removed" '[[ ! -e $tmp/c/fefo ]]'
t "uninstall: link, block, helper gone" '[[ ! -e $HOME/.local/bin/fefo && ! -e $XDG_DATA_HOME/fefo && ! -e $XDG_DATA_HOME/fefo/install-cache ]]'

# uninstall keeps --from checkout
env_for a
zsh $FEFO_ROOT/install.zsh --uninstall --yes >/dev/null 2>&1
t "uninstall: --from checkout kept" '[[ -f $FEFO_ROOT/bin/fefo ]]'
t "uninstall: from link/block/helper gone" '[[ ! -e $HOME/.local/bin/fefo && ! -e $XDG_DATA_HOME/fefo && ! -e $XDG_DATA_HOME/fefo/install-cache ]]'

print "PASS=$PASS FAIL=$FAIL"
[[ $FAIL -eq 0 ]]
