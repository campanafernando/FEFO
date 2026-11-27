# lib/agents.zsh — `fefo agents` (§13)

_fefo_agents_fix_file() {
  emulate -L zsh; setopt local_options extended_glob no_unset pipe_fail
  local f=$1 default_src=$2
  [[ -f $f ]] || return 0
  local tmp; tmp=$(mktemp) || return 0
  awk '
    BEGIN { inside=0 }
    NR==1 && $0=="---" { inside=1; print; next }
    inside && $0=="---" { inside=0; print; next }
    inside && $0 ~ /^[[:space:]]*model:/ { next }
    { print }
  ' "$f" > "$tmp" 2>/dev/null
  local first close
  first=$(head -n 1 "$tmp" 2>/dev/null)
  close=$(awk 'NR>1 && $0=="---" {print NR; exit}' "$tmp" 2>/dev/null)
  if [[ $first != "---" || -z $close ]]; then
    if [[ -f $default_src/${f:t} ]]; then
      cp -- "$default_src/${f:t}" "$f"
    else
      rm -f -- "$f"
    fi
    rm -f -- "$tmp"
    return 0
  fi
  local fm; fm=$(sed -n "2,$((close-1))p" "$tmp" 2>/dev/null)
  local is_sub=0 is_pri=0
  if print -r -- "$fm" | grep -qE '^[[:space:]]*mode:[[:space:]]*subagent[[:space:]]*$'; then
    is_sub=1
  fi
  if print -r -- "$fm" | grep -qE '^[[:space:]]*mode:[[:space:]]*primary[[:space:]]*$'; then
    is_pri=1
  fi
  if (( is_pri )) || (( ! is_sub )); then
    if [[ -f $default_src/${f:t} ]]; then
      cp -- "$default_src/${f:t}" "$f"
    else
      rm -f -- "$f"
    fi
    rm -f -- "$tmp"
    return 0
  fi
  mv -- "$tmp" "$f"
  return 0
}

