emulate -L zsh
setopt local_options extended_glob no_unset pipe_fail typeset_silent

_fefo_git_root() {
  emulate -L zsh
  setopt local_options extended_glob no_unset pipe_fail typeset_silent
  local out
  out=$(git -C "$1" rev-parse --show-toplevel 2>/dev/null) || return 1
  [[ -n $out ]] || return 1
  print -r -- "${out:A}"
}

_fefo_scan_repos() {
  emulate -L zsh
  setopt local_options extended_glob no_unset pipe_fail typeset_silent
  local dir=${1:-.}
  dir=${dir:A}
  local ws=${FEFO_WS:-}
  local -a candidates
  local d
  for d in "$dir"/*(N/); do
    candidates+=("$d")
  done
  local parent=${dir:h}
  for d in "$parent"/*(N/); do
    [[ "$d" == "$dir" ]] && continue
    candidates+=("$d")
  done
  local -A seen=()
  local -a result=()
  local gr
  for d in "${candidates[@]}"; do
    [[ -d $d ]] || continue
    [[ -n $ws && "$d" == "$ws" ]] && continue
    gr=""
    gr=$(_fefo_git_root "$d") || continue
    [[ -n $ws && "$gr" == "$ws" ]] && continue
    if [[ -z ${seen["$gr"]:-} ]]; then
      seen["$gr"]=1
      result+=("$gr")
    fi
  done
  if (( ${#result} )); then
    print -r -- "${(F)result}" | sort -u
  fi
}

_fefo_detect_stack() {
  emulate -L zsh
  setopt local_options extended_glob no_unset pipe_fail typeset_silent
  local dir=$1
  local pyproject="" requirements="" package=""
  [[ -f $dir/pyproject.toml ]] && pyproject=${$(<$dir/pyproject.toml):l}
  [[ -f $dir/requirements.txt ]] && requirements=${$(<$dir/requirements.txt):l}
  [[ -f $dir/package.json ]] && package=${$(<$dir/package.json):l}
  local py_text="$pyproject"$'\n'"$requirements"
  local has_pubspec=0
  [[ -f $dir/pubspec.yaml ]] && has_pubspec=1
  local has_manage=0
  [[ -f $dir/manage.py ]] && has_manage=1
  if (( has_pubspec )); then print -r -- flutter; return 0; fi
  if (( has_manage )) || [[ $py_text == *django* ]]; then print -r -- django; return 0; fi
  if [[ $py_text == *fastapi* ]]; then print -r -- fastapi; return 0; fi
  if [[ $py_text == *flask* ]]; then print -r -- flask; return 0; fi
  if [[ $package == *'"@nestjs/core"'* ]]; then print -r -- nest; return 0; fi
  if [[ $package == *'"next"'* || $package == *'next@'* ]]; then print -r -- next; return 0; fi
  if [[ $package == *'"react"'* || $package == *'"vite"'* ]]; then print -r -- react; return 0; fi
  local has_compose=0
  local f
  for f in compose.yaml compose.yml docker-compose.yml Dockerfile; do
    [[ -f $dir/$f ]] && { has_compose=1; break; }
  done
  if (( has_compose )); then print -r -- infra; return 0; fi
  # docs
  local has_files=0 all_docs=1 has_dir=0
  for f in "$dir"/*(N); do
    if [[ -d $f ]]; then has_dir=1; fi
    if [[ -f $f ]]; then
      has_files=1
      case ${f:e:l} in
        md|txt|rst) ;;
        *) all_docs=0 ;;
      esac
    fi
  done
  if (( has_files && all_docs && !has_dir )); then
    print -r -- docs
    return 0
  fi
  print -r -- generic
  return 0
}

_fefo_detect_role() {
  emulate -L zsh
  setopt local_options extended_glob no_unset pipe_fail typeset_silent
  local stack=$1
  case $stack in
    django|fastapi|flask|nest) print -r -- api ;;
    next|react) print -r -- web ;;
    flutter) print -r -- mobile ;;
    docs) print -r -- docs ;;
    infra) print -r -- infra ;;
    *) print -r -- service ;;
  esac
}

_fefo_detect_commands() {
  emulate -L zsh
  setopt local_options extended_glob no_unset pipe_fail typeset_silent
  local dir=$1
  local stack=${2:-}
  if [[ -z $stack ]]; then
    stack=$(_fefo_detect_stack "$dir")
  fi
  REPLY_TEST=""
  REPLY_LINT=""
  REPLY_BUILD=""
  REPLY_RUN=""
  case $stack in
    django)
      REPLY_TEST="python manage.py test"
      REPLY_LINT="ruff check ."
      REPLY_BUILD="python manage.py check"
      ;;
    fastapi)
      REPLY_TEST="pytest"
      REPLY_LINT="ruff check ."
      REPLY_RUN="uvicorn main:app --reload"
      ;;
    flask)
      REPLY_TEST="pytest"
      REPLY_LINT="ruff check ."
      REPLY_RUN="flask run"
      ;;
    flutter)
      REPLY_TEST="flutter test"
      REPLY_LINT="flutter analyze"
      REPLY_BUILD="flutter build"
      ;;
    nest|next|react)
      local pm=npm
      [[ -f $dir/bun.lock || -f $dir/bun.lockb ]] && pm=bun
      [[ -f $dir/pnpm-lock.yaml ]] && pm=pnpm
      [[ -f $dir/yarn.lock ]] && pm=yarn
      # package scripts
      local pkg=""
      [[ -f $dir/package.json ]] && pkg=$(<$dir/package.json)
      if [[ $pkg == *'"test"'[[:space:]]*:* ]]; then REPLY_TEST="$pm run test"; fi
      if [[ $pkg == *'"lint"'[[:space:]]*:* ]]; then REPLY_LINT="$pm run lint"; fi
      if [[ $pkg == *'"build"'[[:space:]]*:* ]]; then REPLY_BUILD="$pm run build"; fi
      if [[ $pkg == *'"dev"'[[:space:]]*:* ]]; then REPLY_RUN="$pm run dev"; fi
      ;;
  esac
}