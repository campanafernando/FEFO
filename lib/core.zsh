emulate -L zsh
setopt local_options extended_glob no_unset pipe_fail typeset_silent

_fefo_info() { print -r -- "$*"; }

_fefo_warn() { print -r -- "fefo: warning: $*" >&2; }

_fefo_die() { print -r -- "fefo: $*" >&2; return 1; }

_fefo_root() {
  emulate -L zsh
  setopt local_options extended_glob no_unset pipe_fail typeset_silent
  if [[ -n ${FEFO_ROOT:-} ]]; then
    print -r -- "$FEFO_ROOT"
    return 0
  fi
  local d=$PWD
  while [[ -n $d && $d != / ]]; do
    if [[ -f $d/.fefo/workspace.zsh ]]; then
      print -r -- "$d"
      return 0
    fi
    d=${d:h}
  done
  if [[ -f /.fefo/workspace.zsh ]]; then
    print -r -- /
    return 0
  fi
  return 1
}

_fefo_emit() {
  emulate -L zsh
  setopt local_options extended_glob no_unset pipe_fail typeset_silent
  local rel=$1; shift
  local fn=$1; shift
  local ws=${FEFO_WS:-}
  if [[ -z $ws ]]; then
    ws=$(_fefo_root) || return 1
  fi
  local target=$ws/$rel
  local dir=${target:h}
  mkdir -p "$dir" 2>/dev/null
  local tmp
  tmp=$(mktemp "$dir/.fefo.emit.XXXXXX") || return 1
  if ! "$fn" "$@" >"$tmp"; then
    rm -f "$tmp"
    return 1
  fi
  if [[ -f $target ]] && cmp -s "$target" "$tmp"; then
    rm -f "$tmp"
    return 0
  fi
  if [[ ${FEFO_CHECK:-0} == 1 ]]; then
    print -r -- "DRIFT $rel"
    typeset -g FEFO_DRIFT=1
    export FEFO_DRIFT
    rm -f "$tmp"
    return 0
  fi
  mv -f "$tmp" "$target" || { rm -f "$tmp"; return 1; }
  if [[ ${FEFO_QUIET:-0} != 1 ]]; then
    print -r -- "wrote $rel"
  fi
  return 0
}

_fefo_emit_once() {
  emulate -L zsh
  setopt local_options extended_glob no_unset pipe_fail typeset_silent
  local rel=$1
  local ws=${FEFO_WS:-}
  if [[ -z $ws ]]; then
    ws=$(_fefo_root) || return 1
  fi
  local target=$ws/$rel
  if [[ -f $target ]]; then
    return 0
  fi
  _fefo_emit "$@"
}

_fefo_json() {
  emulate -L zsh
  setopt local_options extended_glob no_unset pipe_fail typeset_silent
  local s=$1
  s=${s//\\/\\\\}
  s=${s//\"/\\\"}
  s=${s//$'\n'/\\n}
  s=${s//$'\t'/\\t}
  s=${s//$'\r'/\\r}
  print -r -- "\"$s\""
}

_fefo_relpath() {
  emulate -L zsh
  setopt local_options extended_glob no_unset pipe_fail typeset_silent
  local target=${1:A}
  local base=${2:A}
  if [[ $target == $base ]]; then
    print -r -- "."
    return 0
  fi
  local t=${target#/}
  local b=${base#/}
  local -a ta ba
  ta=(${(s:/:)t})
  ba=(${(s:/:)b})
  local i=0
  while (( i < ${#ta} && i < ${#ba} )); do
    [[ ${ta[i+1]:-} == ${ba[i+1]:-} ]] || break
    ((i++))
  done
  local up=$(( ${#ba} - i ))
  local res=""
  local j
  for ((j=0;j<up;j++)); do
    res+="../"
  done
  for ((j=i;j<${#ta};j++)); do
    res+="${ta[j+1]}/"
  done
  res=${res%/}
  [[ -z $res ]] && res="."
  print -r -- "$res"
}

_fefo_version_ge() {
  emulate -L zsh
  setopt local_options extended_glob no_unset pipe_fail typeset_silent
  local a=${1#v}
  local b=${2#v}
  local -a ap bp
  ap=(${(s:.:)a})
  bp=(${(s:.:)b})
  local n=${#ap}
  (( ${#bp} > n )) && n=${#bp}
  local i
  for ((i=1;i<=n;i++)); do
    local x=${ap[i]:-0}
    local y=${bp[i]:-0}
    x=${x//[^0-9]/}
    y=${y//[^0-9]/}
    [[ -z $x ]] && x=0
    [[ -z $y ]] && y=0
    if (( 10#$x > 10#$y )); then
      return 0
    fi
    if (( 10#$x < 10#$y )); then
      return 1
    fi
  done
  return 0
}

_fefo_slug() {
  emulate -L zsh
  setopt local_options extended_glob no_unset pipe_fail typeset_silent
  local s=${1:l}
  s=${s//[^a-z0-9]/-}
  while [[ $s == *--* ]]; do
    s=${s//--/-}
  done
  s=${s#-}
  s=${s%-}
  [[ -z $s ]] && s=repo
  print -r -- "$s"
}

_fefo_confirm() {
  emulate -L zsh
  setopt local_options extended_glob no_unset pipe_fail typeset_silent
  if [[ ${FEFO_YES:-0} == 1 ]]; then
    return 0
  fi
  if [[ ! -t 0 ]]; then
    return 1
  fi
  local ans
  print -rn -- "$1 [y/N] "
  read -r ans || return 1
  [[ $ans == [yY]* ]]
}