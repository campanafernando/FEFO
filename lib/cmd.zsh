emulate -L zsh
setopt local_options extended_glob no_unset pipe_fail typeset_silent
zmodload zsh/datetime zsh/stat 2>/dev/null

typeset -g FEFO_CHECK=0
typeset -g FEFO_DRIFT=0

_fefo_usage() {
  emulate -L zsh
  setopt local_options extended_glob no_unset pipe_fail typeset_silent
  print -r -- "usage: fefo <command> [args]"
  print -r -- "commands: init add remove sync status vault doctor mcp model handoff graph agents version help"
  print -r -- "graph --query TERM  search symbols, modules, routes, commits and notes in docs/vault/graph.json"
  print -r -- "graph [--port N] [--open] [--out FILE]  open or write the local viewer"
}

_fefo_ws() {
  emulate -L zsh
  setopt local_options extended_glob no_unset pipe_fail typeset_silent
  local ws
  ws=$(_fefo_root) || { _fefo_die "not a fefo workspace (no .fefo/workspace.zsh)"; return 1; }
  FEFO_WS=$ws
  export FEFO_WS
  print -r -- "$ws"
}

_fefo_cmd_help() {
  emulate -L zsh
  setopt local_options extended_glob no_unset pipe_fail typeset_silent
  local cmd=${1:-}
  if [[ -n $cmd ]]; then
    print -r -- "fefo $cmd: see DESIGN.md section 7"
    return 0
  fi
  _fefo_usage
}

_fefo_cmd_version() {
  emulate -L zsh
  setopt local_options extended_glob no_unset pipe_fail typeset_silent
  print -r -- "fefo 2 (zsh)"
}

