# lib/vault.zsh — generated markdown code vaults (docs/vault/<slug>-vault/)
emulate -L zsh
setopt local_options extended_glob no_unset pipe_fail typeset_silent

zmodload zsh/datetime 2>/dev/null

typeset -ga _FEFO_VAULT_DIRTY=()

# top-level source extensions
_fefo_vault_src_exts=(py ts tsx js jsx dart go rb java kt rs php)
# extensions with Definitions extraction

_fefo_vault_is_src() {  # $1 relpath
  local e=${1:e} x
  for x in "${_fefo_vault_src_exts[@]}"; do
    [[ $e == $x ]] && return 0
  done
  return 1
}

_fefo_vault_skip() {  # $1 relpath → 0 if skipped
  local p=$1 c base
  local -a parts=(${(s:/:)p})
  for c in "${parts[@]}"; do
    case $c in
      tests|test|__tests__|migrations|venv|.venv|node_modules|dist|build|coverage|__pycache__) return 0 ;;
    esac
  done
  base=${p:t}
  case $base in
    test_*.py|*_test.py|tests.py|*.spec.*|*.test.*) return 0 ;;
  esac
  return 1
}

# write target only if content changed; content $2 (newline-terminated)
_fefo_vault_write() {
  emulate -L zsh
  setopt local_options extended_glob no_unset pipe_fail typeset_silent
  local target=$1 content=$2 tmp
  mkdir -p "${target:h}" 2>/dev/null
  tmp=$(mktemp "${target:h}/.vault.XXXXXX") || return 1
  print -rn -- "$content" > "$tmp" || { rm -f "$tmp"; return 1; }
  if [[ -f $target ]] && cmp -s "$target" "$tmp"; then rm -f "$tmp"; return 0; fi
  mv -f "$tmp" "$target" || { rm -f "$tmp"; return 1; }
  return 0
}

