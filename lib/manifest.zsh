emulate -L zsh
setopt local_options extended_glob no_unset pipe_fail typeset_silent

typeset -g FEFO_NAME=""
typeset -g FEFO_MODE=cheap
typeset -g FEFO_SUBMODEL=""
typeset -g FEFO_FALLBACK=auto
typeset -g FEFO_PARALLEL=4
typeset -g FEFO_HANDOFF_ENV=${FEFO_HANDOFF:-}  # caller override, survives manifest defaults
typeset -g FEFO_HANDOFF=/var/tmp/fefo
typeset -g FEFO_BROWSE=1
typeset -g FEFO_VAULT=1
typeset -g FEFO_CLAUDE=1
typeset -g FEFO_AGENTS=default
typeset -g FEFO_AIMODEL=""
typeset -g FEFO_MODEL=""
typeset -ga FEFO_PLUGINS=()
typeset -ga FEFO_REPOS=()
typeset -gA FEFO_R_PATH FEFO_R_ROLE FEFO_R_STACK FEFO_R_VAULT FEFO_R_TEST FEFO_R_LINT FEFO_R_BUILD FEFO_R_RUN
typeset -ga FEFO_MCPS=()
typeset -gA FEFO_M_TYPE FEFO_M_TARGET FEFO_M_HEADERS

_fefo_manifest_reset() {
  emulate -L zsh
  setopt local_options extended_glob no_unset pipe_fail typeset_silent
  FEFO_NAME=""
  FEFO_MODE=cheap
  FEFO_SUBMODEL=""
  FEFO_FALLBACK=auto
  FEFO_PARALLEL=4
  FEFO_HANDOFF=/var/tmp/fefo
  FEFO_BROWSE=1
  FEFO_VAULT=1
  FEFO_CLAUDE=1
  FEFO_AGENTS=default
  FEFO_AIMODEL=""
  FEFO_MODEL=""
  FEFO_PLUGINS=()
  FEFO_REPOS=()
  FEFO_R_PATH=()
  FEFO_R_ROLE=()
  FEFO_R_STACK=()
  FEFO_R_VAULT=()
  FEFO_R_TEST=()
  FEFO_R_LINT=()
  FEFO_R_BUILD=()
  FEFO_R_RUN=()
  FEFO_MCPS=()
  FEFO_M_TYPE=()
  FEFO_M_TARGET=()
  FEFO_M_HEADERS=()
}