# ---------- init ----------
_fefo_cmd_init() {
  emulate -L zsh
  setopt local_options extended_glob no_unset pipe_fail typeset_silent

  local name=""
  local -a repos=()
  local scan=0
  local cheap=0
  local model=""
  local fallback=""
  local parallel=""
  local no_browse=0
  local force=0
  local yes=0
  local ai_agents=0 default_agents=0
  local no_vault=0
  local no_claude=0

  while (( $# )); do
    case $1 in
      --name) name=$2; shift 2 ;;
      --repo) repos+=("$2"); shift 2 ;;
      --scan) scan=1; shift ;;
      --cheap) cheap=1; shift ;;
      --model) model=$2; shift 2 ;;
      --fallback) fallback=$2; shift 2 ;;
      --parallel) parallel=$2; shift 2 ;;
      --no-browse) no_browse=1; shift ;;
      --force) force=1; shift ;;
      --yes) yes=1; shift ;;
      --ai-agents) ai_agents=1; shift ;;
      --default-agents) default_agents=1; shift ;;
      --no-vault) no_vault=1; shift ;;
      --no-claude) no_claude=1; shift ;;
      *) _fefo_die "unknown flag: $1"; return 2 ;;
    esac
  done

  export FEFO_YES=$yes
  local ws=$PWD
  FEFO_WS=$ws
  export FEFO_WS

  local manifest=$ws/.fefo/workspace.zsh
  if [[ -f $manifest && $force != 1 ]]; then
    _fefo_die "manifest exists: $manifest (use --force)"
    return 1
  fi

  # user config seeds
  _fefo_userconfig_load || true

  # legacy workspace.json backup
  if [[ -f $ws/.fefo/workspace.json ]]; then
    mv -f "$ws/.fefo/workspace.json" "$ws/.fefo/workspace.json.bak" 2>/dev/null
  fi

  # name default
  if [[ -z $name ]]; then
    name=${ws:t}
  fi
  FEFO_NAME=$name

  # browse
  if (( no_browse )); then FEFO_BROWSE=0; fi
  # code vaults (default on)
  if (( no_vault )); then FEFO_VAULT=0; fi
  if (( no_claude )); then
    FEFO_CLAUDE=0
  else
    : # keep user config default (on)
  fi

  # parallel
  if [[ -n $parallel ]]; then FEFO_PARALLEL=$parallel; fi
  # fallback
  if [[ -n $fallback ]]; then FEFO_FALLBACK=$fallback; fi

  # model mode
  if [[ -n $model ]]; then
    FEFO_MODE=default
    FEFO_SUBMODEL=$model
  elif (( cheap )); then
    FEFO_MODE=cheap
    FEFO_SUBMODEL=""
  else
    if [[ -t 0 ]]; then
      print -r -- "Subagent models: [1] cheap — orchestrator picks the strongest free model (default)"
      print -r -- "                [2] default — you pick one model now"
      local ans
      print -rn -- "choice [1]: "
      read -r ans
      if [[ $ans == 2 ]]; then
        FEFO_MODE=default
        local picked
        picked=$(_fefo_pick_model) || { FEFO_MODE=cheap; FEFO_SUBMODEL=""; }
        if [[ -n $picked ]]; then FEFO_SUBMODEL=$picked; fi
      else
        FEFO_MODE=cheap
        FEFO_SUBMODEL=""
      fi
      # fallback prompt
      print -rn -- "Fallback model (Enter = auto): "
      local fb
      read -r fb
      if [[ -n $fb ]]; then FEFO_FALLBACK=$fb; fi
    else
      FEFO_MODE=cheap
      FEFO_SUBMODEL=""
    fi
  fi

  # agents
  if (( ai_agents )); then
    FEFO_AGENTS=ai
  elif (( default_agents )); then
    FEFO_AGENTS=default
  else
    if [[ -n ${FEFO_AGENTS:-} ]]; then
      : # keep from user config
    fi
    if [[ -t 0 ]] && [[ ${FEFO_AGENTS:-default} == default ]]; then
      # only prompt if not set by config? keep simple: prompt
      print -r -- "Agents: [1] default set (recommended offline) [2] AI-scoped with a free model"
      local aans
      print -rn -- "choice [1]: "
      read -r aans
      if [[ $aans == 2 ]]; then FEFO_AGENTS=ai; else FEFO_AGENTS=default; fi
    fi
  fi

  # OpenCode loads project config (and MCP servers) only inside a Git work tree
  if ! git -C "$ws" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    git -C "$ws" init -q && print -r -- "fefo: git init (OpenCode reads project config only inside a Git repository)"
  fi

  # repos
  mkdir -p "$ws/.fefo"
  if (( ${#repos} )); then
    local p
    for p in "${repos[@]}"; do
      _fefo_init_add_repo "$p" || return 1
    done
  else
    # scan
    local scanned
    scanned=$(_fefo_scan_repos "$ws") || true
    if [[ -n $scanned ]]; then
      local line
      for line in ${(f)scanned}; do
        _fefo_init_add_repo "$line" || true
      done
    fi
  fi

  print -r -- "fefo: detected ${#FEFO_REPOS} git repositories"
  local rn
  for rn in "${FEFO_REPOS[@]}"; do
    print -r -- "fefo: added $rn (${FEFO_R_ROLE[$rn]}/${FEFO_R_STACK[$rn]})"
  done

  _fefo_manifest_save "$manifest" || return 1

  # sync: FEFO_QUIET hides per-file lines, so count them from a normal run
  local sout
  local -a wrote
  sout=$(_fefo_cmd_sync) || { print -r -- "$sout"; return 1; }
  wrote=(${(M)${(f)sout}:#wrote *})
  print -r -- "fefo: wrote ${#wrote} files"

  # code vaults
  if (( ! no_vault )) && (( $+functions[_fefo_cmd_vault] )); then
    _fefo_cmd_vault || _fefo_warn "vault generation failed"
  fi

  # agents install
  if (( $+functions[_fefo_agents_install] )); then
    _fefo_agents_install "$FEFO_AGENTS" || _fefo_warn "agents install failed"
  else
    _fefo_die "agents lane unavailable: _fefo_agents_install not found"; return 1
  fi

  print -r -- "fefo: $name ready — next: opencode"
  return 0
}

_fefo_init_add_repo() {
  emulate -L zsh
  setopt local_options extended_glob no_unset pipe_fail typeset_silent
  local input=$1
  local ws=$FEFO_WS
  local abspath
  if [[ $input = /* ]]; then abspath=$input; else abspath=$PWD/$input; fi
  abspath=${abspath:A}
  local root
  root=$(_fefo_git_root "$abspath")
  [[ -z $root ]] && root=$abspath
  local rel
  rel=$(_fefo_relpath "$root" "$ws")
  local stack role
  stack=$(_fefo_detect_stack "$root")
  role=$(_fefo_detect_role "$stack")
  _fefo_detect_commands "$root" "$stack"
  local name
  name=$(_fefo_slug "${root:t}")
  # ensure unique
  local existing
  for existing in "${FEFO_REPOS[@]}"; do
    if [[ $existing == $name && ${FEFO_R_PATH[$existing]} != $rel ]]; then
      _fefo_die "repo name '$name' already points to ${FEFO_R_PATH[$existing]}"
      return 1
    fi
  done
  # if already present same path, skip
  local skip=0
  for existing in "${FEFO_REPOS[@]}"; do
    if [[ $existing == $name && ${FEFO_R_PATH[$existing]} == $rel ]]; then skip=1; fi
  done
  if (( skip )); then return 0; fi
  FEFO_REPOS+=("$name")
  FEFO_R_PATH[$name]=$rel
  FEFO_R_ROLE[$name]=$role
  FEFO_R_STACK[$name]=$stack
  FEFO_R_VAULT[$name]=1
  FEFO_R_TEST[$name]=${REPLY_TEST:-}
  FEFO_R_LINT[$name]=${REPLY_LINT:-}
  FEFO_R_BUILD[$name]=${REPLY_BUILD:-}
  FEFO_R_RUN[$name]=${REPLY_RUN:-}
  return 0
}

# ---------- add ----------
_fefo_cmd_add() {
  emulate -L zsh
  setopt local_options extended_glob no_unset pipe_fail typeset_silent
  local rarg=""
  local name=""
  local role=""
  local stack=""
  while (( $# )); do
    case $1 in
      --name) name=$2; shift 2 ;;
      --role) role=$2; shift 2 ;;
      --stack) stack=$2; shift 2 ;;
      *) 
        if [[ -z $rarg ]]; then rarg=$1; else _fefo_die "unexpected arg: $1"; return 2; fi
        shift
        ;;
    esac
  done
  [[ -n $rarg ]] || { _fefo_die "usage: fefo add PATH"; return 2; }
  local ws
  ws=$(_fefo_ws) || return 1
  _fefo_manifest_load "$ws/.fefo/workspace.zsh" || return 1
  FEFO_WS=$ws; export FEFO_WS

  local abspath
  if [[ $rarg = /* ]]; then abspath=$rarg; else abspath=$PWD/$rarg; fi
  abspath=${abspath:A}
  [[ -d $abspath ]] || { _fefo_die "directory not found: $abspath"; return 1; }
  local root
  root=$(_fefo_git_root "$abspath")
  [[ -z $root ]] && root=$abspath
  local rel
  rel=$(_fefo_relpath "$root" "$ws")

  local det_stack det_role
  det_stack=$(_fefo_detect_stack "$root")
  det_role=$(_fefo_detect_role "$det_stack")
  [[ -n $stack ]] || stack=$det_stack
  [[ -n $role ]] || role=$det_role
  _fefo_detect_commands "$root" "$stack"

  if [[ -z $name ]]; then
    name=$(_fefo_slug "${root:t}")
  else
    name=$(_fefo_slug "$name")
  fi

  # duplicate check
  local existing
  for existing in "${FEFO_REPOS[@]}"; do
    if [[ $existing == $name ]]; then
      if [[ ${FEFO_R_PATH[$existing]} != $rel ]]; then
        _fefo_die "repo name '$name' already points to ${FEFO_R_PATH[$existing]}"
        return 1
      else
        # update
        FEFO_R_ROLE[$name]=$role
        FEFO_R_STACK[$name]=$stack
        FEFO_R_TEST[$name]=${REPLY_TEST:-}
        FEFO_R_LINT[$name]=${REPLY_LINT:-}
        FEFO_R_BUILD[$name]=${REPLY_BUILD:-}
        FEFO_R_RUN[$name]=${REPLY_RUN:-}
        _fefo_manifest_save "$ws/.fefo/workspace.zsh" || return 1
        _fefo_cmd_sync || return 1
        return 0
      fi
    fi
  done

  FEFO_REPOS+=("$name")
  FEFO_R_PATH[$name]=$rel
  FEFO_R_ROLE[$name]=$role
  FEFO_R_STACK[$name]=$stack
  FEFO_R_VAULT[$name]=1
  FEFO_R_TEST[$name]=${REPLY_TEST:-}
  FEFO_R_LINT[$name]=${REPLY_LINT:-}
  FEFO_R_BUILD[$name]=${REPLY_BUILD:-}
  FEFO_R_RUN[$name]=${REPLY_RUN:-}

  _fefo_manifest_save "$ws/.fefo/workspace.zsh" || return 1
  _fefo_cmd_sync || return 1
  return 0
}

# ---------- remove ----------
_fefo_cmd_remove() {
  emulate -L zsh
  setopt local_options extended_glob no_unset pipe_fail typeset_silent
  local name=${1:-}
  [[ -n $name ]] || { _fefo_die "usage: fefo remove NAME"; return 2; }
  local ws
  ws=$(_fefo_ws) || return 1
  _fefo_manifest_load "$ws/.fefo/workspace.zsh" || return 1
  FEFO_WS=$ws; export FEFO_WS

  local found=0
  local r
  for r in "${FEFO_REPOS[@]}"; do
    if [[ $r == $name ]]; then found=1; fi
  done
  if (( ! found )); then
    _fefo_die "unknown repo: $name"
    return 1
  fi

  local -a new=()
  for r in "${FEFO_REPOS[@]}"; do
    [[ $r == $name ]] || new+=("$r")
  done
  FEFO_REPOS=("${new[@]}")
  unset "FEFO_R_PATH[$name]" "FEFO_R_ROLE[$name]" "FEFO_R_STACK[$name]" "FEFO_R_VAULT[$name]" "FEFO_R_TEST[$name]" "FEFO_R_LINT[$name]" "FEFO_R_BUILD[$name]" "FEFO_R_RUN[$name]"

  _fefo_manifest_save "$ws/.fefo/workspace.zsh" || return 1
  _fefo_cmd_sync || return 1
  return 0
}

# ---------- sync ----------
_fefo_cmd_sync() {
  emulate -L zsh
  setopt local_options extended_glob no_unset pipe_fail typeset_silent
  local check=0
  while (( $# )); do
    case $1 in
      --check) check=1; shift ;;
      *) _fefo_die "unknown flag: $1"; return 2 ;;
    esac
  done
  local ws
  ws=$(_fefo_ws) || return 1
  _fefo_manifest_load "$ws/.fefo/workspace.zsh" || return 1
  FEFO_WS=$ws; export FEFO_WS
  if (( check )); then
    FEFO_CHECK=1
  else
    FEFO_CHECK=0
  fi
  FEFO_DRIFT=0
  export FEFO_CHECK FEFO_DRIFT

  if (( $+functions[_fefo_gen_all] )); then
    _fefo_gen_all || return 1
  else
    _fefo_die "gen lane unavailable: _fefo_gen_all not found"; return 1
  fi

  if (( check )) && [[ ${FEFO_DRIFT:-0} == 1 ]]; then
    return 3
  fi
  return 0
}

# ---------- status ----------
_fefo_cmd_status() {
  emulate -L zsh
  setopt local_options extended_glob no_unset pipe_fail typeset_silent
  local ws
  ws=$(_fefo_ws) || return 1
  _fefo_manifest_load "$ws/.fefo/workspace.zsh" || return 1
  FEFO_WS=$ws; export FEFO_WS
  print -r -- "workspace: $FEFO_NAME"
  print -r -- "root: $ws"
  print -r -- "mode: $FEFO_MODE"
  [[ -n $FEFO_SUBMODEL ]] && print -r -- "submodel: $FEFO_SUBMODEL"
  print -r -- "fallback: $FEFO_FALLBACK"
  print -r -- "parallel: $FEFO_PARALLEL"
  print -r -- "handoff: $FEFO_HANDOFF"
  local -a onoff=(off on)
  print -r -- "browse: ${onoff[FEFO_BROWSE+1]}"
  print -r -- "vault: ${onoff[FEFO_VAULT+1]}"
  print -r -- "claude: ${onoff[FEFO_CLAUDE+1]}"
  print -r -- "agents: $FEFO_AGENTS"
  print -r -- "repos:"
  local r
  for r in "${FEFO_REPOS[@]}"; do
    local p=$ws/${FEFO_R_PATH[$r]}
    local exists="missing"
    [[ -d $p ]] && exists="ok"
    local vstate=$(_fefo_vault_state "$r")
    print -r -- "  $r: ${FEFO_R_PATH[$r]} ($exists) stack=${FEFO_R_STACK[$r]} role=${FEFO_R_ROLE[$r]} vault $vstate"
  done
  print -r -- "mcps: ${${FEFO_MCPS[*]}:-none}"
  if whence -p opencode >/dev/null 2>&1; then
    print -r -- "opencode: $(opencode --version 2>/dev/null)"
  else
    print -r -- "opencode: missing"
  fi
}

# ---------- vault state ----------
# prints fresh|stale|none for repo REPO (code vault docs/vault/<slug>-vault vs HEAD stamp)
_fefo_vault_state() {
  emulate -L zsh
  setopt local_options extended_glob no_unset pipe_fail typeset_silent
  local repo=$1
  local ws=${FEFO_WS:-}
  if [[ -z $ws ]]; then ws=$(_fefo_root 2>/dev/null) || ws=$PWD; fi
  local slug=$(_fefo_slug "$repo")
  local out=$ws/docs/vault/$slug-vault
  if [[ ! -d $out ]]; then print -r -- none; return 0; fi
  local rpath=$ws/${FEFO_R_PATH[$repo]:-.}
  local head=""
  head=$(git -C "$rpath" rev-parse HEAD 2>/dev/null) || head=""
  local stamp=""
  [[ -f $out/.stamp ]] && stamp=$(<"$out/.stamp")
  head=${head//[[:space:]]/}
  stamp=${stamp//[[:space:]]/}
  if [[ -n $head && $stamp == $head ]]; then print -r -- fresh; else print -r -- stale; fi
}


# ---------- mcp ----------
_fefo_cmd_mcp() {
  emulate -L zsh
  setopt local_options extended_glob no_unset pipe_fail typeset_silent
  local sub=${1:-}
  shift 2>/dev/null || true
  case $sub in
    list)
      local ws
      ws=$(_fefo_ws) || return 1
      _fefo_manifest_load "$ws/.fefo/workspace.zsh" || return 1
      FEFO_WS=$ws; export FEFO_WS
      local m
      for m in "${FEFO_MCPS[@]}"; do
        print -r -- "$m: ${FEFO_M_TYPE[$m]} ${FEFO_M_TARGET[$m]}"
      done
      ;;
    add)
      local name=""
      local url=""
      local -a headers=()
      local -a cmdwords=()
      local mode=""
      # parse
      name=${1:-}; shift
      if [[ ${1:-} == --url ]]; then
        mode=remote
        url=$2; shift 2
        while [[ ${1:-} == --header ]]; do headers+=("$2"); shift 2; done
      elif [[ ${1:-} == -- ]]; then
        mode=local
        shift
        cmdwords=("$@")
      else
        _fefo_die "usage: fefo mcp add NAME --url URL | -- CMD"; return 2
      fi
      [[ -n $name && -n $mode ]] || { _fefo_die "usage"; return 2; }
      local ws
      ws=$(_fefo_ws) || return 1
      _fefo_manifest_load "$ws/.fefo/workspace.zsh" || return 1
      FEFO_WS=$ws; export FEFO_WS

      FEFO_MCPS+=("$name")
      FEFO_M_TYPE[$name]=$mode
      if [[ $mode == remote ]]; then
        FEFO_M_TARGET[$name]=$url
        local hstr=""
        local h
        for h in "${headers[@]}"; do
          if [[ -z $hstr ]]; then hstr=$h; else hstr+=$'\n'$h; fi
        done
        FEFO_M_HEADERS[$name]=$hstr
      else
        local joined=""
        local first=1
        local w
        for w in "${cmdwords[@]}"; do
          if (( first )); then joined=$w; first=0; else joined+=$'\0'$w; fi
        done
        FEFO_M_TARGET[$name]=$joined
        FEFO_M_HEADERS[$name]=""
      fi
      _fefo_manifest_save "$ws/.fefo/workspace.zsh" || return 1
      _fefo_cmd_sync || return 1
      ;;
    remove)
      local name=${1:-}
      [[ -n $name ]] || { _fefo_die "usage: fefo mcp remove NAME"; return 2; }
      local ws
      ws=$(_fefo_ws) || return 1
      _fefo_manifest_load "$ws/.fefo/workspace.zsh" || return 1
      FEFO_WS=$ws; export FEFO_WS
      local -a new=()
      local m
      for m in "${FEFO_MCPS[@]}"; do
        [[ $m == $name ]] || new+=("$m")
      done
      FEFO_MCPS=("${new[@]}")
      unset "FEFO_M_TYPE[$name]" "FEFO_M_TARGET[$name]" "FEFO_M_HEADERS[$name]"
      _fefo_manifest_save "$ws/.fefo/workspace.zsh" || return 1
      _fefo_cmd_sync || return 1
      ;;
    *)
      _fefo_die "usage: fefo mcp list|add|remove"
      return 2
      ;;
  esac
}

# ---------- model ----------
_fefo_pick_model() {
  emulate -L zsh
  setopt local_options extended_glob no_unset pipe_fail typeset_silent
  local query=${1:-}
  local -a models
  models=(${(f)"$(opencode models 2>/dev/null)"})
  while true; do
    local -a matches=()
    local m
    if [[ -z $query ]]; then
      matches=("${models[@]}")
    else
      for m in "${models[@]}"; do
        if print -r -- "$m" | grep -qi -- "$query"; then
          matches+=("$m")
        fi
      done
    fi
    local shown=0
    local i
    for ((i=1;i<=${#matches} && i<=30;i++)); do
      print -r -- "  $i) ${matches[i]}" >&2
      shown=$i
    done
    if (( ${#matches} > 30 )); then
      print -r -- "  ... and $(( ${#matches}-30 )) more" >&2
    fi
    local ans
    if [[ -t 0 ]]; then
      print -rn -- "number, new search, or Enter to cancel: " >&2
    fi
    read -r ans || return 1
    [[ -z $ans ]] && return 1
    if [[ $ans == <-> ]]; then
      local n=$ans
      if (( n >= 1 && n <= shown )); then
        print -r -- "${matches[n]}"
        return 0
      fi
      print -r -- "invalid number" >&2
    else
      query=$ans
    fi
  done
}

_fefo_cmd_model() {
  emulate -L zsh
  setopt local_options extended_glob no_unset pipe_fail typeset_silent
  local global=0
  local -a args=()
  while (( $# )); do
    case $1 in
      --global) global=1; shift ;;
      *) args+=("$1"); shift ;;
    esac
  done
  set -- "${args[@]}"

  local sub=${1:-show}
  # load target
  if (( global )); then
    _fefo_userconfig_load || true
  else
    local ws
    ws=$(_fefo_ws) || return 1
    _fefo_manifest_load "$ws/.fefo/workspace.zsh" || return 1
    FEFO_WS=$ws; export FEFO_WS
  fi

  case $sub in
    show)
      print -r -- "mode: $FEFO_MODE"
      [[ -n $FEFO_SUBMODEL ]] && print -r -- "submodel: $FEFO_SUBMODEL"
      print -r -- "fallback: $FEFO_FALLBACK"
      ;;
    cheap)
      FEFO_MODE=cheap
      FEFO_SUBMODEL=""
      _fefo_model_save $global
      ;;
    default)
      shift
      local query=${1:-}
      local picked
      if [[ -n $query ]] && opencode models 2>/dev/null | grep -Fxq -- "$query"; then
        picked=$query
      elif [[ -n $query ]]; then
        if [[ ! -t 0 ]]; then
          _fefo_die "model '$query' not found and no TTY for the picker; use an exact id from: opencode models"
          return 1
        fi
        picked=$(_fefo_pick_model "$query") || { _fefo_die "no model selected"; return 1; }
      else
        picked=$(_fefo_pick_model) || { _fefo_die "no model selected"; return 1; }
      fi
      [[ -n $picked ]] || { _fefo_die "no model selected"; return 1; }
      FEFO_MODE=default
      FEFO_SUBMODEL=$picked
      _fefo_model_save $global
      ;;
    fallback)
      shift
      local val=${1:-}
      [[ -n $val ]] || { _fefo_die "usage: fefo model fallback ID|auto"; return 2; }
      FEFO_FALLBACK=$val
      _fefo_model_save $global
      ;;
    *)
      _fefo_die "usage: fefo model [show]|cheap|default [QUERY]|fallback ID|auto"
      return 2
      ;;
  esac
  if (( ! global )); then
    _fefo_cmd_sync || true
  fi
  return 0
}

_fefo_model_save() {
  emulate -L zsh
  setopt local_options extended_glob no_unset pipe_fail typeset_silent
  local global=$1
  if (( global )); then
    local file=${XDG_CONFIG_HOME:-$HOME/.config}/fefo/config.zsh
    mkdir -p "${file:h}"
    local tmp=$file.tmp line
    : > "$tmp"
    if [[ -f $file ]]; then
      while IFS= read -r line || [[ -n $line ]]; do
        [[ ${${line## #}%% *} == (subagents|fallback) ]] || print -r -- "$line" >> "$tmp"
      done < "$file"
    fi
    {
      if [[ -n $FEFO_SUBMODEL ]]; then print -r -- "subagents $FEFO_MODE $FEFO_SUBMODEL"; else print -r -- "subagents $FEFO_MODE"; fi
      print -r -- "fallback $FEFO_FALLBACK"
    } >> "$tmp"
    mv "$tmp" "$file"
  else
    _fefo_manifest_save "$FEFO_WS/.fefo/workspace.zsh"
  fi
}

# ---------- handoff ----------
_fefo_cmd_handoff() {
  emulate -L zsh
  setopt local_options extended_glob no_unset pipe_fail typeset_silent
  local show_status=0
  local -a lanes=()
  local -a pos=()
  while (( $# )); do
    case $1 in
      --status) show_status=1; shift ;;
      *) pos+=("$1"); shift ;;
    esac
  done

  local ws
  ws=$(_fefo_ws) || return 1
  _fefo_manifest_load "$ws/.fefo/workspace.zsh" || return 1
  FEFO_WS=$ws; export FEFO_WS

  local task=${pos[1]:-}
  [[ -n $task ]] || { _fefo_die "usage: fefo handoff TASK [LANE]..."; return 2; }
  local -a rest=("${pos[@]:1}")

  local ws_slug task_slug
  ws_slug=$(_fefo_slug "$FEFO_NAME")
  task_slug=$(_fefo_slug "$task")
  local root=${FEFO_HANDOFF_ENV:-$FEFO_HANDOFF}/${ws_slug}/${task_slug}

  if (( show_status )); then
    if [[ ! -d $root ]]; then
      _fefo_die "handoff not found: $root"
      return 1
    fi
    print -r -- "lane | DONE? | report lines | last modified"
    local lane
    for lane in "$root"/*(N/); do
      local lname=${lane:t}
      local done="no"
      [[ -f $lane/DONE ]] && done="yes"
      local lines=0
      if [[ -f $lane/report.md ]]; then
        lines=$(wc -l < "$lane/report.md")
      fi
      local mt
      zmodload zsh/stat 2>/dev/null
      zmodload zsh/datetime 2>/dev/null
      local mtime
      zstat -A st +mtime "$lane" 2>/dev/null
      mtime=${st[1]:-0}
      local pretty
      pretty=$(strftime '%Y-%m-%d %H:%M' $mtime 2>/dev/null)
      print -r -- "$lname | $done | $lines | $pretty"
    done
    return 0
  fi

  mkdir -p "$root"
  chmod 700 "$root"
  lanes=("${rest[@]}")
  local lane
  for lane in "${lanes[@]}"; do
    mkdir -p "$root/$lane"
  done

  # README template
  local readme=$root/README.md
  {
    print -r -- "# Handoff: $task"
    print -r -- ""
    print -r -- "Workspace: $FEFO_NAME"
    print -r -- "Root: $ws"
    print -r -- "Handoff: $root"
    print -r -- ""
    print -r -- "## Targets"
    print -r -- "- (fill in)"
    print -r -- ""
    print -r -- "## Rules"
    print -r -- "- (fill in)"
    print -r -- ""
    print -r -- "## Protocol"
    print -r -- "- (fill in)"
    print -r -- ""
    print -r -- "## Lanes"
    print -r -- "| Lane | Dir | Status |"
    print -r -- "|---|---|---|"
    for lane in "${lanes[@]}"; do
      print -r -- "| $lane | $lane/ | pending |"
    done
  } > "$readme"

  print -r -- "$root"
  return 0
}

# ---------- doctor ----------
_fefo_cmd_doctor() {
  emulate -L zsh
  setopt local_options extended_glob no_unset pipe_fail typeset_silent
  local ws
  ws=$(_fefo_root 2>/dev/null)
  local fails=0

  # zsh
  if _fefo_version_ge "$ZSH_VERSION" "5.8"; then
    print -r -- "✓ zsh >= 5.8 ($ZSH_VERSION)"
  else
    print -r -- "✗ zsh >= 5.8 ($ZSH_VERSION)"; ((fails++))
  fi

  # opencode
  if whence -p opencode >/dev/null 2>&1; then
    print -r -- "✓ opencode ($(opencode --version 2>/dev/null))"
    if [[ ${FEFO_SKIP_UPDATE_CHECK:-0} != 1 ]]; then
      local cache=${XDG_CACHE_HOME:-$HOME/.cache}/fefo/latest
      local latest="" ; local -a st
      zmodload zsh/stat zsh/datetime 2>/dev/null
      if [[ -f $cache ]] && zstat -A st +mtime "$cache" 2>/dev/null && (( EPOCHSECONDS - st[1] < 21600 )); then
        latest=$(<$cache)
      else
        local body
        body=$(curl -fsSL --max-time 10 https://opencode.ai/update/api/latest/cli/npm 2>/dev/null)
        if [[ $body =~ '"version"[[:space:]]*:[[:space:]]*"([^"]+)"' ]]; then
          latest=$match[1]
          mkdir -p "${cache:h}"
          print -r -- "$latest" > "$cache"
        fi
      fi
      if [[ -z $latest ]]; then
        print -r -- "! could not check latest opencode version"
      elif ! _fefo_version_ge "$(opencode --version 2>/dev/null)" "$latest"; then
        print -r -- "! opencode behind latest $latest — run: opencode upgrade"
      fi
    fi
  else
    print -r -- "✗ opencode missing"; ((fails++))
  fi

  # git
  if whence -p git >/dev/null 2>&1; then
    print -r -- "✓ git"
  else
    print -r -- "✗ git"; ((fails++))
  fi

  # browse
  if whence -p browse >/dev/null 2>&1; then
    print -r -- "✓ browse"
  else
    print -r -- "! browse missing (optional)"
  fi

  # ponytail plugin
  local -a ptf=("${XDG_CONFIG_HOME:-$HOME/.config}"/opencode/opencode.json*(N))
  if (( ${#ptf} )) && grep -qs ponytail "${ptf[@]}" \
      || grep -qs ponytail "$PWD"/opencode.json "$PWD"/opencode.jsonc "$PWD"/.opencode/opencode.json \
      ${ws:+"$ws"/opencode.json "$ws"/opencode.jsonc "$ws"/.opencode/opencode.json} 2>/dev/null; then
    print -r -- "✓ ponytail plugin"
  else
    print -r -- "! ponytail plugin missing (optional)"
  fi

  # caveman skill
  if [[ -f ${HOME}/.agents/skills/caveman/SKILL.md ]]; then
    print -r -- "✓ caveman skill"
  else
    print -r -- "! caveman skill missing (optional)"
  fi

  # manifest
  if [[ -n $ws ]]; then
    if git -C "$ws" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
      print -r -- "✓ workspace is in a Git repository"
    else
      print -r -- "✗ workspace is not in a Git repository (OpenCode ignores its config) — run: git init"; ((fails++))
    fi
    if _fefo_manifest_load "$ws/.fefo/workspace.zsh" 2>/dev/null; then
      print -r -- "✓ manifest parses"
      FEFO_WS=$ws; export FEFO_WS
      # sync --check
      if _fefo_cmd_sync --check >/dev/null 2>&1; then
        print -r -- "✓ sync --check clean"
      else
        print -r -- "✗ sync --check drift"
        ((fails++))
      fi
      # repo paths
      local r
      for r in "${FEFO_REPOS[@]}"; do
        local p=$ws/${FEFO_R_PATH[$r]}
        if [[ -d $p ]]; then
          print -r -- "✓ repo $r path exists"
        else
          print -r -- "✗ repo $r path missing"
          ((fails++))
        fi
        # code vault freshness
        if [[ $(_fefo_vault_state "$r") == stale ]]; then
          print -r -- "! vault stale for $r — fefo vault --changed"
        fi
      done
    else
      print -r -- "✗ manifest parses"; ((fails++))
    fi
    if (( ! ${FEFO_CLAUDE:-1} )); then
      local cf
      for cf in CLAUDE.md .mcp.json .claude/skills; do
        [[ -e $ws/$cf ]] && print -r -- "! claude off but $cf exists (remove it if unused)"
      done
    fi
  else
    print -r -- "! not in a workspace"
  fi

  # legacy artifacts (inspect $PWD when no workspace was found)
  local lw=${ws:-$PWD} legacy=0
  # outside a workspace, only a real old-FEFO marker makes $PWD a legacy workspace
  # (so ~/.claude/settings.json in $HOME is never flagged)
  [[ -z $ws && ! -f $PWD/.fefo/workspace.json && ! -f $PWD/tools/fefo.py ]] && lw=/nonexistent
  _fefo_legacy() { print -r -- "! legacy $1 present — $2"; (( legacy++ )); }
  local hint="fefo init --force"
  [[ -n $ws ]] && hint=remove
  [[ -f $lw/tools/fefo.py ]] && _fefo_legacy tools/fefo.py "$hint"
  [[ -f $lw/.fefo/workspace.json ]] && _fefo_legacy .fefo/workspace.json "fefo init --force"
  if [[ -f $lw/opencode.json ]] && grep -q '"default_agent"' "$lw/opencode.json" 2>/dev/null; then
    _fefo_legacy "default_agent in opencode.json" "$hint"
  fi
  [[ -d $lw/.cursor ]] && _fefo_legacy ".cursor/" "$hint"
  [[ -f $lw/.github/copilot-instructions.md ]] && _fefo_legacy .github/copilot-instructions.md "$hint"
  [[ -d $lw/.claude/agents ]] && _fefo_legacy .claude/agents/ "$hint"
  [[ -d $lw/.claude/commands ]] && _fefo_legacy .claude/commands/ "$hint"
  [[ -f $lw/.claude/settings.json ]] && _fefo_legacy .claude/settings.json "$hint"
  [[ -f $lw/.opencode/agents/fefo.md ]] && _fefo_legacy .opencode/agents/fefo.md "$hint"
  unfunction _fefo_legacy
  [[ -z $ws ]] && (( legacy > 0 )) && ((fails++))

  print -r -- "FEFO itself: reinstall with the built-in installer: curl -fsSL https://raw.githubusercontent.com/campanafernando/FEFO/main/install.sh | sh"

  if (( fails > 0 )); then
    return 1
  fi
  return 0
}

# ---------- placeholders for other lanes ----------
(( $+functions[_fefo_gen_all] )) || _fefo_gen_all() { _fefo_die "gen lane unavailable: _fefo_gen_all not found"; return 1; }
(( $+functions[_fefo_agents_install] )) || _fefo_agents_install() { _fefo_die "agents lane unavailable: _fefo_agents_install not found"; return 1; }
(( $+functions[_fefo_cmd_graph] )) || _fefo_cmd_graph() { _fefo_die "graph lane unavailable: _fefo_cmd_graph not found"; return 1; }
(( $+functions[_fefo_cmd_agents] )) || _fefo_cmd_agents() { _fefo_die "agents lane unavailable: _fefo_cmd_agents not found"; return 1; }
(( $+functions[_fefo_cmd_vault] )) || _fefo_cmd_vault() { _fefo_die "vault lane unavailable: _fefo_cmd_vault not found"; return 1; }
# lane vault (lib/vault.zsh) provides _fefo_cmd_vault; sourced last, overrides the placeholder
if [[ -f ${FEFO_HOME:-}/lib/vault.zsh ]]; then source "${FEFO_HOME}/lib/vault.zsh"; fi