_fefo_vault_clean() {  # strip pipes, trim, strip leading '# '
  local s=${1//|/}
  s=${s##[[:space:]]##}; s=${s%%[[:space:]]##}
  s=${s#\# }
  print -r -- "$s"
}

# ---------- per-file scanning ----------

_fefo_vault_defs_file() {  # $1 disk path, $2 ext → prints "name:line"
  local line ln ext=$2
  local -a flines
  flines=("${(@f)$(< $1)}")
  for ((ln=1;ln<=${#flines};ln++)); do
    line=${flines[ln]}
    case $ext in
      py)
        if [[ $line =~ '^class[[:space:]]+([A-Za-z_][A-Za-z0-9_]*)' ]]; then
          print -r -- "${match[1]}:$ln"
        elif [[ $line =~ '^async[[:space:]]+def[[:space:]]+([A-Za-z_][A-Za-z0-9_]*)' ]]; then
          print -r -- "${match[1]}:$ln"
        elif [[ $line =~ '^def[[:space:]]+([A-Za-z_][A-Za-z0-9_]*)' ]]; then
          print -r -- "${match[1]}:$ln"
        fi
        ;;
      ts|tsx|js|jsx)
        if [[ $line =~ '^export[[:space:]]+(default[[:space:]]+)?(function|class|const|interface|type)[[:space:]]+([A-Za-z_$][A-Za-z0-9_$]*)' ]]; then
          print -r -- "${match[3]}:$ln"
        fi
        ;;
      dart)
        if [[ $line =~ '^(class|enum|mixin|extension)[[:space:]]+([A-Za-z_][A-Za-z0-9_]*)' ]]; then
          print -r -- "${match[2]}:$ln"
        fi
        ;;
      go)
        if [[ $line =~ '^func[[:space:]]+([A-Za-z_][A-Za-z0-9_]*)' ]]; then
          print -r -- "${match[1]}:$ln"
        elif [[ $line =~ '^func[[:space:]]+\([^)]*\)[[:space:]]+([A-Za-z_][A-Za-z0-9_]*)' ]]; then
          print -r -- "${match[1]}:$ln"
        elif [[ $line =~ '^type[[:space:]]+([A-Za-z_][A-Za-z0-9_]*)' ]]; then
          print -r -- "${match[1]}:$ln"
        fi
        ;;
    esac
  done
}

_fefo_vault_models_file() {  # $1 disk → prints "name:line"
  local line ln=0
  while IFS= read -r line || [[ -n $line ]]; do
    (( ++ln ))
    if [[ $line =~ '^class[[:space:]]+([A-Za-z_][A-Za-z0-9_]*)[[:space:]]*\(([^)]*)\)' ]]; then
      if [[ ${match[2]} == *Model* ]]; then print -r -- "${match[1]}:$ln"; fi
    fi
  done < "$1"
}

_fefo_vault_is_models_file() {  # $1 relpath
  local base=${1:t} parent=${1:h:t}
  [[ $base == models* ]] && return 0
  [[ $parent == models ]] && return 0
  return 1
}

# routes for one file: prints "- route → view"; $1 disk
_fefo_vault_routes_file() {
  local disk=$1
  local -a lines
  lines=("${(@f)$(< $disk)}")
  local n=${#lines} i j l chunk rest route view q verb
  local verbs='get post put delete patch options head trace'
  local xverbs='get post put delete patch options head all use'
  for ((i=1;i<=n;i++)); do
    l=${lines[i]}
    # django path()/re_path()
    if [[ $l == *path\(* ]]; then
      chunk=$l; j=$i
      while (( j < n && j < i+5 )) && [[ $chunk != *')'* ]]; do
        (( j++ )); chunk+=" ${lines[j]:-}"
      done
      rest=${chunk#*path\(}
      rest=${rest##[[:space:]]##}
      q=${rest[1]:-}
      if [[ $q == \" || $q == \' ]]; then
        rest=${rest[2,-1]}
        if [[ $rest == *$q* ]]; then
          route=${rest%%$q*}
          rest=${rest#*$q}; rest=${rest##[[:space:]]##}
          if [[ $rest == ,* ]]; then
            rest=${rest[2,-1]}; rest=${rest##[[:space:]]##}
            view=${rest%%,*}; view=${view%%)*}; view=${view%%[[:space:]]##}
            print -r -- "- $route → $view"
          fi
        fi
      fi
    fi
    # DRF router.register
    if [[ $l == *router.register\(* ]]; then
      rest=${l#*router.register\(}; rest=${rest##[[:space:]]##}
      rest=${rest#r}
      q=${rest[1]:-}
      if [[ $q == \" || $q == \' ]]; then
        rest=${rest[2,-1]}
        if [[ $rest == *$q* ]]; then
          route=${rest%%$q*}
          rest=${rest#*$q}; rest=${rest##[[:space:]]##}
          if [[ $rest == ,* ]]; then
            rest=${rest[2,-1]}; rest=${rest##[[:space:]]##}
            view=${rest%%,*}; view=${view%%)*}; view=${view%%[[:space:]]##}
            print -r -- "- $route → $view"
          fi
        fi
      fi
    fi
    # FastAPI @app/@router.<verb>("path")
    for verb in $verbs; do
      if [[ $l == *@app.$verb\(* || $l == *@router.$verb\(* ]]; then
        rest=${l#*$verb\(}; rest=${rest##[[:space:]]##}
        q=${rest[1]:-}; route=""
        if [[ $q == \" || $q == \' ]]; then
          rest=${rest[2,-1]}
          [[ $rest == *$q* ]] && route=${rest%%$q*}
        fi
        view=""; j=$i+1
        while (( j <= n && j < i+6 )); do
          if [[ ${lines[j]} =~ '^[[:space:]]*(async[[:space:]]+)?def[[:space:]]+([A-Za-z_][A-Za-z0-9_]*)' ]]; then
            view=${match[2]}; break
          fi
          (( j++ ))
        done
        print -r -- "- $route → $view"
        break
      fi
    done
    # express router.<verb>(...)
    for verb in $xverbs; do
      if [[ $l == *router.$verb\(* ]]; then
        rest=${l#*router.$verb\(}; rest=${rest##[[:space:]]##}
        q=${rest[1]:-}; route=""
        if [[ $q == \" || $q == \' ]]; then
          rest=${rest[2,-1]}
          [[ $rest == *$q* ]] && route=${rest%%$q*}
        fi
        view=""
        rest=${rest#*,}; rest=${rest##[[:space:]]##}
        view=${rest%%,*}; view=${view%%)*}; view=${view%%[[:space:]]##}
        print -r -- "- $route → $view"
        break
      fi
    done
  done
}

# ---------- module edges ----------

_fefo_vault_file_module() {  # $1 relpath → prints module + REPLY; modlist global
  local f=$1 m best=""
  local -a mods=(${(f)_fefo_vault_modlist})
  for m in "${mods[@]}"; do
    [[ -n $m ]] || continue
    if [[ $f == $m/* ]]; then
      (( ${#m} > ${#best} )) && best=$m
    fi
  done
  REPLY=$best
}

_fefo_vault_match_module() {  # $1 slash path → longest-prefix module + REPLY
  local p=$1 m best=""
  while [[ $p == ./* ]]; do p=${p#./}; done
  p=${p%/}; [[ $p == . || -z $p ]] && p=""
  local -a mods=(${(f)_fefo_vault_modlist})
  for m in "${mods[@]}"; do
    [[ -n $m ]] || continue
    if [[ $p == $m || $p == $m/* ]]; then
      (( ${#m} > ${#best} )) && best=$m
    fi
  done
  REPLY=$best
}

_fefo_vault_resolve_py() {  # $1 base $2 cur module → prints slash path
  local base=$1 cur=$2 S=/
  if [[ $base == .* ]]; then
    local dots=${base%%[^.]*}
    local rest=${base#$dots}
    local nd=${#dots}
    local dir=$cur
    rest=${rest##[[:space:]]##}
    while (( nd > 1 )); do dir=${dir:h}; (( nd-- )); done
    if [[ $dir == . ]]; then dir=""; fi
    if [[ -n $rest ]]; then
      local conv=${rest//./$S}
      if [[ -n $dir ]]; then REPLY=$dir/$conv; else REPLY=$conv; fi
      print -r -- "$REPLY"
    else
      REPLY=${dir:-.}
      print -r -- "$REPLY"
    fi
    return 0
  fi
  REPLY=${base//./$S}
}

_fefo_vault_resolve_js() {  # $1 target $2 cur module → prints slash path
  local t=$1 cur=$2 p=$1 dir=$cur
  if [[ $t == ./* || $t == ../* || $t == . || $t == .. ]]; then
    while [[ $p == ../* || $p == .. ]]; do
      dir=${dir:h}
      if [[ $p == .. ]]; then p=""; break; fi
      p=${p#../}
    done
    [[ $p == ./* ]] && p=${p#./}
    [[ $p == . ]] && p=""
    REPLY=${dir%/}/$p
  else
    REPLY=$t
  fi
}

# ---------- role ----------

_fefo_vault_role() {  # $1 repo $2 module → prints role
  local repo=$1 m=$2 line
  local readme=$repo/$m/README.md
  if [[ -f $readme ]]; then
    while IFS= read -r line || [[ -n $line ]]; do
      [[ ${line##[[:space:]]##} == *[^[:space:]]* ]] || continue
      print -r -- "$(_fefo_vault_clean "$line")"; return 0
    done < "$readme"
  fi
  local apps=$repo/$m/apps.py
  if [[ -f $apps ]]; then
    local re="verbose_name[[:space:]]*=[[:space:]]*[\"']([^\"']+)[\"']"
    while IFS= read -r line || [[ -n $line ]]; do
      if [[ $line =~ $re ]]; then print -r -- "${match[1]}"; return 0; fi
    done < "$apps"
  fi
  local init=$repo/$m/__init__.py
  if [[ -f $init ]]; then
    local started=0 after before dq='"""' sq="'''"
    while IFS= read -r line || [[ -n $line ]]; do
      if (( ! started )); then
        if [[ $line == *$dq* || $line == *$sq* ]]; then
          started=1
          after=${line#*$dq}; after=${after#*$sq}
          if [[ $after == *$dq* || $after == *$sq* ]]; then
            before=${after%%$dq*}; before=${before%%$sq*}
            [[ -n ${before##[[:space:]]##} ]] && { print -r -- "$(_fefo_vault_clean "$before")"; return 0; }
            break
          fi
          if [[ -n ${after##[[:space:]]##} ]]; then
            print -r -- "$(_fefo_vault_clean "$after")"; return 0
          fi
        else
          [[ ${line##[[:space:]]##} == *[^[:space:]]* ]] || continue
          break
        fi
      else
        if [[ $line == *$dq* || $line == *$sq* ]]; then
          before=${line%%$dq*}; before=${before%%$sq*}
          [[ -n ${before##[[:space:]]##} ]] && { print -r -- "$(_fefo_vault_clean "$before")"; return 0; }
          break
        fi
        if [[ -n ${line##[[:space:]]##} ]]; then
          print -r -- "$(_fefo_vault_clean "$line")"; return 0
        fi
      fi
    done < "$init"
  fi
  print -r -- "—"
}

# ---------- recent ----------

_fefo_vault_recent() {  # $1 repo; modlist global
  local repo=$1 h shorthash date subj files f m k key
  local -a commits lines parts
  commits=("${(@f)$(git -C "$repo" log -n20 --format=%H 2>/dev/null)}")
  lines=("# Recent commits (last 20)" "")
  local -A touched
  for h in "${commits[@]}"; do
    [[ -n $h ]] || continue
    shorthash=$(git -C "$repo" log -1 --format=%h "$h" 2>/dev/null)
    date=$(git -C "$repo" log -1 --date=short --format=%ad "$h" 2>/dev/null)
    subj=$(git -C "$repo" log -1 --format=%s "$h" 2>/dev/null)
    files=$(git -C "$repo" show --name-only --format= "$h" 2>/dev/null)
    touched=()
    for f in ${(f)files}; do
      [[ -n $f && $f != */ ]] || continue
      _fefo_vault_file_module "$f"; m=$REPLY
      [[ -n $m ]] || continue
      touched[$m]=$(( ${touched[$m]:-0} + 1 ))
    done
    parts=()
    for k in "${(@ko)touched}"; do
      parts+=("$k(${touched[$k]})")
    done
    if (( ${#parts} )); then
      lines+=("- $shorthash $date $subj — ${(j:, :)parts}")
    else
      lines+=("- $shorthash $date $subj — no module files")
    fi
  done
  print -r -- "${(F)lines}"$'\n'
}

# ---------- per-repo generation ----------

_fefo_vault_repo() {  # $1 ws $2 name $3 changed $4 force
  local ws=$1 name=$2 changed=$3 force=$4
  local rpath=${FEFO_R_PATH[$name]:-.}
  local repo
  if [[ $rpath == /* ]]; then repo=$rpath; else repo=$ws/$rpath; fi
  repo=${repo:A}
  local slug=$(_fefo_slug "$name")
  local out=$ws/docs/vault/$slug-vault

  local head
  head=$(git -C "$repo" rev-parse HEAD 2>/dev/null) || { _fefo_warn "vault $name: not a git repo, skipped"; return 0; }

  if (( changed && ! force )) && [[ -f $out/.stamp ]]; then
    local stamp
    stamp=$(<$out/.stamp)
    if [[ $stamp == $head ]]; then
      print -r -- "fefo: vault $name unchanged"
      return 0
    fi
  fi

  _FEFO_VAULT_DIRTY+=("$slug")
  local start=$EPOCHSECONDS

  # tracked, non-skipped files
  local -a tracked=() kept=() src=()
  local f
  tracked=("${(@f)$(git -C "$repo" ls-files 2>/dev/null)}")
  for f in "${tracked[@]}"; do
    [[ -n $f ]] || continue
    _fefo_vault_skip "$f" && continue
    kept+=("$f")
    _fefo_vault_is_src "$f" && src+=("$f")
  done

  # ---- module detection ----
  local -a appsdirs=() tops=() modules=()
  local d
  for f in "${kept[@]}"; do
    if [[ ${f:t} == apps.py ]]; then
      d=${f:h}; [[ $d == . ]] && continue
      local -a comps=(${(s:/:)d})
      if (( ${#comps} <= 2 )); then appsdirs+=("$d"); fi
    fi
  done
  for f in "${src[@]}"; do
    [[ $f == */* ]] || continue
    tops+=("${f%%/*}")
  done
  if (( ${#appsdirs} )); then
    modules=("${(@ou)appsdirs}")
  else
    modules=("${(@ou)tops}")
  fi
  typeset -g _fefo_vault_modlist="${(F)modules}"

  mkdir -p "$out/modules"

  # ---- per-module scan ----
  local -A modfiles moddefs modroles modmodels modroutes
  local -A impfrom impby usedbyname
  local m sf ext disk
  for m in "${modules[@]}"; do
    local -a files=() deflines=() routes=() models=()
    for f in "${kept[@]}"; do
      [[ $f == $m/* ]] && files+=("$f")
    done
    files=("${(@o)files}")
    modfiles[$m]="${(F)files}"
    for sf in "${src[@]}"; do
      [[ $sf == $m/* ]] || continue
      ext=${sf:e}; disk=$repo/$sf
      [[ -f $disk ]] || continue
      # definitions
      local -a dl=()
      dl=("${(@f)$(_fefo_vault_defs_file "$disk" "$ext")}")
      local -a dln=()
      local dn
      for dn in "${dl[@]}"; do [[ -n $dn ]] && dln+=("$dn"); done
      if (( ${#dln} )); then deflines+=("$sf — ${(j:, :)dln}"); fi
      # routes
      local -a rl=()
      rl=("${(@f)$(_fefo_vault_routes_file "$disk")}")
      local r
      for r in "${rl[@]}"; do [[ -n $r ]] && routes+=("$r"); done
      # models
      if _fefo_vault_is_models_file "$sf"; then
        local -a ml=()
        ml=("${(@f)$(_fefo_vault_models_file "$disk")}")
        local mn
        for mn in "${ml[@]}"; do
          [[ -n $mn ]] || continue
          models+=("${mn%%:*} ($sf:${mn##*:})")
        done
      fi
    done
    deflines=("${(@o)deflines}")
    routes=("${(@o)routes}")
    models=("${(@o)models}")
    moddefs[$m]="${(F)deflines}"
    modroutes[$m]="${(F)routes}"
    modmodels[$m]="${(F)models}"
    modroles[$m]="$(_fefo_vault_role "$repo" "$m")"
  done

  # ---- edges: ONE git grep per repo ----
  local gout line rest ln content base names ext cur other target S=/
  local nm nmclean resolved resclean q curfile=""
  gout=$(git -C "$repo" grep -n -E '^(from|import) |from .' 2>/dev/null || true)
  for line in ${(f)gout}; do
    [[ -n $line ]] || continue
    f=${line%%:*}
    rest=${line#*:}; ln=${rest%%:*}; content=${rest#*:}
    _fefo_vault_skip "$f" && continue
    _fefo_vault_is_src "$f" || continue
    if [[ $f != $curfile ]]; then
      curfile=$f
      _fefo_vault_file_module "$f"; cur=$REPLY
    fi
    [[ -n $cur ]] || continue
    ext=${f:e}
    case $ext in
      py)
        if [[ $content =~ '^from[[:space:]]+([.][.]*[A-Za-z_][A-Za-z0-9_.]*|[.]+|[A-Za-z_][A-Za-z0-9_.]*)' ]]; then
          base=${match[1]}; names=""
          if [[ $content == *' import '* ]]; then
            names=${content#* import }
            names=${names%%)*}; names=${names#\(}
            names=${names##[[:space:]]##}; names=${names%%[[:space:]]##}
          fi
          _fefo_vault_resolve_py "$base" "$cur"; resolved=$REPLY
          _fefo_vault_match_module "$resolved"; other=$REPLY
          if [[ -n $other ]]; then
            for nm in ${(s:,:)names}; do
              nmclean=${nm##[[:space:]]##}; nmclean=${nmclean%%[[:space:]]##}
              nmclean=${nmclean%% as *}
              [[ -n $nmclean && $nmclean != '*' ]] || continue
              local ukey=$other$'\t'$nmclean
              usedbyname[$ukey]+="$f"$'\n'
            done
          fi
          if [[ -n $other && $other != $cur ]]; then
            impfrom[$cur]+="$other"$'\n'
            impby[$other]+="$cur"$'\n'
          fi
        elif [[ $content =~ '^import[[:space:]]+([A-Za-z_][A-Za-z0-9_.]*)' ]]; then
          base=${match[1]}
          resolved=${base//./$S}
          _fefo_vault_match_module "$resolved"; other=$REPLY
          if [[ -n $other ]]; then
            local ukey=$other$'\t'${base##*.}
            usedbyname[$ukey]+="$f"$'\n'
          fi
          if [[ -n $other && $other != $cur ]]; then
            impfrom[$cur]+="$other"$'\n'
            impby[$other]+="$cur"$'\n'
          fi
        fi
        ;;
      ts|tsx|js|jsx)
        if [[ $content == *from\ * ]]; then
          rest=${content#*from }; rest=${rest##[[:space:]]##}
          q=${rest[1]:-}
          if [[ $q == \" || $q == \' ]]; then
            rest=${rest[2,-1]}
            if [[ $rest == *$q* ]]; then
              target=${rest%%$q*}
              _fefo_vault_resolve_js "$target" "$cur"; resolved=$REPLY
              resclean=${resolved%.*}
              _fefo_vault_match_module "$resolved"; other=$REPLY
              if [[ -z $other ]]; then _fefo_vault_match_module "$resclean"; other=$REPLY; fi
              if [[ -n $other && $other != $cur ]]; then
                impfrom[$cur]+="$other"$'\n'
                impby[$other]+="$cur"$'\n'
              fi
            fi
          fi
        fi
        ;;
    esac
  done

  # ---- write outputs ----
  local stack=${FEFO_R_STACK[$name]:-generic}
  local short=${head[1,7]}
  local -a idx=()
  idx+=("# $name — code vault")
  idx+=("")
  idx+=("repo $repo · stack $stack · HEAD $short · generated by fefo vault")
  idx+=("")
  idx+=("| module | role | files | note |")
  idx+=("|---|---|---|---|")
  local nfiles
  for m in "${modules[@]}"; do
    nfiles=0
    [[ -n ${modfiles[$m]:-} ]] && nfiles=$(print -r -- "${modfiles[$m]}" | grep -c . || true)
    idx+=("| $m | $(_fefo_vault_clean "${modroles[$m]:-—}") | $nfiles | [[modules/$m]] |")
  done
  idx+=("")
  idx+=("## Entry points")
  local -a eps=()
  local base e
  for f in "${kept[@]}"; do
    base=${f:t}
    case $f in
      manage.py|package.json|pubspec.yaml|go.mod) eps+=("$f"); continue ;;
    esac
    if [[ $base == main.* ]]; then eps+=("$f"); continue; fi
    if [[ $f == */* && ( $base == settings.py || $base == urls.py ) ]]; then eps+=("$f"); continue; fi
    if [[ $f == cmd/*/main.go ]]; then eps+=("$f"); continue; fi
  done
  eps=("${(@ou)eps}")
  for e in "${eps[@]}"; do idx+=("- $e"); done
  idx+=("")
  idx+=("## Commands")
  [[ -n ${FEFO_R_TEST[$name]:-} ]] && idx+=("- test: ${FEFO_R_TEST[$name]}")
  [[ -n ${FEFO_R_LINT[$name]:-} ]] && idx+=("- lint: ${FEFO_R_LINT[$name]}")
  [[ -n ${FEFO_R_BUILD[$name]:-} ]] && idx+=("- build: ${FEFO_R_BUILD[$name]}")
  [[ -n ${FEFO_R_RUN[$name]:-} ]] && idx+=("- run: ${FEFO_R_RUN[$name]}")
  idx+=("")
  idx+=("## How to use")
  idx+=("1. index → module note: read 00-INDEX.md, then modules/<m>.md for files, definitions, routes, models and edges.")
  idx+=("2. path:line: definitions and routes give repo-root-relative path and line; open <path> at that line.")
  idx+=("3. usages: git -C $repo grep -n inside the files listed")
  _fefo_vault_write "$out/00-INDEX.md" "${(F)idx}"$'\n'

  # ---- module notes ----
  for m in "${modules[@]}"; do
    local -a note=() fromlist=() bylist=() usedlines=()
    note+=("# $m")
    note+=("")
    note+=("Role: ${modroles[$m]:-—}")
    note+=("")
    nfiles=0
    [[ -n ${modfiles[$m]:-} ]] && nfiles=$(print -r -- "${modfiles[$m]}" | grep -c . || true)
    note+=("## Files ($nfiles)")
    local lf
    for lf in ${(f)modfiles[$m]}; do [[ -n $lf ]] && note+=("$lf"); done
    note+=("")
    note+=("## Definitions")
    local dl2
    for dl2 in ${(f)moddefs[$m]}; do [[ -n $dl2 ]] && note+=("$dl2"); done
    note+=("")
    note+=("## Routes")
    local rt
    for rt in ${(f)modroutes[$m]}; do [[ -n $rt ]] && note+=("$rt"); done
    note+=("")
    note+=("## Models")
    local ml2
    for ml2 in ${(f)modmodels[$m]}; do [[ -n $ml2 ]] && note+=("- $ml2"); done
    note+=("")
    note+=("## Imports from")
    local other2 cnt
    if [[ -n ${impfrom[$m]:-} ]]; then
      for other2 in ${(f)impfrom[$m]}; do
        [[ -n $other2 ]] || continue
        cnt=$(print -r -- "${impfrom[$m]}" | grep -xF -- "$other2" | wc -l | tr -d ' ')
        fromlist+=("- [[modules/$other2]] ($cnt)")
      done
      fromlist=("${(@u)fromlist}")
    fi
    if (( ${#fromlist} == 0 )); then note+=("- none"); else note+=("${fromlist[@]}"); fi
    note+=("")
    note+=("## Imported by")
    if [[ -n ${impby[$m]:-} ]]; then
      for other2 in ${(f)impby[$m]}; do
        [[ -n $other2 ]] || continue
        cnt=$(print -r -- "${impby[$m]}" | grep -xF -- "$other2" | wc -l | tr -d ' ')
        bylist+=("- [[modules/$other2]] ($cnt)")
      done
      bylist=("${(@u)bylist}")
    fi
    if (( ${#bylist} == 0 )); then note+=("- none"); else note+=("${bylist[@]}"); fi
    note+=("")
    note+=("## Used by")
    local uk uname
    local -a ufiles=() shown=()
    for uk in "${(@k)usedbyname}"; do
      [[ ${uk%%$'\t'*} == $m ]] || continue
      uname=${uk#*$'\t'}
      ufiles=("${(@f)usedbyname[$uk]}")
      ufiles=("${(@uo)ufiles[@]:#}")
      shown=("${ufiles[@]:0:10}")
      local extra=""
      (( ${#ufiles} > 10 )) && extra=", …"
      usedlines+=("- $uname → ${(j:, :)shown}$extra")
    done
    usedlines=("${(@o)usedlines}")
    if (( ${#usedlines} )); then note+=("${usedlines[@]}"); else note+=("- none"); fi

    # ---- split guard: >1500 lines → split Definitions per 2nd-level dir ----
    if (( ${#note} > 1500 )); then
      local indefs=0 in2=0 ln2 sub key2
      local -a restdefs=() links=() newnote=()
      local -A subgroups
      subgroups=()
      for ln2 in "${note[@]}"; do
        if [[ $ln2 == '## Definitions' ]]; then indefs=1; continue; fi
        if (( indefs )) && [[ $ln2 == '## '* ]]; then indefs=0; fi
        (( indefs )) && restdefs+=("$ln2")
      done
      local p rel
      for ln2 in "${restdefs[@]}"; do
        [[ -n $ln2 ]] || continue
        p=${ln2%% — *}
        rel=${p#$m/}
        if [[ $rel == */* ]]; then sub=${rel%%/*}; else sub="_root"; fi
        subgroups[$sub]+="$ln2"$'\n'
      done
      for sub in "${(@ko)subgroups}"; do
        _fefo_vault_write "$out/modules/$m/$sub.md" "# $m/$sub"$'\n\n'"${subgroups[$sub]}"
        links+=("- [[modules/$m/$sub]]")
      done
      for ln2 in "${note[@]}"; do
        if [[ $ln2 == '## Definitions' ]]; then
          in2=1; newnote+=("$ln2"); newnote+=("${links[@]}"); continue
        fi
        if (( in2 )) && [[ $ln2 == '## '* ]]; then in2=0; fi
        (( in2 )) && continue
        newnote+=("$ln2")
      done
      note=("${newnote[@]}")
    fi

    _fefo_vault_write "$out/modules/$m.md" "${(F)note}"$'\n'
  done

  # recent.md
  local recent
  recent=$(_fefo_vault_recent "$repo")
  _fefo_vault_write "$out/recent.md" "$recent"$'\n'


  # stamp
  _fefo_vault_write "$out/.stamp" "$head"$'\n'

  print -r -- "fefo: vault $name (${#modules} modules, $(( EPOCHSECONDS - start ))s)"
}

# ---------- command ----------

_fefo_cmd_vault() {
  emulate -L zsh
  setopt local_options extended_glob no_unset pipe_fail typeset_silent
  zmodload zsh/datetime 2>/dev/null
  _FEFO_VAULT_DIRTY=()

  local changed=0 force=0
  local -a names=()
  while (( $# )); do
    case $1 in
      --changed) changed=1; shift ;;
      --force) force=1; shift ;;
      --) shift; names+=("$@"); break ;;
      -*) _fefo_die "unknown flag: $1"; return 2 ;;
      *) names+=("$1"); shift ;;
    esac
  done

  local ws=${FEFO_WS:-}
  if [[ -z $ws ]]; then ws=$(_fefo_root) || return 1; fi
  ws=${ws:A}
  FEFO_WS=$ws; export FEFO_WS

  _fefo_manifest_load "$ws/.fefo/workspace.zsh" || return 1

  # global vault on/off (default on)
  if (( ! ${FEFO_VAULT:-1} )); then return 0; fi

  local -a repos=()
  local r n found
  if (( ${#names} )); then
    for n in "${names[@]}"; do
      found=0
      for r in "${FEFO_REPOS[@]}"; do
        if [[ $r == $n ]]; then repos+=("$r"); found=1; break; fi
      done
      if (( ! found )); then _fefo_die "unknown repo: $n"; return 1; fi
    done
  else
    repos=("${FEFO_REPOS[@]}")
  fi

  for r in "${repos[@]}"; do
    # per-repo vault=off
    if (( ${+FEFO_R_VAULT} )) && [[ -n ${FEFO_R_VAULT[$r]:-} ]]; then
      case ${FEFO_R_VAULT[$r]} in
        0|off|no|false) continue ;;
      esac
    fi
    _fefo_vault_repo "$ws" "$r" "$changed" "$force"
  done

  # gitignore (idempotent; lane wire also ensures this in _fefo_ensure_gitignore)
  local gi=$ws/.gitignore
  local -a ign=('/docs/vault/*-vault/' '/docs/vault/graph.json')
  local il
  if [[ -f $gi ]]; then
    [[ -s $gi && -n $(tail -c1 "$gi" 2>/dev/null) ]] && print >> "$gi"
    for il in "${ign[@]}"; do
      grep -Fxq -- "$il" "$gi" 2>/dev/null || printf '%s\n' "$il" >> "$gi"
    done
  else
    printf '%s\n' "${ign[@]}" > "$gi"
  fi

  # FEFO graph: rebuild once per run when vaults changed or graph is missing/stale.
  local g="$ws/docs/vault/graph.json"
  local need=0
  (( force )) && need=1
  (( ${#_FEFO_VAULT_DIRTY} )) && need=1
  if [[ ! -f $g ]]; then
    need=1
  else
    local vf
    for vf in "$ws"/docs/vault/*-vault/**/*.md(N); do
      [[ -f $vf ]] || continue
      if [[ $vf -nt $g ]]; then need=1; break; fi
    done
  fi
  if (( need )); then
    _fefo_graph_build "$ws/docs/vault" "$g"
  fi
  return 0
}
