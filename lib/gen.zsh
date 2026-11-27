# gen.zsh — generators. Each _fefo_gen_* prints its file to stdout.

_fefo_gen_opencode() {
  emulate -L zsh; setopt local_options extended_glob no_unset pipe_fail
  local ws=$FEFO_WS
  local name=$FEFO_NAME
  local template_checkout=0
  [[ -f "$ws/.fefo/template" ]] && template_checkout=1

  local has_plugins=0 has_model=0
  (( ${#FEFO_PLUGINS[@]} > 0 )) && has_plugins=1
  [[ -n ${FEFO_MODEL:-} ]] && has_model=1

  print -r -- '{'
  print -r -- '  "$schema": "https://opencode.ai/config.json",'
  if (( template_checkout )); then
    print -r -- '  "instructions": [".fefo/AGENTS.md", "AGENTS.local.md"],'
  else
    print -r -- '  "instructions": ["AGENTS.md", "AGENTS.local.md"],'
  fi

  # permissions
  local -a asks=(
    "git commit *" "git -C * commit *"
    "git push *" "git -C * push *"
    "git merge *" "git -C * merge *"
    "git rebase *" "git -C * rebase *"
    "git reset --hard*" "git -C * reset --hard*"
  )
  local -a denies=(
    "git push --force*" "git push -f *" "git push * --force*" "git push * -f *"
    "git -C * push --force*" "git -C * push -f *" "git -C * push * --force*" "git -C * push * -f *"
  )
  local total=$(( ${#asks[@]} + ${#denies[@]} ))
  local idx=0 r
  print -r -- '  "permissions": ['
  for r in "${asks[@]}"; do
    (( idx++ ))
    local comma=''; (( idx < total )) && comma=','
    print -r -- "    {\"action\": \"shell\", \"resource\": $(_fefo_json "$r"), \"effect\": \"ask\"}$comma"
  done
  for r in "${denies[@]}"; do
    (( idx++ ))
    local comma=''; (( idx < total )) && comma=','
    print -r -- "    {\"action\": \"shell\", \"resource\": $(_fefo_json "$r"), \"effect\": \"deny\"}$comma"
  done
  print -r -- '  ],'

  print -r -- '  "watcher": { "ignore": ["**/.codegraph/**", "**/node_modules/**", "**/.venv/**", "**/venv/**", "**/__pycache__/**"] },'
  print -r -- '  "experimental": { "subagent_depth": 2, "todo": true },'

  # references
  local -a refentries=()
  local repo role stack rpath slug
  for repo in "${FEFO_REPOS[@]}"; do
    role=${FEFO_R_ROLE[$repo]:-}; stack=${FEFO_R_STACK[$repo]:-}; rpath=${FEFO_R_PATH[$repo]:-}; slug=$(_fefo_slug "$repo")
    refentries+=("    $(_fefo_json "$slug"): {\"path\": $(_fefo_json "$rpath"), \"description\": $(_fefo_json "$role repository ($stack) in the $name workspace.")}")
  done
  if (( ${#refentries[@]} == 0 )); then
    print -r -- '  "references": {},'
  else
    print -r -- '  "references": {'
    local i=0
    for ((i=1;i<=${#refentries[@]};i++)); do
      if (( i < ${#refentries[@]} )); then
        print -r -- "${refentries[$i]},"
      else
        print -r -- "${refentries[$i]}"
      fi
    done
    print -r -- '  },'
  fi

  # mcp servers
  local -a srv=()
  local cg_on=0
  if (( ${FEFO_CODEGRAPH:-1} )); then
    for repo in "${FEFO_REPOS[@]}"; do
      if (( ${FEFO_R_CG[$repo]:-0} )); then cg_on=1; break; fi
    done
  fi
  if (( cg_on )); then
    srv+=("      \"codegraph\": {\"type\": \"local\", \"command\": [\"codegraph\", \"serve\", \"--mcp\"]}")
  fi
  if (( ${FEFO_VAULT:-0} )); then
    srv+=("      \"vault\": {\"type\": \"local\", \"command\": [\"codegraph\", \"serve\", \"--mcp\", \"--no-watch\", \"--path\", \"docs/vault\"]}")
  fi
  if (( ${FEFO_BROWSE:-0} )); then
    srv+=("      \"browse\": {\"type\": \"local\", \"command\": [\"zsh\", \".opencode/bin/browse-mcp\"]}")
  fi
  local m mtype mtarget
  for m in "${FEFO_MCPS[@]}"; do
    mtype=${FEFO_M_TYPE[$m]}
    mtarget=${FEFO_M_TARGET[$m]}
    if [[ $mtype == local ]]; then
      local -a w=()
      w=("${(@0)${(Q)mtarget}}")
      local cmdjson='["zsh", ".opencode/bin/mcp"'
      local wd
      for wd in "${w[@]}"; do
        cmdjson+=', '$(_fefo_json "$wd")
      done
      cmdjson+=']'
      srv+=("      $(_fefo_json "$m"): {\"type\": \"local\", \"command\": $cmdjson}")
    else
      local headersjson=''
      local hlines=${FEFO_M_HEADERS[$m]:-}
      if [[ -n $hlines ]]; then
        local -a harr=("${(f)hlines}")
        local firsth=1
        headersjson='{'
        local hl k v
        for hl in "${harr[@]}"; do
          [[ -z $hl ]] && continue
          k=${hl%%=*}; v=${hl#*=}
          if (( firsth )); then firsth=0; else headersjson+=','; fi
          headersjson+=$'\n        '$(_fefo_json "$k")': '$(_fefo_json "$v")
        done
        headersjson+=$'\n      }'
      else
        headersjson='{}'
      fi
      if [[ $headersjson == '{}' ]]; then
        srv+=("      $(_fefo_json "$m"): {\"type\": \"remote\", \"url\": $(_fefo_json "$mtarget")}")
      else
        srv+=("      $(_fefo_json "$m"): {\"type\": \"remote\", \"url\": $(_fefo_json "$mtarget"), \"headers\": $headersjson}")
      fi
    fi
  done

  local mcp_comma=''
  (( has_plugins || has_model )) && mcp_comma=','
  if (( ${#srv[@]} == 0 )); then
    print -r -- "  \"mcp\": { \"timeout\": { \"startup\": 90000 }, \"servers\": {} }$mcp_comma"
  else
    print -r -- '  "mcp": { "timeout": { "startup": 90000 }, "servers": {'
    local i=0
    for ((i=1;i<=${#srv[@]};i++)); do
      if (( i < ${#srv[@]} )); then
        print -r -- "${srv[$i]},"
      else
        print -r -- "${srv[$i]}"
      fi
    done
    print -r -- "  } }$mcp_comma"
  fi

  if (( has_plugins )); then
    local plugin_comma=''
    (( has_model )) && plugin_comma=','
    print -r -- '  "plugins": ['
    local i=0
    for ((i=1;i<=${#FEFO_PLUGINS[@]};i++)); do
      local comma=''
      (( i < ${#FEFO_PLUGINS[@]} )) && comma=','
      print -r -- "    $(_fefo_json "${FEFO_PLUGINS[$i]}")$comma"
    done
    print -r -- "  ]$plugin_comma"
  fi
  if (( has_model )); then
    print -r -- "  \"model\": $(_fefo_json "$FEFO_MODEL")"
  fi
  print -r -- '}'
}

_fefo_gen_agents() {
  emulate -L zsh; setopt local_options extended_glob no_unset pipe_fail
  local tpl="${FEFO_HOME}/templates/AGENTS.md"
  [[ -f $tpl ]] || { _fefo_die "template missing: $tpl"; return 1; }
  local content; content=$(<"$tpl")
  local name=$FEFO_NAME

  local repo_table="| Repo | Path | Role | Stack | CodeGraph | Commands |"$'\n'"|---|---|---|---|---|---|"
  local repo
  for repo in "${FEFO_REPOS[@]}"; do
    local role=${FEFO_R_ROLE[$repo]:-} stack=${FEFO_R_STACK[$repo]:-} rpath=${FEFO_R_PATH[$repo]:-}
    local cg=off; (( ${FEFO_R_CG[$repo]:-0} )) && cg=on
    local test=${FEFO_R_TEST[$repo]:-} lint=${FEFO_R_LINT[$repo]:-} build=${FEFO_R_BUILD[$repo]:-} run=${FEFO_R_RUN[$repo]:-}
    local -a parts=()
    [[ -n $test ]] && parts+=("test: $test")
    [[ -n $lint ]] && parts+=("lint: $lint")
    [[ -n $build ]] && parts+=("build: $build")
    [[ -n $run ]] && parts+=("run: $run")
    local cmds="${(j: · :)parts}"
    [[ -z $cmds ]] && cmds="—"
    repo_table+=$'\n'"| $repo | $rpath | $role | $stack | $cg | $cmds |"
  done

  local codegraph=""
  if (( ${FEFO_CODEGRAPH:-1} )); then
    for repo in "${FEFO_REPOS[@]}"; do
      if (( ${FEFO_R_CG[$repo]:-0} )); then
        local rpath=${FEFO_R_PATH[$repo]:-}
        codegraph+="- \`$repo\` → projectPath \`<workspace>/$rpath\`"$'\n'
      fi
    done
  fi

  local vault=""
  if (( ${FEFO_VAULT:-0} )); then
    vault="; MCP server \`vault\`, \`codegraph_context\`/\`codegraph_search\` on notes"
  fi

  local model_policy
  if [[ ${FEFO_MODE:-cheap} == default ]]; then
    local m=${FEFO_SUBMODEL:-${FEFO_MODEL:-your model}}
    model_policy="- Mode **default**: pin \`$m\` on every subagent call."
  else
    model_policy="- Mode **cheap**: at dispatch time pick the strongest free OpenCode model (models tool: cost 0, active, newest family, has a \`max\` variant, largest context); pin it on every subagent call and keep the next two strongest free models as the ladder."
  fi

  local fallback
  if [[ ${FEFO_FALLBACK:-auto} == auto ]]; then
    fallback="your own model (omit \`model\`)"
  else
    fallback="\`${FEFO_FALLBACK}\`"
  fi

  local parallel=${FEFO_PARALLEL:-4}
  local handoff="${FEFO_HANDOFF:-/var/tmp/fefo}/$(_fefo_slug "${FEFO_NAME}")"

  content=${content//@@NAME@@/$name}
  content=${content//@@REPO_TABLE@@/$repo_table}
  content=${content//@@CODEGRAPH@@/$codegraph}
  content=${content//@@VAULT@@/$vault}
  content=${content//@@MODEL_POLICY@@/$model_policy}
  content=${content//@@FALLBACK@@/$fallback}
  content=${content//@@PARALLEL@@/$parallel}
  content=${content//@@HANDOFF@@/$handoff}

  print -r -- "$content"
}

_fefo_gen_agents_local() {
  emulate -L zsh; setopt local_options extended_glob no_unset pipe_fail
  print -r -- '<!-- FEFO never overwrites this file. Add workspace-specific rules here. -->'
  print -r -- '# Local instructions'
  print -r -- ''
  print -r -- '- Add project-specific conventions, owners, and delivery notes here.'
  print -r -- '- Keep durable domain knowledge in `docs/vault/`, not in this file.'
}

_fefo_gen_vault_index() {
  emulate -L zsh; setopt local_options extended_glob no_unset pipe_fail
  local name=$FEFO_NAME
  print -r -- "# $name Knowledge Vault"
  print -r -- ''
  print -r -- 'Start with the federation snapshot and add durable knowledge under `repos/`.'
  print -r -- ''
  print -r -- '- [Federation](federation.md)'
  print -r -- '- [Decisions](decisions.md)'
  print -r -- '- [Repository notes](repos/)'
  local repo slug
  for repo in "${FEFO_REPOS[@]}"; do
    slug=$(_fefo_slug "$repo")
    local role=${FEFO_R_ROLE[$repo]:-} stack=${FEFO_R_STACK[$repo]:-}
    print -r -- "- [$repo](repos/$slug.md) — $role / $stack"
  done
}

_fefo_gen_vault_federation() {
  emulate -L zsh; setopt local_options extended_glob no_unset pipe_fail
  local name=$FEFO_NAME
  print -r -- '# Federation'
  print -r -- ''
  print -r -- "Workspace: **$name**"
  print -r -- ''
  print -r -- '| Repo | Path | Role | Stack | CodeGraph |'
  print -r -- '|---|---|---|---|---|'
  local repo
  for repo in "${FEFO_REPOS[@]}"; do
    local role=${FEFO_R_ROLE[$repo]:-} stack=${FEFO_R_STACK[$repo]:-} rpath=${FEFO_R_PATH[$repo]:-}
    local cg=off; (( ${FEFO_R_CG[$repo]:-0} )) && cg=on
    print -r -- "| \`$repo\` | \`$rpath\` | \`$role\` | \`$stack\` | \`$cg\` |"
  done
  print -r -- ''
  print -r -- '## Generated adapters'
  print -r -- ''
  print -r -- '- OpenCode: `opencode.json`, `.opencode/`'
  print -r -- ''
  print -r -- '## Model'
  print -r -- ''
  print -r -- "Mode: ${FEFO_MODE:-cheap}."
  print -r -- ''
  if (( ${#FEFO_REPOS[@]} > 0 )); then
    print -r -- '## Repository commands'
    print -r -- ''
    print -r -- '| Repo | Test | Lint | Build / Run |'
    print -r -- '|---|---|---|---|'
    for repo in "${FEFO_REPOS[@]}"; do
      local test=${FEFO_R_TEST[$repo]:-} lint=${FEFO_R_LINT[$repo]:-} build=${FEFO_R_BUILD[$repo]:-} run=${FEFO_R_RUN[$repo]:-}
      local br="—"
      [[ -n $build ]] && br=$build
      [[ -z $build && -n $run ]] && br=$run
      print -r -- "| \`$repo\` | \`${test:-—}\` | \`${lint:-—}\` | \`$br\` |"
    done
    print -r -- ''
  fi
}

_fefo_gen_vault_repo() {
  emulate -L zsh; setopt local_options extended_glob no_unset pipe_fail
  local repo=$1
  local role=${FEFO_R_ROLE[$repo]:-} stack=${FEFO_R_STACK[$repo]:-} rpath=${FEFO_R_PATH[$repo]:-}
  local test=${FEFO_R_TEST[$repo]:-} lint=${FEFO_R_LINT[$repo]:-} build=${FEFO_R_BUILD[$repo]:-} run=${FEFO_R_RUN[$repo]:-}
  local cg=off; (( ${FEFO_R_CG[$repo]:-0} )) && cg=on
  local slug=$(_fefo_slug "$repo")
  print -r -- "# $repo"
  print -r -- ''
  print -r -- '| Field | Value |'
  print -r -- '|---|---|'
  print -r -- "| Role | \`$role\` |"
  print -r -- "| Stack | \`$stack\` |"
  print -r -- "| Path | \`$rpath\` |"
  print -r -- "| CodeGraph | \`$cg\` |"
  [[ -n $test ]] && print -r -- "| Test | \`$test\` |"
  [[ -n $lint ]] && print -r -- "| Lint | \`$lint\` |"
  [[ -n $build ]] && print -r -- "| Build | \`$build\` |"
  [[ -n $run ]] && print -r -- "| Run | \`$run\` |"
  print -r -- ''
  print -r -- "Read \`$rpath/AGENTS.md\` first."
  print -r -- ''
  local marker='<!-- fefo:notes — yours, kept by sync -->'
  print -r -- "$marker"
  local ws=$FEFO_WS
  local file="$ws/docs/vault/repos/$slug.md"
  local preserved=""
  if [[ -f $file ]]; then
    local content; content=$(<"$file")
    local after=${content#*$marker}
    if [[ $after != "$content" ]]; then
      preserved=${after#$'\n'}
    fi
  fi
  if [[ -z $preserved ]]; then
    print -r -- ''
    print -r -- '## Notes'
    print -r -- ''
    print -r -- '- (your domain notes here)'
  else
    print -r -- "$preserved"
  fi
}

_fefo_gen_vault_decisions() {
  emulate -L zsh; setopt local_options extended_glob no_unset pipe_fail
  local tpl="${FEFO_HOME}/templates/vault/decisions.md"
  if [[ -f $tpl ]]; then
    cat "$tpl"
  else
    print -r -- '# Decisions'
    print -r -- ''
    print -r -- 'Record durable decisions here with date, context, decision, and consequence.'
    print -r -- 'Do not use this file as a task tracker.'
  fi
}

_fefo_gen_codegraph_readme() {
  emulate -L zsh; setopt local_options extended_glob no_unset pipe_fail
  print -r -- '# CodeGraph'
  print -r -- ''
  print -r -- 'FEFO indexes each federated repository separately. Run:'
  print -r -- ''
  print -r -- '```sh'
  print -r -- './bin/fefo index'
  print -r -- '```'
  print -r -- ''
  print -r -- "Indexes live in each repository's \`.codegraph/\` directory."
  print -r -- ''
  if (( ${#FEFO_REPOS[@]} > 0 )); then
    print -r -- '## Federated indexes'
    print -r -- ''
    local repo
    for repo in "${FEFO_REPOS[@]}"; do
      if (( ${FEFO_R_CG[$repo]:-0} )); then
        local rpath=${FEFO_R_PATH[$repo]:-}
        print -r -- "- \`$repo\` → \`$rpath/.codegraph/\`"
      fi
    done
    local -a disabled=()
    for repo in "${FEFO_REPOS[@]}"; do
      (( ${FEFO_R_CG[$repo]:-0} )) || disabled+=("$repo")
    done
    if (( ${#disabled[@]} > 0 )); then
      print -r -- ''
      print -r -- "CodeGraph disabled for: ${(j:, :)disabled}."
    fi
    print -r -- ''
  fi
}

_fefo_gen_browse_mcp() {
  emulate -L zsh; setopt local_options extended_glob no_unset pipe_fail
  local tpl="${FEFO_HOME}/templates/browse-mcp"
  [[ -f $tpl ]] && { cat "$tpl"; return 0; }
  print -r -- '#!/usr/bin/env zsh'
}

_fefo_gen_mcp() {
  emulate -L zsh; setopt local_options extended_glob no_unset pipe_fail
  local tpl="${FEFO_HOME}/templates/mcp"
  [[ -f $tpl ]] && { cat "$tpl"; return 0; }
  print -r -- '#!/usr/bin/env zsh'
}

_fefo_gen_env_example() {
  emulate -L zsh; setopt local_options extended_glob no_unset pipe_fail
  print -r -- '# Workspace environment. Copy to .env and fill secrets. Gitignored.'
  print -r -- '# Example:'
  print -r -- '# DATABASE_URL=postgres://user:pass@localhost/db'
}

_fefo_gen_env_mcp_example() {
  emulate -L zsh; setopt local_options extended_glob no_unset pipe_fail
  print -r -- '# MCP server environment. Copy to .env.mcp and fill. Loaded by .opencode/bin/mcp.'
  print -r -- '# Example:'
  print -r -- '# PG_URL=postgres://user:pass@localhost/db'
}

_fefo_ensure_gitignore() {
  emulate -L zsh; setopt local_options extended_glob no_unset pipe_fail
  local ws=$FEFO_WS
  local gi="$ws/.gitignore"
  local -a lines=('.env' '.env.*' '!.env*.example' '.codegraph/' '*.codegraph.lock')
  local rn rp
  # repos nested inside the workspace are their own Git roots: keep them out of the workspace repo
  for rn in "${FEFO_REPOS[@]}"; do
    rp=${FEFO_R_PATH[$rn]:-}
    [[ -n $rp && $rp != ../* && $rp != /* && $rp != . ]] && lines+=("/${rp%/}/")
  done
  if [[ ! -f $gi ]]; then
    printf '%s\n' "${lines[@]}" > "$gi"
    return 0
  fi
  local l
  for l in "${lines[@]}"; do
    grep -Fxq -- "$l" "$gi" 2>/dev/null || printf '%s\n' "$l" >> "$gi"
  done
}

_fefo_copy_skills() {
  emulate -L zsh; setopt local_options extended_glob no_unset pipe_fail
  local ws=$FEFO_WS home=${FEFO_HOME:-}
  [[ -z $home ]] && return 0
  local skill
  for skill in codegraph vault-search; do
    local src="$home/.agents/skills/$skill/SKILL.md"
    local dst="$ws/.agents/skills/$skill/SKILL.md"
    [[ -f $src ]] || continue
    [[ ${src:A} == ${dst:A} ]] && continue
    mkdir -p "${dst:h}"
    cp -f "$src" "$dst"
  done
}

_fefo_gen_claude_md() {
  emulate -L zsh; setopt local_options extended_glob no_unset pipe_fail
  local ws=$FEFO_WS
  if [[ -f "$ws/.fefo/template" ]]; then
    print -r -- '@.fefo/AGENTS.md'
  else
    print -r -- '@AGENTS.md'
  fi
  print -r -- '@AGENTS.local.md'
  print -r -- 'OpenCode is the primary harness; the subagent model policy applies only inside OpenCode.'
}

_fefo_gen_mcp_json() {
  emulate -L zsh; setopt local_options extended_glob no_unset pipe_fail
  local ws=$FEFO_WS
  local name=$FEFO_NAME
  local template_checkout=0
  [[ -f "$ws/.fefo/template" ]] && template_checkout=1

  # build server list in same order as opencode
  local -a srv=()
  local cg_on=0
  if (( ${FEFO_CODEGRAPH:-1} )); then
    local repo
    for repo in "${FEFO_REPOS[@]}"; do
      if (( ${FEFO_R_CG[$repo]:-0} )); then cg_on=1; break; fi
    done
  fi
  if (( cg_on )); then
    srv+=('codegraph')
  fi
  if (( ${FEFO_VAULT:-0} )); then
    srv+=('vault')
  fi
  if (( ${FEFO_BROWSE:-0} )); then
    srv+=('browse')
  fi
  local m
  for m in "${FEFO_MCPS[@]}"; do
    srv+=("$m")
  done

  print -r -- '{'
  print -r -- '  "mcpServers": {'
    local i=0
  for ((i=1;i<=${#srv[@]};i++)); do
    local s=${srv[$i]}
    local comma=''; (( i < ${#srv[@]} )) && comma=','
    case $s in
      codegraph)
        print -r -- "    \"codegraph\": {\"type\": \"stdio\", \"command\": \"codegraph\", \"args\": [\"serve\", \"--mcp\"]}$comma"
        ;;
      vault)
        print -r -- "    \"vault\": {\"type\": \"stdio\", \"command\": \"codegraph\", \"args\": [\"serve\", \"--mcp\", \"--no-watch\", \"--path\", \"docs/vault\"]}$comma"
        ;;
      browse)
        print -r -- "    \"browse\": {\"type\": \"stdio\", \"command\": \"zsh\", \"args\": [\".opencode/bin/browse-mcp\"]}$comma"
        ;;
      *)
        local mtype=${FEFO_M_TYPE[$s]}
        local mtarget=${FEFO_M_TARGET[$s]}
        if [[ $mtype == local ]]; then
          local -a w=()
          w=("${(@0)${(Q)mtarget}}")
          local argsjson='['$(_fefo_json ".opencode/bin/mcp")
          local wd
          for wd in "${w[@]}"; do
            argsjson+=', '$(_fefo_json "$wd")
          done
          argsjson+=']'
          print -r -- "    $(_fefo_json "$s"): {\"type\": \"stdio\", \"command\": \"zsh\", \"args\": $argsjson}$comma"
        else
          local url=$mtarget
          local hlines=${FEFO_M_HEADERS[$s]:-}
          local headersjson='{}'
          if [[ -n $hlines ]]; then
            local -a harr=("${(f)hlines}")
            local firsth=1
            headersjson='{'
            local hl k v
            for hl in "${harr[@]}"; do
              [[ -z $hl ]] && continue
              k=${hl%%=*}; v=${hl#*=}
              # rewrite {env:VAR} -> ${VAR}
              local repl='${'
              v="${v//\{env:/$repl}"
              if (( firsth )); then firsth=0; else headersjson+=','; fi
              headersjson+=$'\n        '$(_fefo_json "$k")': '$(_fefo_json "$v")
            done
            headersjson+=$'\n      }'
          fi
          if [[ $headersjson == '{}' ]]; then
            print -r -- "    $(_fefo_json "$s"): {\"type\": \"http\", \"url\": $(_fefo_json "$url")}$comma"
          else
            print -r -- "    $(_fefo_json "$s"): {\"type\": \"http\", \"url\": $(_fefo_json "$url"), \"headers\": $headersjson}$comma"
          fi
        fi
        ;;
    esac
  done
  if (( ${#srv[@]} == 0 )); then
    print -r -- '  }'
  else
    print -r -- '  }'
  fi
  print -r -- '}'
}

_fefo_copy_claude_skills() {
  emulate -L zsh; setopt local_options extended_glob no_unset pipe_fail
  local ws=$FEFO_WS home=${FEFO_HOME:-}
  [[ -z $home ]] && return 0
  local skill
  for skill in codegraph vault-search; do
    local src="$home/.agents/skills/$skill/SKILL.md"
    local dst="$ws/.claude/skills/$skill/SKILL.md"
    [[ -f $src ]] || continue
    [[ ${src:A} == ${dst:A} ]] && continue
    mkdir -p "${dst:h}"
    cp -f "$src" "$dst"
  done
}

_fefo_gen_all() {
  emulate -L zsh; setopt local_options extended_glob no_unset pipe_fail
  local ws=$FEFO_WS
  _fefo_emit "opencode.json" _fefo_gen_opencode
  local agents_rel="AGENTS.md"
  [[ -f "$ws/.fefo/template" ]] && agents_rel=".fefo/AGENTS.md"
  _fefo_emit "$agents_rel" _fefo_gen_agents
  _fefo_emit_once "AGENTS.local.md" _fefo_gen_agents_local
  if (( ${FEFO_VAULT:-0} )); then
    if [[ ! -f "$ws/.fefo/template" ]]; then
      mkdir -p "$ws/docs/vault"
      _fefo_emit "docs/vault/00-INDEX.md" _fefo_gen_vault_index
    fi
    mkdir -p "$ws/docs/vault"
    _fefo_emit "docs/vault/federation.md" _fefo_gen_vault_federation
    local repo slug
    for repo in "${FEFO_REPOS[@]}"; do
      slug=$(_fefo_slug "$repo")
      mkdir -p "$ws/docs/vault/repos"
      _fefo_emit "docs/vault/repos/$slug.md" _fefo_gen_vault_repo "$repo"
    done
  fi
  _fefo_emit_once "docs/vault/decisions.md" _fefo_gen_vault_decisions
  if [[ ! -f "$ws/.fefo/template" ]]; then
    mkdir -p "$ws/codegraph"
    _fefo_emit "codegraph/README.md" _fefo_gen_codegraph_readme
  fi
  mkdir -p "$ws/.opencode/bin"
  _fefo_emit ".opencode/bin/mcp" _fefo_gen_mcp
  if (( ${FEFO_BROWSE:-0} )); then
    _fefo_emit ".opencode/bin/browse-mcp" _fefo_gen_browse_mcp
  fi
  chmod +x "$ws/.opencode/bin/mcp" "$ws/.opencode/bin/browse-mcp" 2>/dev/null
  _fefo_emit_once ".env.example" _fefo_gen_env_example
  _fefo_emit_once ".env.mcp.example" _fefo_gen_env_mcp_example
  _fefo_ensure_gitignore
  _fefo_copy_skills
  if (( ${FEFO_CLAUDE:-1} )); then
    local claude_rel="CLAUDE.md"
    _fefo_emit "$claude_rel" _fefo_gen_claude_md
    _fefo_emit ".mcp.json" _fefo_gen_mcp_json
    _fefo_copy_claude_skills
  fi
}