#!/usr/bin/env zsh
# FEFO vault graph: zsh parser + know-graph viewer + vault index loader trigger.

_fefo__trim() {
  emulate -L zsh; setopt local_options extended_glob no_unset pipe_fail typeset_silent
  local v=$1
  v=${v#"${v%%[![:space:]]*}"}
  v=${v%"${v##*[![:space:]]}"}
  printf '%s' "$v"
}

_fefo__graph_add_node() {
  emulate -L zsh; setopt local_options extended_glob no_unset pipe_fail typeset_silent
  local id=$1 kind=$2 label=$3 npath=$4 line=$5
  [[ -n ${_FG_NODE_SEEN[$id]+x} ]] && return
  _FG_NODE_SEEN[$id]=1
  local jid=$(_fefo_json "$id") jkind=$(_fefo_json "$kind") jlabel=$(_fefo_json "$label") jpath=$(_fefo_json "$npath")
  _FG_NODES+=("{\"id\":$jid,\"kind\":$jkind,\"label\":$jlabel,\"path\":$jpath,\"line\":$line}")
}

_fefo__graph_add_edge() {
  emulate -L zsh; setopt local_options extended_glob no_unset pipe_fail typeset_silent
  local s=$1 t=$2 kind=$3 line=$4
  local key="$s|$t|$kind"
  [[ -n ${_FG_EDGE_SEEN[$key]+x} ]] && return
  _FG_EDGE_SEEN[$key]=1
  local js=$(_fefo_json "$s") jt=$(_fefo_json "$t") jk=$(_fefo_json "$kind")
  _FG_EDGES+=("{\"s\":$js,\"t\":$jt,\"kind\":$jk,\"line\":$line}")
}

_fefo__graph_resolve() {
  emulate -L zsh; setopt local_options extended_glob no_unset pipe_fail typeset_silent
  local fromRel=$1 target=$2
  REPLY=
  target=$(_fefo__trim "$target")
  local t=${target%%\#*}
  t=$(_fefo__trim "$t")
  if [[ -z "$t" ]]; then REPLY=$fromRel; return; fi
  if [[ "$t" != *.md && "$t" != *.MD ]]; then t="$t.md"; fi
  local fromDir=${fromRel:h}
  [[ "$fromDir" == "." ]] && fromDir=""
  local cand
  if [[ -n "$fromDir" ]]; then cand="$fromDir/$t"; else cand="$t"; fi
  local -a parts out
  parts=("${(@s:/:)cand}")
  local part
  for part in "${parts[@]}"; do
    [[ -z "$part" || "$part" == "." ]] && continue
    if [[ "$part" == ".." ]]; then
      (( ${#out} > 0 )) && out=("${out[@]:0:${#out}-1}")
    else
      out+=("$part")
    fi
  done
  cand="${(j:/:)out}"
  if [[ -n ${_FG_RELSET[$cand]+x} ]]; then REPLY=$cand; return; fi
  local base=${cand:t}; base=${base%.*}; base=${base:l}
  if [[ -n ${_FG_BYBASE[$base]+x} ]]; then REPLY=${_FG_BYBASE[$base]}; return; fi
  REPLY=
}

_fefo_graph_build() {
  emulate -L zsh; setopt local_options extended_glob no_unset pipe_fail typeset_silent
  local vault=$1 out=$2
  [[ -d "$vault" ]] || { _fefo_die "vault not found: $vault"; return 1; }
  [[ -n "$out" ]] || { _fefo_die "output path required"; return 1; }
  vault=${vault:A}
  _FG_NODES=(); _FG_NODE_SEEN=(); _FG_EDGES=(); _FG_EDGE_SEEN=(); _FG_RELSET=(); _FG_BYBASE=()
  typeset -gA _FG_NODE_SEEN _FG_EDGE_SEEN _FG_RELSET _FG_BYBASE
  local -a files=() rels=()
  local f rel
  while IFS= read -r f; do
    [[ -n "$f" ]] && files+=("$f")
  done < <(find "$vault" -type d \( -name .codegraph -o -name .obsidian -o -name .git -o -name node_modules \) -prune -o -type f -name '*.md' -print | sort)
  for f in "${files[@]}"; do
    rel=${f#$vault/}
    rels+=("$rel")
  done
  for rel in "${rels[@]}"; do
    _FG_RELSET[$rel]=1
    local base=${rel:t}; base=${base%.*}; base=${base:l}
    [[ -z ${_FG_BYBASE[$base]+x} ]] && _FG_BYBASE[$base]=$rel
  done

  local content line
  local -a lines
  local in_fence=0
  local i
  for rel in "${rels[@]}"; do
    content=$(<"$vault/$rel")
    lines=("${(@f)content}")
    local -a ftags=()
    if [[ ${lines[1]:-} == "---" ]]; then
      local fm="" j=2
      while (( j <= ${#lines} )) && [[ ${lines[j]:-} != "---" ]]; do
        fm+="${lines[j]}"$'\n'
        ((j++))
      done
      if [[ "$fm" == *tags:* ]]; then
        local tline
        tline=$(printf '%s\n' "$fm" | grep -E '^[[:space:]]*tags:' | head -n1)
        if [[ "$tline" == *'['* ]]; then
          local arr=${tline#*:}; arr=${arr#*\[}; arr=${arr%\]*}
          local -a parts; parts=("${(@s:,:)arr}")
          local p
          for p in "${parts[@]}"; do
            p=$(_fefo__trim "$p"); p=${p#\"}; p=${p%\"}; p=${p#\'}; p=${p%\'}
            [[ -n "$p" ]] && ftags+=("$p")
          done
        else
          local in_tags=0
          local ln
          while IFS= read -r ln; do
            if [[ "$ln" =~ '^[[:space:]]*tags:[[:space:]]*$' ]]; then in_tags=1; continue; fi
            if (( in_tags )); then
              if [[ "$ln" =~ '^[[:space:]]*-[[:space:]]+' ]]; then
                local t=${ln#*-}; t=$(_fefo__trim "$t"); t=${t#\"}; t=${t%\"}; t=${t#\'}; t=${t%\'}
                [[ -n "$t" ]] && ftags+=("$t")
              elif [[ "$ln" =~ '^[a-zA-Z]' ]]; then
                in_tags=0
              fi
            fi
          done <<< "$fm"
        fi
      fi
    fi

    _fefo__graph_add_node "file:$rel" "file" "${rel:t}" "$rel" 1
    local t
    for t in "${ftags[@]}"; do
      _fefo__graph_add_node "tag:$t" "tag" "$t" "$rel" 1
      _fefo__graph_add_edge "file:$rel" "tag:$t" "tagged" 1
    done

    in_fence=0
    for (( i=1; i<=${#lines}; i++ )); do
      line=${lines[i]}
      if [[ "$line" =~ '^[ ]{0,3}(```|~~~)' ]]; then
        if (( in_fence )); then in_fence=0; else in_fence=1; fi
        continue
      fi
      (( in_fence )) && continue

      if [[ "$line" =~ '^(#{1,3})[[:space:]]+(.+)$' ]]; then
        local hashes=${match[1]} text=$(_fefo__trim "${match[2]}")
        text=${text%%[[:space:]]\#*}
        local slug=$(_fefo_slug "$text")
        _fefo__graph_add_node "heading:$rel#$slug" "heading" "$text" "$rel" "$i"
        _fefo__graph_add_edge "file:$rel" "heading:$rel#$slug" "contains" "$i"
      fi

      local rest=$line
      while [[ "$rest" == *'#'* ]]; do
        if [[ "$rest" =~ '(^|[[:space:]])#([A-Za-z][A-Za-z0-9_-]*)' ]]; then
          local tag=${MATCH##*\#}
          _fefo__graph_add_node "tag:$tag" "tag" "$tag" "$rel" "$i"
          _fefo__graph_add_edge "file:$rel" "tag:$tag" "tagged" "$i"
          rest=${rest#*${MATCH}}
        else
          break
        fi
      done

      rest=$line
      while [[ "$rest" == *'[['* ]]; do
        local seg=${rest#*\[\[}
        [[ "$seg" == "$rest" ]] && break
        local inner=${seg%%\]\]*}
        [[ "$inner" == "$seg" ]] && { rest=${seg}; break; }
        local raw=$(_fefo__trim "$inner")
        local target=${raw%%|*}
        target=$(_fefo__trim "$target")
        local anchor="" pathPart=$target
        if [[ "$target" == *"#"* ]]; then
          anchor=$(_fefo__trim "${target#*\#}")
          pathPart=$(_fefo__trim "${target%%\#*}")
        fi
        local resolved=""
        if [[ -z "$pathPart" && -n "$anchor" ]]; then
          resolved=$rel
        elif [[ -n "$pathPart" ]]; then
          _fefo__graph_resolve "$rel" "$pathPart"
          resolved=$REPLY
        fi
        local targetId=""
        if [[ -n "$resolved" ]]; then
          if [[ -n "$anchor" ]]; then
            local aslug=$(_fefo_slug "$anchor")
            targetId="heading:$resolved#$aslug"
            _fefo__graph_add_node "$targetId" "heading" "$anchor" "$resolved" "$i"
          else
            targetId="file:$resolved"
          fi
        else
          local cname=${pathPart%.md}
          targetId="concept:$cname"
          _fefo__graph_add_node "$targetId" "concept" "$cname" "$rel" "$i"
        fi
        _fefo__graph_add_edge "file:$rel" "$targetId" "references" "$i"
        rest=${seg#*\]\]}
      done

      rest=$line
      while [[ "$rest" == *']('* ]]; do
        local seg=${rest#*\]\(}
        [[ "$seg" == "$rest" ]] && break
        local linktarget=${seg%%\)*}
        linktarget=$(_fefo__trim "$linktarget")
        local pathPart=$linktarget anchor=""
        if [[ "$pathPart" == *"#"* ]]; then
          anchor=$(_fefo__trim "${pathPart#*\#}")
          pathPart=$(_fefo__trim "${pathPart%%\#*}")
        fi
        if [[ "$pathPart" == http* || "$pathPart" == //* || "$pathPart" == \#* ]]; then
          rest=${seg#*\)}
          continue
        fi
        if [[ "${pathPart:l}" != *.md ]]; then
          rest=${seg#*\)}
          continue
        fi
        local resolved=""
        _fefo__graph_resolve "$rel" "$pathPart"
        resolved=$REPLY
        local targetId=""
        if [[ -n "$resolved" ]]; then
          if [[ -n "$anchor" ]]; then
            local aslug=$(_fefo_slug "$anchor")
            targetId="heading:$resolved#$aslug"
            _fefo__graph_add_node "$targetId" "heading" "$anchor" "$resolved" "$i"
          else
            targetId="file:$resolved"
          fi
        else
          local cname=${pathPart%.md}
          targetId="concept:$cname"
          _fefo__graph_add_node "$targetId" "concept" "$cname" "$rel" "$i"
        fi
        _fefo__graph_add_edge "file:$rel" "$targetId" "references" "$i"
        rest=${seg#*\)}
      done
    done
  done

  if [[ -n ${FEFO_REPOS+x} ]]; then
    local slug rpath rnodepath
    for slug in "${FEFO_REPOS[@]}"; do
      rpath="repos/$slug.md"
      rnodepath=""
      [[ -n ${_FG_RELSET[$rpath]+x} ]] && rnodepath=$rpath
      _fefo__graph_add_node "repo:$slug" "repo" "$slug" "$rnodepath" 1
      if [[ -n ${_FG_RELSET[$rpath]+x} ]]; then
        _fefo__graph_add_edge "repo:$slug" "file:$rpath" "references" 1
      fi
    done
  fi

  local -a sorted_nodes sorted_edges
  sorted_nodes=("${(@o)_FG_NODES}")
  sorted_edges=("${(@o)_FG_EDGES}")
  local nodes_json edges_json
  nodes_json="${(j:,:)sorted_nodes}"
  edges_json="${(j:,:)sorted_edges}"

  mkdir -p "${out:h}"
  printf '{"nodes":[%s],"edges":[%s]}\n' "$nodes_json" "$edges_json" > "$out"
}

_fefo_index_vault() {
  emulate -L zsh; setopt local_options extended_glob no_unset pipe_fail typeset_silent
  local root vault
  root=$(_fefo_root 2>/dev/null) || root=$PWD
  vault="$root/docs/vault"
  [[ -d "$vault" ]] || { _fefo_die "vault not found: $vault"; return 1; }
  if [[ ! -d "$vault/.codegraph" ]]; then
    codegraph init "$vault" || { _fefo_die "codegraph init failed"; return 1; }
  fi
  local json="$vault/.codegraph/vault-graph.json"
  _fefo_graph_build "$vault" "$json" || return 1
  local cg node
  cg=$(whence -p codegraph) || { _fefo_die "codegraph not found"; return 1; }
  node="${cg:A:h:h}/node"
  "$node" "$FEFO_HOME/lib/vault-graph.mjs" "$vault" || { _fefo_die "vault-graph loader failed"; return 1; }
}

_fefo_cmd_graph() {
  emulate -L zsh; setopt local_options extended_glob no_unset pipe_fail typeset_silent
  local port="" open=0 out=""
  while (( $# )); do
    case $1 in
      --port) port=$2; shift 2 ;;
      --open) open=1; shift ;;
      --out) out=$2; shift 2 ;;
      *) _fefo_die "unknown option: $1"; return 2 ;;
    esac
  done
  local root
  root=$(_fefo_root 2>/dev/null) || root=$PWD
  local vault="$root/docs/vault"
  [[ -d "$vault" ]] || { _fefo_die "vault not found: $vault"; return 1; }
  local home=${FEFO_HOME:-}
  if [[ -z "$home" ]]; then
    home=${${(%):-%x}:A:h:h}
  fi
  local slug
  slug=$(_fefo_slug "${root:t}")
  local cachedir="${XDG_CACHE_HOME:-$HOME/.cache}/fefo/$slug"
  mkdir -p "$cachedir"
  local jsonfile="$cachedir/graph.json"
  _fefo_graph_build "$vault" "$jsonfile" || return 1
  local json
  json=$(<"$jsonfile")
  local template="$home/templates/know-graph.html"
  [[ -f "$template" ]] || { _fefo_die "template missing: $template"; return 1; }
  local html
  html=$(<"$template")
  local mark='/*@@GRAPH@@*/'
  html="${html%%"$mark"*}$json${html#*"$mark"}"
  if [[ -n "$out" ]]; then
    mkdir -p "${out:h}"
    printf '%s' "$html" > "$out"
    return 0
  fi
  local outfile="$cachedir/know-graph.html"
  printf '%s' "$html" > "$outfile"

  zmodload zsh/net/tcp
  local lfd user_port=0
  if [[ -n "$port" ]]; then user_port=1; fi
  if (( user_port )); then
    ztcp -l "$port" 2>/dev/null || { _fefo_die "port busy: $port"; return 1; }
    lfd=$REPLY
  else
    port=7737
    while ! ztcp -l "$port" 2>/dev/null; do
      (( port++ ))
      (( port > 7800 )) && { _fefo_die "no free port"; return 1; }
    done
    lfd=$REPLY
  fi

  print "know-graph: http://127.0.0.1:$port/"

  if (( open )); then
    local url="http://127.0.0.1:$port/"
    if command -v open >/dev/null 2>&1; then
      open "$url" >/dev/null 2>&1 &
    elif command -v xdg-open >/dev/null 2>&1; then
      xdg-open "$url" >/dev/null 2>&1 &
    fi
  fi

  trap 'ztcp -c '"$lfd"' 2>/dev/null; exit 0' INT TERM
  while true; do
    ztcp -a "$lfd" 2>/dev/null || break
    local cfd=$REPLY
    local req="" rpath=""
    IFS= read -r -t 2 -u "$cfd" req 2>/dev/null || true
    rpath=${req#GET }
    rpath=${rpath%% *}
    if [[ "$rpath" == "/" || "$rpath" == "/index.html" ]]; then
      print -rnu "$cfd" -- "HTTP/1.1 200 OK"$'\r\n'"Content-Type: text/html; charset=utf-8"$'\r\n'"Connection: close"$'\r\n\r\n'
      cat "$outfile" >&$cfd
    else
      print -rnu "$cfd" -- "HTTP/1.1 404 Not Found"$'\r\n'"Content-Type: text/plain"$'\r\n'"Connection: close"$'\r\n\r\nNot found'
    fi
    ztcp -c "$cfd" 2>/dev/null
  done
  ztcp -c "$lfd" 2>/dev/null
}