_fefo_manifest_parse() {
  emulate -L zsh
  setopt local_options extended_glob no_unset pipe_fail typeset_silent
  local file=$1
  [[ -f $file ]] || { _fefo_die "manifest not found: $file"; return 1; }
  local lineno=0
  local line
  while IFS= read -r line || [[ -n $line ]]; do
    ((lineno++))
    local -a words
    words=(${(z)line})
    (( ${#words} == 0 )) && continue
    words=(${(Q)words})
    local stmt=$words[1]
    case $stmt in
      fefo)
        [[ ${words[2]:-} == 2 ]] || { _fefo_die "$file:$lineno: expected 'fefo 2'"; return 1; }
        ;;
      workspace)
        FEFO_NAME=${words[2]:-}
        ;;
      subagents)
        if [[ ${words[2]:-} == cheap ]]; then
          FEFO_MODE=cheap
          FEFO_SUBMODEL=""
        elif [[ ${words[2]:-} == default ]]; then
          FEFO_MODE=default
          FEFO_SUBMODEL=${words[3]:-}
        else
          _fefo_die "$file:$lineno: bad subagents"; return 1
        fi
        ;;
      fallback)
        FEFO_FALLBACK=${words[2]:-auto}
        ;;
      parallel)
        FEFO_PARALLEL=${words[2]:-4}
        ;;
      handoff)
        FEFO_HANDOFF=${words[2]:-}
        ;;
      browse)
        [[ ${words[2]:-} == on ]] && FEFO_BROWSE=1 || FEFO_BROWSE=0
        ;;
      vault)
        [[ ${words[2]:-} == on ]] && FEFO_VAULT=1 || FEFO_VAULT=0
        ;;
      codegraph) ;;  # shortcut: legacy manifests; FEFO owns the graph now
      claude)
        [[ ${words[2]:-} == on ]] && FEFO_CLAUDE=1 || FEFO_CLAUDE=0
        ;;
      agents)
        FEFO_AGENTS=${words[2]:-default}
        ;;
      ai-model)
        FEFO_AIMODEL=${words[2]:-}
        ;;
      model)
        FEFO_MODEL=${words[2]:-}
        ;;
      plugin)
        FEFO_PLUGINS+=("${words[2]:-}")
        ;;
      repo)
        local name=${words[2]:-}
        local rpath=${words[3]:-}
        [[ -n $name && -n $rpath ]] || { _fefo_die "$file:$lineno: bad repo"; return 1; }
        FEFO_REPOS+=("$name")
        FEFO_R_PATH[$name]=$rpath
        FEFO_R_ROLE[$name]=service
        FEFO_R_STACK[$name]=generic
        FEFO_R_VAULT[$name]=1
        FEFO_R_TEST[$name]=""
        FEFO_R_LINT[$name]=""
        FEFO_R_BUILD[$name]=""
        FEFO_R_RUN[$name]=""
        local i
        for ((i=4;i<=${#words};i++)); do
          local w=$words[i]
          [[ $w == *=* ]] || { _fefo_die "$file:$lineno: bad repo attr '$w'"; return 1; }
          local key=${w%%=*}
          local val=${w#*=}
          case $key in
            role) FEFO_R_ROLE[$name]=$val ;;
            stack) FEFO_R_STACK[$name]=$val ;;
            vault) [[ $val == off ]] && FEFO_R_VAULT[$name]=0 || FEFO_R_VAULT[$name]=1 ;;
            codegraph) ;;  # shortcut: legacy manifests; ignored
            test) FEFO_R_TEST[$name]=$val ;;
            lint) FEFO_R_LINT[$name]=$val ;;
            build) FEFO_R_BUILD[$name]=$val ;;
            run) FEFO_R_RUN[$name]=$val ;;
            *) _fefo_die "$file:$lineno: unknown repo attr '$key'"; return 1 ;;
          esac
        done
        # default role from stack if still service? keep detected? manifest should have role
        ;;
      mcp)
        local mname=${words[2]:-}
        local mtype=${words[3]:-}
        [[ -n $mname && ( $mtype == remote || $mtype == local ) ]] || { _fefo_die "$file:$lineno: bad mcp"; return 1; }
        FEFO_MCPS+=("$mname")
        FEFO_M_TYPE[$mname]=$mtype
        if [[ $mtype == remote ]]; then
          FEFO_M_TARGET[$mname]=${words[4]:-}
          local headers=""
          local i
          for ((i=5;i<=${#words};i++)); do
            local w=$words[i]
            if [[ $w == header=* ]]; then
              local hv=${w#header=}
              if [[ -z $headers ]]; then headers=$hv; else headers+=$'\n'$hv; fi
            fi
          done
          FEFO_M_HEADERS[$mname]=$headers
        else
          local joined=""
          local first=1
          local i
          for ((i=4;i<=${#words};i++)); do
            if (( first )); then joined=${words[i]}; first=0; else joined+=$'\0'${words[i]}; fi
          done
          FEFO_M_TARGET[$mname]=$joined
          FEFO_M_HEADERS[$mname]=""
        fi
        ;;
      *)
        _fefo_die "$file:$lineno: unknown statement '$stmt'"; return 1
        ;;
    esac
  done < "$file"
  return 0
}

_fefo_manifest_load() {
  emulate -L zsh
  setopt local_options extended_glob no_unset pipe_fail typeset_silent
  _fefo_manifest_reset
  local file=${1:-}
  if [[ -z $file ]]; then
    local ws
    ws=$(_fefo_root) || return 1
    file=$ws/.fefo/workspace.zsh
  fi
  [[ -f $file ]] || return 1
  _fefo_manifest_parse "$file"
}

_fefo_userconfig_load() {
  emulate -L zsh
  setopt local_options extended_glob no_unset pipe_fail typeset_silent
  local file=${XDG_CONFIG_HOME:-$HOME/.config}/fefo/config.zsh
  [[ -f $file ]] || return 0
  # seed globals only; parse into a temp by resetting? We reset then parse, but that wipes workspace defaults already? 
  # User config is loaded before manifest; reset defaults first.
  _fefo_manifest_reset
  _fefo_manifest_parse "$file"
}

_fefo_manifest_save() {
  emulate -L zsh
  setopt local_options extended_glob no_unset pipe_fail typeset_silent
  local file=${1:-}
  if [[ -z $file ]]; then
    local ws
    ws=$(_fefo_root) || return 1
    file=$ws/.fefo/workspace.zsh
  fi
  local dir=${file:h}
  mkdir -p "$dir" 2>/dev/null
  local tmp
  tmp=$(mktemp "$dir/.manifest.XXXXXX") || return 1
  {
    print -r -- "fefo 2"
    print -r -- "workspace ${(q-)FEFO_NAME}"
    if [[ $FEFO_MODE == default ]]; then
      print -r -- "subagents default ${(q-)FEFO_SUBMODEL}"
    else
      print -r -- "subagents cheap"
    fi
    print -r -- "fallback ${(q-)FEFO_FALLBACK}"
    print -r -- "parallel $FEFO_PARALLEL"
    print -r -- "handoff ${(q-)FEFO_HANDOFF}"
    if (( FEFO_BROWSE )); then print -r -- "browse on"; else print -r -- "browse off"; fi
    if (( FEFO_VAULT )); then print -r -- "vault on"; else print -r -- "vault off"; fi
    if (( FEFO_CLAUDE )); then print -r -- "claude on"; else print -r -- "claude off"; fi
    print -r -- "agents $FEFO_AGENTS"
    [[ -n $FEFO_AIMODEL ]] && print -r -- "ai-model ${(q-)FEFO_AIMODEL}"
    [[ -n $FEFO_MODEL ]] && print -r -- "model ${(q-)FEFO_MODEL}"
    local p
    for p in "${FEFO_PLUGINS[@]}"; do
      print -r -- "plugin ${(q-)p}"
    done
    local r
    for r in "${FEFO_REPOS[@]}"; do
      local rv=on
      (( FEFO_R_VAULT[$r] )) || rv=off
      local rl="repo ${(q-)r} ${(q-)FEFO_R_PATH[$r]} role=${(q-)FEFO_R_ROLE[$r]} stack=${(q-)FEFO_R_STACK[$r]} vault=$rv"
      [[ -n ${FEFO_R_TEST[$r]} ]] && rl+=" test=${(q-)FEFO_R_TEST[$r]}"
      [[ -n ${FEFO_R_LINT[$r]} ]] && rl+=" lint=${(q-)FEFO_R_LINT[$r]}"
      [[ -n ${FEFO_R_BUILD[$r]} ]] && rl+=" build=${(q-)FEFO_R_BUILD[$r]}"
      [[ -n ${FEFO_R_RUN[$r]} ]] && rl+=" run=${(q-)FEFO_R_RUN[$r]}"
      print -r -- "$rl"
    done
    local m
    for m in "${FEFO_MCPS[@]}"; do
      if [[ ${FEFO_M_TYPE[$m]} == remote ]]; then
        local line="mcp ${(q-)m} remote ${(q-)FEFO_M_TARGET[$m]}"
        local hdr
        local -a hdrs
        hdrs=(${(f)FEFO_M_HEADERS[$m]})
        for hdr in "${hdrs[@]}"; do
          [[ -z $hdr ]] && continue
          line+=" header=${(q-)hdr}"
        done
        print -r -- "$line"
      else
        local -a parts
        parts=(${(ps:\0:)FEFO_M_TARGET[$m]})
        local line="mcp ${(q-)m} local"
        local w
        for w in "${parts[@]}"; do
          line+=" ${(q-)w}"
        done
        print -r -- "$line"
      fi
    done
  } > "$tmp"
  mv -f "$tmp" "$file"
}