_fefo_agents_install() {
  emulate -L zsh; setopt local_options extended_glob no_unset pipe_fail
  local mode=${1:-default}
  local force=0
  case ${2:-} in --force|1|true) force=1 ;; esac

  local ws=${FEFO_WS:-}
  if [[ -z $ws ]]; then
    ws=$(_fefo_root 2>/dev/null) || true
  fi
  if [[ -z $ws ]]; then
    if typeset -f _fefo_die >/dev/null; then _fefo_die "no workspace root"; else print -u2 "fefo: no workspace root"; fi
    return 1
  fi
  local home=${FEFO_HOME:-}
  if [[ -z $home ]]; then
    if typeset -f _fefo_die >/dev/null; then _fefo_die "FEFO_HOME not set"; else print -u2 "fefo: FEFO_HOME not set"; fi
    return 1
  fi

  local srcdir=$home/.opencode/agents
  local dstdir=$ws/.opencode/agents
  mkdir -p -- "$dstdir"

  local created=0 updated=0 kept=0
  local f name existed
  for f in "$srcdir"/*.md(N); do
    [[ -f $f ]] || continue
    name=${f:t}
    existed=0
    [[ -e "$dstdir/$name" ]] && existed=1
    if (( existed && force == 0 )); then
      (( kept++ ))
    else
      cp -- "$f" "$dstdir/$name"
      if (( existed )); then
        (( updated++ ))
      else
        (( created++ ))
      fi
    fi
  done

  if [[ $mode == default ]]; then
    if typeset -f _fefo_info >/dev/null; then _fefo_info "agents: created=$created updated=$updated kept=$kept"; else print "agents: created=$created updated=$updated kept=$kept"; fi
    return 0
  fi

  # ai mode
  local model=${FEFO_AIMODEL:-}
  if [[ -z $model && ${FEFO_MODE:-} == "default" ]]; then
    model=${FEFO_SUBMODEL:-}
  fi
  if [[ -z $model ]]; then
    model=$(opencode models 2>/dev/null | grep -- '-free' | head -n 1)
  fi
  if [[ -z $model ]]; then
    if typeset -f _fefo_warn >/dev/null; then _fefo_warn "no model available for agents job; keeping default set"; else print -u2 "fefo: warning: no model available for agents job; keeping default set"; fi
    if typeset -f _fefo_info >/dev/null; then _fefo_info "agents: created=$created updated=$updated kept=$kept"; else print "agents: created=$created updated=$updated kept=$kept"; fi
    return 0
  fi

  local tpl=$home/templates/agents-prompt.md
  if [[ ! -f $tpl ]]; then
    if typeset -f _fefo_warn >/dev/null; then _fefo_warn "agents prompt template missing; keeping default set"; else print -u2 "fefo: warning: agents prompt template missing; keeping default set"; fi
    if typeset -f _fefo_info >/dev/null; then _fefo_info "agents: created=$created updated=$updated kept=$kept"; else print "agents: created=$created updated=$updated kept=$kept"; fi
    return 0
  fi

  local name_ws=${FEFO_NAME:-workspace}

  local repo_table=$'| Repo | Path | Role | Stack |\n|---|---|---|---|'
  if [[ -v FEFO_REPOS ]] && (( ${#FEFO_REPOS[@]} > 0 )); then
    local r
    for r in "${FEFO_REPOS[@]}"; do
      local rp="" rrole="" rstack=""
      if [[ -v FEFO_R_PATH ]]; then rp=${FEFO_R_PATH[$r]:-}; fi
      if [[ -v FEFO_R_ROLE ]]; then rrole=${FEFO_R_ROLE[$r]:-}; fi
      if [[ -v FEFO_R_STACK ]]; then rstack=${FEFO_R_STACK[$r]:-}; fi
      repo_table+=$'\n'"| $r | $rp | $rrole | $rstack |"
    done
  fi

  local agent_list=""
  for f in "$srcdir"/*.md(N); do
    [[ -f $f ]] || continue
    agent_list+="- ${f:t}"$'\n'
  done

  local tpl_content; tpl_content=$(<"$tpl")
  local prompt=${tpl_content//@@NAME@@/$name_ws}
  prompt=${prompt//@@REPO_TABLE@@/$repo_table}
  prompt=${prompt//@@AGENT_LIST@@/$agent_list}

  local rc=0
  (
    cd -- "$ws" && opencode run --model "$model" --auto --title "fefo agents" "$prompt"
  )
  rc=$?

  if (( rc != 0 )); then
    if typeset -f _fefo_warn >/dev/null; then _fefo_warn "agents job failed; keeping default set"; else print -u2 "fefo: warning: agents job failed; keeping default set"; fi
    if typeset -f _fefo_info >/dev/null; then _fefo_info "agents: created=$created updated=$updated kept=$kept"; else print "agents: created=$created updated=$updated kept=$kept"; fi
    return 0
  fi

  local af
  for af in "$dstdir"/*.md(N); do
    [[ -f $af ]] || continue
    _fefo_agents_fix_file "$af" "$srcdir"
  done

  local specialists=0
  for af in "$dstdir"/*-specialist.md(N); do
    [[ -f $af ]] && (( specialists++ ))
  done

  if typeset -f _fefo_info >/dev/null; then _fefo_info "agents: created=$created updated=$updated kept=$kept specialists=$specialists"; else print "agents: created=$created updated=$updated kept=$kept specialists=$specialists"; fi
  return 0
}

_fefo_cmd_agents() {
  emulate -L zsh; setopt local_options extended_glob no_unset pipe_fail
  local mode="" force=0
  local a
  for a in "$@"; do
    case $a in
      --ai) mode=ai ;;
      --default) mode=default ;;
      --force) force=1 ;;
      *)
        if typeset -f _fefo_die >/dev/null; then _fefo_die "unknown arg: $a"; else print -u2 "fefo: unknown arg: $a"; fi
        return 2
        ;;
    esac
  done
  [[ -z $mode ]] && mode=${FEFO_AGENTS:-default}
  if (( force )); then
    _fefo_agents_install "$mode" --force
  else
    _fefo_agents_install "$mode"
  fi
}
