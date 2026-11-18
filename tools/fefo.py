#!/usr/bin/env python3
"""FEFO — Flow Execution via Federated Ontology.

A small, dependency-free workspace generator. It federates existing Git
repositories into one OpenCode-first workspace and derives adapters for Claude
Code, Cursor, and GitHub Copilot from the same manifest.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import textwrap
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(os.environ.get("FEFO_ROOT", Path(__file__).resolve().parents[1])).resolve()
MANIFEST_PATH = ROOT / ".fefo" / "workspace.json"
# Suggested, never forced: a workspace pins a model only when the manifest says so.
RECOMMENDED_MODEL = "opencode-go/deepseek-v4.1-flash"
MIN_OPENCODE = (2, 3, 0)
HARNESSES = ("opencode", "claude", "cursor", "copilot")
ROLES = (
    "orchestrator", "api", "web", "mobile", "data", "infra", "legacy",
    "integration", "docs", "service", "library",
)
STACKS = (
    "django", "fastapi", "flask", "nest", "next", "react", "flutter",
    "docs", "infra", "generic",
)
GIT_ASKS = [
    "git commit *", "git -C * commit *",
    "git push *", "git -C * push *",
    "git merge *", "git -C * merge *",
    "git rebase *", "git -C * rebase *",
    "git reset --hard*", "git -C * reset --hard*",
]
# Force-push is denied outright: `opencode run --auto` (used by scripted helpers)
# approves everything that is only `ask`, so ask alone is not a guardrail.
GIT_DENIES = [
    "git push --force*", "git push -f *", "git push * --force*", "git push * -f *",
    "git -C * push --force*", "git -C * push -f *", "git -C * push * --force*", "git -C * push * -f *",
]


# ---------------------------------------------------------------------------
# Files and manifest
# ---------------------------------------------------------------------------

def slugify(value: str) -> str:
    value = re.sub(r"[^a-zA-Z0-9]+", "-", value.strip().lower())
    return value.strip("-") or "repo"


def read_json(path: Path) -> dict:
    return json.loads(path.read_text())


# Every generated write goes through these helpers. In check mode nothing is
# written; the paths that would change are collected in DRIFT instead.
CHECK = False
DRIFT: list[str] = []
CONFLICTS: list[str] = []


def rel(path: Path) -> str:
    try:
        return str(Path(path).relative_to(ROOT))
    except ValueError:
        return str(path)


def ensure_dir(path: Path) -> None:
    if not CHECK:
        path.mkdir(parents=True, exist_ok=True)


def write_text(path: Path, content: str) -> None:
    if path.is_file() and not path.is_symlink() and path.read_text() == content:
        return
    DRIFT.append(rel(path))
    if CHECK:
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content)


def write_json(path: Path, data) -> None:
    write_text(path, json.dumps(data, indent=2, ensure_ascii=False) + "\n")


def link(path: Path, target: str) -> None:
    if path.is_symlink() and os.readlink(path) == target:
        return
    if path.exists() and not path.is_symlink():
        CONFLICTS.append(rel(path))
        print(f"CONFLICT {rel(path)} is a real file or directory; replace it with a symlink to {target}")
        return
    DRIFT.append(rel(path))
    if CHECK:
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.is_symlink():
        path.unlink()
    path.symlink_to(target)


def remove(path: Path) -> None:
    DRIFT.append(rel(path))
    if not CHECK:
        path.unlink()


APPEND_REPLACE_KEYS = {"command", "args"}


def deep_merge(base, override, key: str = ""):
    """Merge user overrides into generated config.

    Objects merge key by key, lists append without duplicates (except process
    `command`/`args` lists, which replace), and scalars replace.
    """
    if isinstance(base, dict) and isinstance(override, dict):
        merged = dict(base)
        for k, v in override.items():
            merged[k] = deep_merge(base[k], v, k) if k in base else v
        return merged
    if isinstance(base, list) and isinstance(override, list) and key not in APPEND_REPLACE_KEYS:
        return base + [item for item in override if item not in base]
    return override


def default_manifest(name: str) -> dict:
    return {
        "fefo": 1,
        "name": name,
        "generated_at": None,
        "provider": {"model": None},
        "harnesses": list(HARNESSES),
        "repos": [],
        "plugins": [],
        "mcp_servers": {},
        "opencode": {},
        "claude_settings": {},
    }


def load_manifest(required: bool = True) -> dict:
    if not MANIFEST_PATH.is_file():
        if required:
            raise SystemExit("FEFO: no manifest found. Run `./bin/fefo init` first.")
        return default_manifest(ROOT.name)
    data = read_json(MANIFEST_PATH)
    validate_manifest(data)
    return data


def save_manifest(data: dict) -> None:
    # generated_at records creation only; rewriting it on every sync would make
    # a no-op sync change the manifest.
    if not data.get("generated_at"):
        data["generated_at"] = datetime.now(timezone.utc).isoformat()
    write_json(MANIFEST_PATH, data)


def manifest_model(manifest: dict) -> str | None:
    return (manifest.get("provider") or {}).get("model") or None


def validate_manifest(data: dict) -> None:
    if data.get("fefo") != 1:
        raise SystemExit("FEFO: unsupported manifest version; expected fefo: 1.")
    if not data.get("name"):
        raise SystemExit("FEFO: manifest is missing a workspace name.")
    for field, kind in (("opencode", dict), ("claude_settings", dict), ("plugins", list), ("mcp_servers", dict)):
        if field in data and not isinstance(data[field], kind):
            raise SystemExit(f"FEFO: manifest field '{field}' must be a {kind.__name__}.")
    names = set()
    for repo in data.get("repos", []):
        for field in ("name", "path", "role", "stack"):
            if not repo.get(field):
                raise SystemExit(f"FEFO: repo entry is missing {field}: {repo}")
        if repo["name"] in names:
            raise SystemExit(f"FEFO: duplicate repo name: {repo['name']}")
        names.add(repo["name"])


# ---------------------------------------------------------------------------
# Repository detection
# ---------------------------------------------------------------------------

def command_exists(name: str) -> bool:
    return shutil.which(name) is not None


def git_root(path: Path) -> Path | None:
    try:
        out = subprocess.run(
            ["git", "-C", str(path), "rev-parse", "--show-toplevel"],
            capture_output=True, text=True, check=True,
        ).stdout.strip()
        return Path(out).resolve()
    except Exception:
        return None


def relative_path(path: Path) -> str:
    try:
        return os.path.relpath(path, ROOT)
    except ValueError:
        return str(path)


def repo_path(repo: dict) -> Path:
    p = Path(repo["path"])
    return (ROOT / p).resolve() if not p.is_absolute() else p


def read_text(path: Path) -> str:
    try:
        return path.read_text(errors="ignore")
    except Exception:
        return ""


def detect_stack(path: Path) -> str:
    files = {p.name for p in path.iterdir()} if path.is_dir() else set()
    pyproject = read_text(path / "pyproject.toml").lower()
    requirements = read_text(path / "requirements.txt").lower()
    package = read_text(path / "package.json").lower()
    py_text = pyproject + "\n" + requirements
    if "pubspec.yaml" in files:
        return "flutter"
    if "manage.py" in files or "django" in py_text:
        return "django"
    if "fastapi" in py_text:
        return "fastapi"
    if "flask" in py_text:
        return "flask"
    if '"@nestjs/core"' in package:
        return "nest"
    if '"next"' in package or "next@" in package:
        return "next"
    if '"react"' in package or '"vite"' in package:
        return "react"
    if any(files & {"compose.yaml", "compose.yml", "docker-compose.yml", "Dockerfile"}):
        return "infra"
    if files and all(p.suffix.lower() in {".md", ".txt", ".rst"} for p in path.iterdir() if p.is_file()):
        return "docs"
    return "generic"


def package_manager(path: Path) -> str:
    if (path / "bun.lock").exists() or (path / "bun.lockb").exists():
        return "bun"
    if (path / "pnpm-lock.yaml").exists():
        return "pnpm"
    if (path / "yarn.lock").exists():
        return "yarn"
    return "npm"


def package_scripts(path: Path) -> list[str]:
    try:
        data = read_json(path / "package.json")
        return list((data.get("scripts") or {}).keys())
    except Exception:
        return []


def detect_commands(path: Path, stack: str) -> dict:
    commands = {"test": "", "lint": "", "build": "", "run": ""}
    if stack == "django":
        commands.update(test="python manage.py test", lint="ruff check .", build="python manage.py check")
    elif stack == "fastapi":
        commands.update(test="pytest", lint="ruff check .", run="uvicorn main:app --reload")
    elif stack == "flask":
        commands.update(test="pytest", lint="ruff check .", run="flask run")
    elif stack == "flutter":
        commands.update(test="flutter test", lint="flutter analyze", build="flutter build")
    elif stack in ("nest", "next", "react"):
        pm = package_manager(path)
        scripts = package_scripts(path)
        if "test" in scripts:
            commands["test"] = f"{pm} run test"
        if "lint" in scripts:
            commands["lint"] = f"{pm} run lint"
        if "build" in scripts:
            commands["build"] = f"{pm} run build"
        if "dev" in scripts:
            commands["run"] = f"{pm} run dev"
    return commands


def default_role(stack: str) -> str:
    return {
        "django": "api", "fastapi": "api", "flask": "api", "nest": "api",
        "next": "web", "react": "web", "flutter": "mobile",
        "docs": "docs", "infra": "infra",
    }.get(stack, "service")


def detect_repo(path: Path) -> tuple[str, dict, str]:
    stack = detect_stack(path)
    return stack, detect_commands(path, stack), default_role(stack)


def ensure_unique_name(manifest: dict, name: str, path: str, force: bool = False) -> str:
    for repo in manifest["repos"]:
        if repo["name"] == name and repo["path"] != path:
            if not force:
                raise SystemExit(f"FEFO: repo name '{name}' already points to {repo['path']}. Use --force or --name.")
    return name


def add_repo(manifest: dict, path_arg: str, *, name=None, role=None, stack=None,
             test=None, lint=None, build=None, index=True, force=False) -> dict:
    path = Path(path_arg).expanduser()
    if not path.is_absolute():
        path = (Path.cwd() / path)
    path = path.resolve()
    if not path.is_dir():
        raise SystemExit(f"FEFO: repository directory does not exist: {path}")
    root = git_root(path) or path
    detected_stack, commands, detected_role = detect_repo(root)
    stack = stack or detected_stack
    role = role or detected_role
    commands = detect_commands(root, stack) | {
        k: v for k, v in {"test": test, "lint": lint, "build": build}.items() if v
    }
    name = slugify(name or root.name)
    rel = relative_path(root)
    ensure_unique_name(manifest, name, rel, force)
    repo = {
        "name": name,
        "path": rel,
        "role": role,
        "stack": stack,
        "mcp": f"codegraph-{name}",
        "commands": commands,
    }
    manifest["repos"] = [r for r in manifest["repos"] if r["name"] != name]
    manifest["repos"].append(repo)
    manifest["repos"].sort(key=lambda r: r["name"])
    if index:
        ensure_codegraph(root)
    return repo


def ensure_codegraph(path: Path) -> bool:
    if not command_exists("codegraph"):
        print(f"FEFO: codegraph CLI not found; skipped indexing {path}", file=sys.stderr)
        return False
    db = path / ".codegraph" / "codegraph.db"
    try:
        if db.is_file():
            cmd = ["codegraph", "sync", str(path)]
        else:
            cmd = ["codegraph", "init", "--index", str(path)]
        print(f"FEFO: {' '.join(cmd)}")
        result = subprocess.run(cmd, cwd=str(ROOT), text=True)
        if result.returncode != 0 and db.is_file():
            return False
        return result.returncode == 0
    except Exception as exc:
        print(f"FEFO: codegraph failed for {path}: {exc}", file=sys.stderr)
        return False


# ---------------------------------------------------------------------------
# Generated content
# ---------------------------------------------------------------------------

def repo_rows(manifest: dict) -> str:
    lines = ["| Repository | Role | Stack | Path | CodeGraph |", "|---|---|---|---|---|"]
    for repo in manifest["repos"]:
        lines.append(
            f"| `{repo['name']}` | `{repo['role']}` | `{repo['stack']}` | "
            f"`{repo['path']}` | `{repo['mcp']}` |"
        )
    return "\n".join(lines)


def command_rows(manifest: dict) -> str:
    lines = ["| Repository | Test | Lint | Build / Run |", "|---|---|---|---|"]
    for repo in manifest["repos"]:
        c = repo.get("commands") or {}
        lines.append(
            f"| `{repo['name']}` | `{c.get('test') or '—'}` | `{c.get('lint') or '—'}` | "
            f"`{c.get('build') or c.get('run') or '—'}` |"
        )
    return "\n".join(lines)


DELEGATION_RULES = """\
Subagents run in the background (OpenCode 2.3+): the `subagent` tool returns
immediately and the parent receives a report each time a child goes idle.

1. Map scopes first; one owner per file set; at most four concurrent subagents.
2. Launch every independent subagent in one message.
3. Never poll, sleep, or re-check a child. Continue with non-overlapping work or
   end the turn; the report arrives on its own.
4. Launch a dependent layer only after its prerequisite's report has arrived
   (for example the API contract before the client).
5. Integrate and verify only after every report is in. To give a child more
   work, reuse its `sessionID`."""


def model_line(manifest: dict) -> str:
    model = manifest_model(manifest)
    return f"Model: `{model}`." if model else "Model: the session model (none pinned)."


def generate_agents_md(manifest: dict) -> str:
    repos = repo_rows(manifest) if manifest["repos"] else "No repositories added yet."
    commands = command_rows(manifest) if manifest["repos"] else ""
    return f"""<!-- Generated by FEFO. Edit .fefo/workspace.json or AGENTS.local.md. -->
# {manifest['name']} — FEFO workspace

**FEFO — Flow Execution via Federated Ontology.** This workspace federates the
repositories below into one context. FEFO is the holding layer: it owns routing,
standards, harness adapters, and the knowledge vault. Each repository keeps its
own Git history, dependencies, and test commands.

## Federation

{repos}

## Commands by repository

{commands}

## Routing

| Work | Agent |
|---|---|
| Plan, split, delegate, and integrate | `fefo` |
| Backend / API implementation | `backend` → `model`, `service`, `selector`, `serializer`, `migration`, `test`, `lint` |
| Database design and queries | `database` |
| Web / React / Next.js | `frontend` → `form`, `table`, `api-layer`, `design`, `i18n` |
| Cross-repository contracts | `cross-stack` |
| Architecture and code quality | `architect` |
| Security review | `security` |
| Data / ETL / analytics | `data` |
| Infrastructure and delivery | `infra` |
| Legacy systems | `legacy` |
| External integrations | `integration` |
| Domain specialist | `specialist` (copy and customize) |

The canonical agent definitions live in `.opencode/agents/`. Claude Code wrappers
are generated in `.claude/agents/`; Cursor and Copilot receive pointers in
`.cursor/rules/` and `.github/copilot-instructions.md`.

## Delegation

{DELEGATION_RULES}

## Working rules

1. **CodeGraph first** for source structure, symbols, call flow, and impact. Use
   the repository's `codegraph-*` MCP server. Use the vault for Markdown knowledge.
2. **Contract first** for cross-stack work: update the API contract before the
   client, or declare the change as breaking.
3. **Repository boundaries** are real. Change only the repository required by the
   task and preserve unrelated local work.
4. **No commits, pushes, merges, rebases, or hard resets** without explicit
   authorization. The generated permission rules ask before those commands.
5. **Vault maintained**: add durable domain knowledge and decisions under
   `docs/vault/`. Do not use the vault as a task tracker.
6. **English documentation**, unless the repository explicitly says otherwise.
   Product/UX language follows the repository's own convention.
7. **Tests are proof**: run the focused check first, then the repository's
   delivery checks. Do not claim a check that was not run.
8. **No secrets** in generated files, vault notes, or model output.

## Knowledge

- Start at `docs/vault/00-INDEX.md`.
- Federation snapshot: `docs/vault/federation.md`.
- Repository notes: `docs/vault/repos/`.
- Local instructions that FEFO never overwrites: `AGENTS.local.md`.

## Generated files

`opencode.json`, `.mcp.json`, `.claude/`, `.cursor/rules/fefo.mdc`,
`.github/copilot-instructions.md`, `CLAUDE.md`, `AGENTS.md`, `docs/vault/`, and
`codegraph/README.md` are generated by `./bin/fefo sync`. Put user-owned text in
`AGENTS.local.md` and `docs/vault/`.

## Commands

```sh
./bin/fefo add <path>          # add a repository and refresh the workspace
./bin/fefo remove <name>       # remove a repository
./bin/fefo sync                # regenerate config and harness adapters
./bin/fefo index [name...]     # refresh CodeGraph indexes
./bin/fefo status              # repository and index overview
./bin/fefo doctor              # validate workspace and harnesses
./bin/fefo mcp add ...         # add another MCP server
```

{model_line(manifest)} FEFO does not hardcode a model in any agent; to pin one for
this workspace set `provider.model` in `.fefo/workspace.json` and run `sync`.
"""


def generate_agents_local() -> str:
    return """<!-- FEFO never overwrites this file. Add workspace-specific rules here. -->
# Local instructions

- Add project-specific conventions, owners, and delivery notes here.
- Keep durable domain knowledge in `docs/vault/`, not in this file.
"""


def generate_federation_md(manifest: dict) -> str:
    lines = [
        "# Federation",
        "",
        f"Workspace: **{manifest['name']}**",
        "",
        repo_rows(manifest) if manifest["repos"] else "No repositories added yet.",
        "",
        "## Generated adapters",
        "",
        "- OpenCode: `opencode.json`, `.opencode/`",
        "- Claude Code: `.mcp.json`, `.claude/`, `CLAUDE.md`",
        "- Cursor: `.cursor/rules/fefo.mdc`",
        "- GitHub Copilot: `.github/copilot-instructions.md`",
        "",
        "## Model",
        "",
        f"{model_line(manifest)} Pin one with `provider.model` in `.fefo/workspace.json`.",
        "",
    ]
    if manifest["repos"]:
        lines += ["## Repository commands", "", command_rows(manifest), ""]
    return "\n".join(lines)


def generated_block(repo: dict) -> str:
    c = repo.get("commands") or {}
    return f"""<!-- fefo:generated:start -->
# {repo['name']}

| Field | Value |
|---|---|
| Role | `{repo['role']}` |
| Stack | `{repo['stack']}` |
| Path | `{repo['path']}` |
| CodeGraph MCP | `{repo['mcp']}` |
| Test | `{c.get('test') or '—'}` |
| Lint | `{c.get('lint') or '—'}` |
| Build / run | `{c.get('build') or c.get('run') or '—'}` |
<!-- fefo:generated:end -->"""


def update_generated_block(path: Path, block: str, header: str) -> None:
    if path.is_file():
        text = path.read_text()
        start = text.find("<!-- fefo:generated:start -->")
        end = text.find("<!-- fefo:generated:end -->")
        if start != -1 and end != -1:
            end += len("<!-- fefo:generated:end -->")
            write_text(path, text[:start] + block + text[end:])
            return
        write_text(path, text.rstrip() + "\n\n" + block + "\n")
        return
    write_text(path, header + "\n\n" + block + "\n\n## Domain notes\n\n"
               "<!-- Add durable domain knowledge here. FEFO preserves this section. -->\n")


def generate_vault(manifest: dict) -> None:
    vault = ROOT / "docs" / "vault"
    ensure_dir(vault / "repos")
    index = ["# FEFO Knowledge Vault", "",
             "Start with the federation snapshot and add durable knowledge under `repos/`.", "",
             "- [Federation](federation.md)",
             "- [Decisions](decisions.md)",
             "- [Repository notes](repos/)", ""]
    for repo in manifest["repos"]:
        index.append(f"- [{repo['name']}](repos/{slugify(repo['name'])}.md) — {repo['role']} / {repo['stack']}")
    write_text(vault / "00-INDEX.md", "\n".join(index) + "\n")
    write_text(vault / "federation.md", generate_federation_md(manifest))
    if not (vault / "decisions.md").is_file():
        write_text(vault / "decisions.md", """# Decisions

Record durable decisions here with date, context, decision, and consequence.
Do not use this file as a task tracker.
""")
    if not (vault / "README.md").is_file():
        write_text(vault / "README.md", """# Vault

`docs/vault/` is FEFO's durable knowledge graph. It stores product decisions,
domain rules, architecture relationships, and source-backed notes.

- `00-INDEX.md` is the entry point.
- `federation.md` is generated from `.fefo/workspace.json`.
- `repos/<name>.md` keeps generated repository facts and a user-owned domain section.
- `decisions.md` records decisions that should survive the current task.

Markdown is the source of truth. CodeGraph covers source code; use the vault for
knowledge that cannot be derived from symbols.
""")
    for repo in manifest["repos"]:
        path = vault / "repos" / f"{slugify(repo['name'])}.md"
        update_generated_block(path, generated_block(repo), f"# {repo['name']}")


def generate_codegraph_readme(manifest: dict) -> None:
    lines = [
        "# CodeGraph",
        "",
        "FEFO indexes each federated repository separately. The generated MCP",
        "configuration exposes one `codegraph-<repository>` server per repository,",
        "with an explicit `--path`.",
        "",
        "```sh",
        "./bin/fefo index          # all repositories",
        "./bin/fefo index api web  # selected repositories",
        "```",
        "",
        "Indexes live in each repository's `.codegraph/` directory and are not",
        "committed. Do not copy a database between repositories.",
        "",
    ]
    if manifest["repos"]:
        lines += ["## Federated indexes", ""]
        for repo in manifest["repos"]:
            lines.append(f"- `{repo['name']}` → `{repo['path']}/.codegraph/` (`{repo['mcp']}`)")
        lines.append("")
    write_text(ROOT / "codegraph" / "README.md", "\n".join(lines))


def generate_opencode(manifest: dict) -> None:
    servers = {}
    for repo in manifest["repos"]:
        servers[repo["mcp"]] = {
            "type": "local",
            "command": ["codegraph", "serve", "--mcp", "--path", repo["path"]],
        }
    for name, cfg in (manifest.get("mcp_servers") or {}).items():
        servers[name] = cfg
    references = {}
    for repo in manifest["repos"]:
        references[repo["name"]] = {
            "path": repo["path"],
            "description": f"{repo['role']} repository ({repo['stack']}) in the {manifest['name']} FEFO workspace.",
        }
    config = {
        "$schema": "https://opencode.ai/config.json",
        "default_agent": "fefo",
        "instructions": ["AGENTS.md", "AGENTS.local.md"],
        # Last matching rule wins, so the force-push denies come after the asks.
        "permissions": [
            *({"action": "shell", "resource": resource, "effect": "ask"} for resource in GIT_ASKS),
            *({"action": "shell", "resource": resource, "effect": "deny"} for resource in GIT_DENIES),
            # opencode-fefo asks before any tool call that changes the workspace.
            {"action": "fefo", "resource": "*", "effect": "ask"},
        ],
        "watcher": {"ignore": ["**/.codegraph/**", "**/node_modules/**", "**/.venv/**", "**/venv/**", "**/__pycache__/**"]},
        # Subagents are always background since OpenCode 2.3; there is no depth cap left to set.
        "experimental": {"todo": True},
        "references": references,
        "mcp": {"timeout": {"startup": 90000}, "servers": servers},
    }
    model = manifest_model(manifest)
    if model:
        config["model"] = model
    if manifest.get("plugins"):
        config["plugins"] = list(manifest["plugins"])
    config = deep_merge(config, manifest.get("opencode") or {})
    write_json(ROOT / "opencode.json", config)


def claude_servers(manifest: dict) -> dict:
    servers = {}
    for repo in manifest["repos"]:
        servers[repo["mcp"]] = {
            "type": "stdio",
            "command": "codegraph",
            "args": ["serve", "--mcp", "--path", repo["path"]],
        }
    for name, cfg in (manifest.get("mcp_servers") or {}).items():
        if cfg.get("type") == "local":
            servers[name] = {
                "type": "stdio",
                "command": cfg["command"][0],
                "args": cfg["command"][1:],
            }
            if cfg.get("environment"):
                servers[name]["env"] = cfg["environment"]
        elif cfg.get("type") == "remote" and cfg.get("url"):
            values = list((cfg.get("headers") or {}).values())
            if not any("{file:" in str(v) or "{env:" in str(v) for v in values):
                entry = {"type": "http", "url": cfg["url"]}
                if cfg.get("headers"):
                    entry["headers"] = cfg["headers"]
                servers[name] = entry
    return servers


DEPRECATED_AGENT_FIELDS = ("permission", "tools", "temperature", "top_p", "prompt", "disable", "maxSteps")
WRAPPER_MARKER = "canonical definition of this agent"
OPENCODE_ONLY_COMMAND_FIELDS = ("model", "agent", "subagent", "subtask")


def frontmatter(path: Path) -> str:
    match = re.match(r"^---\n(.*?)\n---\n?", read_text(path), re.S)
    return match.group(1) if match else ""


def fm_field(fm: str, name: str) -> str | None:
    match = re.search(rf"^{name}:[ \t]*(.*)$", fm, re.M)
    if not match:
        return None
    value = match.group(1).strip()
    if value in (">", ">-", "|", "|-"):
        block = re.search(rf"^{name}:.*\n((?:[ \t]+.*\n?)+)", fm, re.M)
        return " ".join(line.strip() for line in block.group(1).splitlines()) if block else ""
    if len(value) >= 2 and value[0] == value[-1] and value[0] in "\"'":
        value = value[1:-1]
    return value


def permission_rules(fm: str) -> list[dict]:
    """Parse a V2 `permissions:` list (block or flow items, any key order)."""
    match = re.search(r"^permissions:[ \t]*\n((?:[ \t]+.*\n?|-.*\n?)+)", fm + "\n", re.M)
    if not match:
        return []
    rules: list[dict] = []
    current: dict | None = None
    for line in match.group(1).splitlines():
        text = line.strip()
        if not text or text.startswith("#"):
            continue
        if text.startswith("- "):
            text = text[2:].strip()
            current = {}
            rules.append(current)
            if text.startswith("{") and text.endswith("}"):
                text = text[1:-1]
                for part in text.split(","):
                    if ":" in part:
                        key, value = part.split(":", 1)
                        current[key.strip()] = value.strip().strip("\"'")
                continue
        if current is None or ":" not in text:
            continue
        key, value = text.split(":", 1)
        current[key.strip()] = value.strip().strip("\"'")
    return rules


def rule_effect(rules: list[dict], action: str) -> str | None:
    """Effect of the last rule that covers every resource of `action` (last match wins)."""
    result = None
    for rule in rules:
        if rule.get("action") in (action, "*") and rule.get("resource") == "*":
            result = rule.get("effect")
    return result


def blocked_tools(fm: str) -> list[str]:
    rules = permission_rules(fm)
    blocked = []
    if rule_effect(rules, "edit") == "deny":
        blocked += ["Edit", "Write"]
    shell = [r for r in rules if r.get("action") in ("shell", "*")]
    if rule_effect(rules, "shell") == "deny" and all(r.get("effect") == "deny" for r in shell):
        blocked.append("Bash")
    return blocked


def claude_wrapper(agent_id: str, fm: str) -> str:
    desc = fm_field(fm, "description") or agent_id
    lines = ["---", f"name: {agent_id}", f"description: {json.dumps(desc, ensure_ascii=False)}"]
    blocked = blocked_tools(fm)
    if blocked:
        lines.append("disallowedTools: " + ", ".join(blocked))
    lines += ["---", "", f"Read `.opencode/agents/{agent_id}.md` and follow it in full. It is the {WRAPPER_MARKER},",
              "shared by OpenCode and Claude Code.", ""]
    return "\n".join(lines)


def sync_claude_adapters() -> None:
    """Derive .claude agents, skills and commands from the canonical OpenCode sources.

    Needs no manifest, so it also works on hand-maintained orchestrators
    (`FEFO_ROOT=<repo> ./bin/fefo adapters`).
    """
    canonical = {p.stem: p for p in sorted((ROOT / ".opencode" / "agents").glob("*.md"))}
    for agent_id, path in canonical.items():
        write_text(ROOT / ".claude" / "agents" / f"{agent_id}.md", claude_wrapper(agent_id, frontmatter(path)))
    for path in sorted((ROOT / ".claude" / "agents").glob("*.md")):
        if path.stem not in canonical and WRAPPER_MARKER in read_text(path):
            remove(path)

    skills = {p.parent.name for p in (ROOT / ".agents" / "skills").glob("*/SKILL.md")}
    for skill_id in sorted(skills):
        link(ROOT / ".claude" / "skills" / skill_id, f"../../.agents/skills/{skill_id}")
    for path in sorted((ROOT / ".claude" / "skills").glob("*")):
        if path.is_symlink() and os.readlink(path).startswith("../../.agents/skills/") and path.name not in skills:
            remove(path)

    commands = set()
    for path in sorted((ROOT / ".opencode" / "commands").glob("*.md")):
        fm = frontmatter(path)
        specific = [name for name in OPENCODE_ONLY_COMMAND_FIELDS if fm_field(fm, name) is not None]
        if specific:
            print(f"skip  .opencode/commands/{path.name}: OpenCode-only frontmatter {specific}")
            continue
        commands.add(path.name)
        link(ROOT / ".claude" / "commands" / path.name, f"../../.opencode/commands/{path.name}")
    for path in sorted((ROOT / ".claude" / "commands").glob("*.md")):
        if path.is_symlink() and os.readlink(path).startswith("../../.opencode/commands/") and path.name not in commands:
            remove(path)


def normalized(command: list) -> list:
    return [arg[2:] if str(arg).startswith("./") else arg for arg in command]


def check_mcp_parity() -> list[str]:
    """Compare opencode.json with .mcp.json / .claude/settings.json (checked, never written)."""
    problems: list[str] = []
    config = ROOT / "opencode.json"
    if not config.is_file():
        return problems
    servers = read_json(config).get("mcp", {}).get("servers", {})
    claude_file = ROOT / ".mcp.json"
    claude = read_json(claude_file).get("mcpServers", {}) if claude_file.is_file() else {}
    settings_file = ROOT / ".claude" / "settings.json"
    disabled = set(read_json(settings_file).get("disabledMcpjsonServers", [])) if settings_file.is_file() else set()
    for name in sorted(set(servers) | set(claude)):
        ours, theirs = servers.get(name), claude.get(name)
        if ours is None:
            problems.append(f"mcp {name}: only in .mcp.json")
            continue
        if theirs is None:
            if ours.get("type") == "remote":
                print(f"info  mcp {name}: remote server, OpenCode-only")
            else:
                problems.append(f"mcp {name}: only in opencode.json")
            continue
        if ours.get("type") == "local":
            same = normalized(ours["command"]) == normalized([theirs.get("command"), *theirs.get("args", [])]) \
                and ours.get("environment", {}) == theirs.get("env", {})
            if not same:
                problems.append(f"mcp {name}: command or environment differs")
        if bool(ours.get("disabled")) != (name in disabled):
            problems.append(f"mcp {name}: disabled in one harness only (.claude/settings.json disabledMcpjsonServers)")
    return problems


def generate_claude(manifest: dict) -> None:
    write_json(ROOT / ".mcp.json", {"mcpServers": claude_servers(manifest)})
    disabled = [
        name for name, cfg in (manifest.get("mcp_servers") or {}).items()
        if cfg.get("disabled")
    ]
    settings = {
        "$schema": "https://json.schemastore.org/claude-code-settings.json",
        "permissions": {
            "ask": [f"Bash({resource})" for resource in GIT_ASKS],
            "deny": [f"Bash({resource})" for resource in GIT_DENIES],
        },
    }
    if disabled:
        settings["disabledMcpjsonServers"] = disabled
    settings = deep_merge(settings, manifest.get("claude_settings") or {})
    write_json(ROOT / ".claude" / "settings.json", settings)
    write_text(ROOT / "CLAUDE.md", f"# {manifest['name']}\n\n@AGENTS.md\n@AGENTS.local.md\n")
    sync_claude_adapters()


def generate_cursor(manifest: dict) -> None:
    content = f"""---
description: {manifest['name']} — FEFO federated workspace routing and conventions
alwaysApply: true
---

# {manifest['name']}

FEFO workspace. Repositories are federated, not merged.

{repo_rows(manifest) if manifest['repos'] else 'No repositories added yet.'}

## Routing

Use `.opencode/agents/` as the canonical agent definitions. `fefo` plans and
delegates; `backend` owns API layers; `frontend` owns web layers; `database`,
`cross-stack`, `architect`, `security`, `data`, `infra`, `legacy`, and
`integration` cover their domains.

## Rules

1. CodeGraph first for source structure and impact.
2. Contract first across repositories.
3. Change only the repository required by the task.
4. Never commit, push, merge, rebase, or hard reset without permission.
5. Keep durable knowledge in `docs/vault/`.
6. Run the repository's focused checks before claiming completion.
7. Subagents run in the background: launch independent ones together, never poll,
   and start dependent work only after the prerequisite reports.
"""
    write_text(ROOT / ".cursor" / "rules" / "fefo.mdc", content)


def generate_copilot(manifest: dict) -> None:
    content = f"""# {manifest['name']} — FEFO workspace

FEFO — Flow Execution via Federated Ontology. This is a holding workspace over
multiple independent repositories. See `AGENTS.md` for the full routing.

{repo_rows(manifest) if manifest['repos'] else 'No repositories added yet.'}

## Rules

- CodeGraph first for source structure and impact.
- Contract first across repositories.
- Change only the repository required by the task.
- Never commit, push, merge, rebase, or hard reset without permission.
- Keep durable knowledge in `docs/vault/`.
- Run the repository's focused checks before claiming completion.
- Subagents run in the background: launch independent ones together, never poll,
  and start dependent work only after the prerequisite reports.
"""
    write_text(ROOT / ".github" / "copilot-instructions.md", content)


def generate_fefo_readme(manifest: dict) -> None:
    write_text(ROOT / ".fefo" / "README.md", """# FEFO state

`workspace.json` is the source of truth. Edit it through `./bin/fefo` commands.

Generated from the manifest:

- `opencode.json`, `.mcp.json`, `.claude/`, `.cursor/rules/fefo.mdc`,
  `.github/copilot-instructions.md`, `CLAUDE.md`
- `AGENTS.md`, `docs/vault/`, `codegraph/README.md`

Customize generated config without editing it by hand. FEFO deep-merges these
manifest fields into the output on every `sync` (objects merge, lists append,
`command`/`args` replace):

- `plugins` — OpenCode plugins (for example `opencode-fefo`)
- `opencode` — extra `opencode.json` settings (`agents`, `formatter`, `skills`, ...)
- `claude_settings` — extra `.claude/settings.json` settings (hooks, permissions)
- `mcp_servers` — extra MCP servers (`./bin/fefo mcp add`)

Check for drift without writing: `./bin/fefo sync --check`.

User-owned files that FEFO does not overwrite:

- `AGENTS.local.md`
- `docs/vault/decisions.md`
- non-generated sections of `docs/vault/repos/*.md`
""")


def sync_all(manifest: dict, check: bool = False) -> list[str]:
    """Regenerate every adapter; with check=True only report what would change."""
    global CHECK
    CHECK = check
    DRIFT.clear()
    CONFLICTS.clear()
    try:
        if not (ROOT / "AGENTS.local.md").exists():
            write_text(ROOT / "AGENTS.local.md", generate_agents_local())
        write_text(ROOT / "AGENTS.md", generate_agents_md(manifest))
        generate_opencode(manifest)
        generate_vault(manifest)
        generate_codegraph_readme(manifest)
        generate_fefo_readme(manifest)
        if "claude" in manifest.get("harnesses", []):
            generate_claude(manifest)
        if "cursor" in manifest.get("harnesses", []):
            generate_cursor(manifest)
        if "copilot" in manifest.get("harnesses", []):
            generate_copilot(manifest)
        save_manifest(manifest)
    finally:
        CHECK = False
    return list(DRIFT)


# ---------------------------------------------------------------------------
# Status and diagnostics
# ---------------------------------------------------------------------------

def index_status(repo: dict) -> str:
    db = repo_path(repo) / ".codegraph" / "codegraph.db"
    if not db.is_file():
        return "missing"
    size = db.stat().st_size
    return f"{size / 1024 / 1024:.1f} MB"


def print_status(manifest: dict) -> None:
    if not manifest["repos"]:
        print("FEFO: no repositories yet. Run `./bin/fefo add <path>`.")
        return
    print(f"FEFO workspace: {manifest['name']}")
    print(f"Model: {manifest_model(manifest) or 'session model (none pinned)'}\n")
    print(f"{'REPO':<20} {'ROLE':<12} {'STACK':<10} {'INDEX':<10} PATH")
    for repo in manifest["repos"]:
        print(f"{repo['name']:<20} {repo['role']:<12} {repo['stack']:<10} {index_status(repo):<10} {repo['path']}")


DEPRECATED_CONFIG_KEYS = {
    "agent", "mode", "tools", "permission", "provider", "command", "plugin", "reference",
    "snapshot", "attachment", "layout", "subagent_depth", "small_model", "autoupdate",
    "autoshare", "logLevel", "server", "disabled_providers", "enabled_providers",
}

# Removed from the experimental block by OpenCode 2.3; configs that still set them load but do nothing.
DEPRECATED_EXPERIMENTAL_KEYS = {"subagent_depth", "background_compaction"}


def opencode_version() -> tuple[int, ...] | None:
    exe = shutil.which("opencode")
    if not exe:
        return None
    try:
        out = subprocess.run([exe, "--version"], capture_output=True, text=True, timeout=15).stdout
    except Exception:
        return None
    match = re.search(r"(\d+)\.(\d+)\.(\d+)", out)
    return tuple(int(part) for part in match.groups()) if match else None


def doctor(manifest: dict) -> int:
    errors = warnings = 0
    def ok(msg): print(f"OK    {msg}")
    def warn(msg):
        nonlocal warnings; warnings += 1; print(f"WARN  {msg}")
    def err(msg):
        nonlocal errors; errors += 1; print(f"ERROR {msg}")

    ok(f"manifest: {MANIFEST_PATH.relative_to(ROOT)}")
    for repo in manifest["repos"]:
        path = repo_path(repo)
        if not path.is_dir():
            err(f"repository missing: {repo['name']} → {path}")
            continue
        if not (path / ".git").exists():
            warn(f"not a Git repository: {repo['name']}")
        if index_status(repo) == "missing":
            warn(f"CodeGraph index missing: {repo['name']} (run ./bin/fefo index {repo['name']})")
        else:
            ok(f"CodeGraph index: {repo['name']} ({index_status(repo)})")
    if command_exists("codegraph"):
        ok("codegraph CLI found")
    else:
        err("codegraph CLI not found on PATH")
    for path in ("opencode.json", ".mcp.json", "AGENTS.md", "docs/vault/00-INDEX.md"):
        if (ROOT / path).is_file():
            ok(f"generated: {path}")
        else:
            err(f"missing generated file: {path}")
    if not list((ROOT / ".opencode" / "agents").glob("*.md")):
        err("no canonical agents found in .opencode/agents")
    if "claude" in manifest.get("harnesses", []):
        if not (ROOT / ".claude" / "settings.json").is_file():
            err("Claude adapter missing: .claude/settings.json")
        else:
            ok("Claude adapter present")

    version = opencode_version()
    if version is None:
        warn("opencode CLI not found on PATH; cannot check its version")
    elif version < MIN_OPENCODE:
        warn(f"OpenCode {'.'.join(map(str, version))} is older than {'.'.join(map(str, MIN_OPENCODE))}; "
             "background subagents and the documented config need 2.3.0+")
    else:
        ok(f"opencode {'.'.join(map(str, version))}")

    config = ROOT / "opencode.json"
    if config.is_file():
        try:
            data = read_json(config)
        except ValueError as exc:
            err(f"opencode.json is not valid JSON: {exc}")
        else:
            deprecated = sorted(set(data) & DEPRECATED_CONFIG_KEYS)
            if deprecated:
                warn(f"opencode.json uses deprecated keys: {', '.join(deprecated)}")
            dead = sorted(set(data.get("experimental") or {}) & DEPRECATED_EXPERIMENTAL_KEYS)
            if dead:
                warn(f"opencode.json sets removed experimental keys: {', '.join(dead)}")

    for kind in ("agents", "commands"):
        for path in sorted((ROOT / ".opencode" / kind).glob("*.md")):
            fm = frontmatter(path)
            if not fm:
                warn(f"{rel(path)}: missing frontmatter")
                continue
            keys = set(re.findall(r"^([A-Za-z_]+):", fm, re.M))
            old = [k for k in DEPRECATED_AGENT_FIELDS if k in keys]
            if old:
                warn(f"{rel(path)}: deprecated V1 frontmatter ({', '.join(old)}); use `permissions:` rules")
            if kind != "agents":
                continue
            if "description" not in keys:
                warn(f"{rel(path)}: agent without description (the subagent catalog shows it to the model)")
            if "model" in keys:
                warn(f"{rel(path)}: pins a model; FEFO agents inherit the session model")
            rules = permission_rules(fm)
            if rule_effect(rules, "edit") == "deny" and rule_effect(rules, "shell") != "deny":
                warn(f"{rel(path)}: denies edit but can still write through the shell tool")

    for name, cfg in (manifest.get("mcp_servers") or {}).items():
        secrets = {**(cfg.get("headers") or {}), **(cfg.get("environment") or {})}
        for key, value in secrets.items():
            if isinstance(value, str) and re.search(r"(?i)auth|token|key|secret|pass", key) \
                    and "{env:" not in value and "{file:" not in value:
                warn(f"MCP {name}: '{key}' holds a literal value; use {{env:...}} or {{file:...}}")

    drift = sync_all(manifest, check=True)
    if CONFLICTS:
        err(f"harness adapters blocked by real files: {', '.join(CONFLICTS[:5])}")
    if drift:
        shown = ", ".join(drift[:6]) + (" ..." if len(drift) > 6 else "")
        warn(f"{len(drift)} generated file(s) out of date: {shown} (run ./bin/fefo sync)")
    else:
        ok("generated files in sync")
    print(f"\n{errors} error(s), {warnings} warning(s)")
    return 1 if errors else 0


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="fefo", description="FEFO workspace manager")
    sub = parser.add_subparsers(dest="command", required=True)

    p = sub.add_parser("init", help="create a FEFO workspace")
    p.add_argument("--name", default=None)
    p.add_argument("--repo", action="append", default=[])
    p.add_argument("--provider-model", default=None,
                   help=f"pin a model for the workspace (for example {RECOMMENDED_MODEL}); default: none")
    p.add_argument("--harness", action="append", choices=HARNESSES, default=None)
    p.add_argument("--no-index", action="store_true")
    p.add_argument("--force", action="store_true")
    p.add_argument("--yes", action="store_true")
    p.set_defaults(func=cmd_init)

    p = sub.add_parser("add", help="add a repository")
    p.add_argument("path")
    p.add_argument("--name")
    p.add_argument("--role", choices=ROLES)
    p.add_argument("--stack", choices=STACKS)
    p.add_argument("--test")
    p.add_argument("--lint")
    p.add_argument("--build")
    p.add_argument("--no-index", action="store_true")
    p.add_argument("--force", action="store_true")
    p.set_defaults(func=cmd_add)

    p = sub.add_parser("remove", help="remove a repository")
    p.add_argument("name")
    p.set_defaults(func=cmd_remove)

    p = sub.add_parser("sync", help="regenerate config and adapters")
    p.add_argument("--check", action="store_true", help="report generated files that are out of date; write nothing")
    p.set_defaults(func=cmd_sync)

    p = sub.add_parser("adapters", help="derive Claude agents, skills and commands from .opencode/.agents")
    p.add_argument("--check", action="store_true", help="report drift; write nothing")
    p.set_defaults(func=cmd_adapters)

    p = sub.add_parser("index", help="refresh CodeGraph indexes")
    p.add_argument("names", nargs="*")
    p.set_defaults(func=cmd_index)

    p = sub.add_parser("status", help="show repositories and indexes")
    p.set_defaults(func=cmd_status)

    p = sub.add_parser("doctor", help="validate the workspace")
    p.set_defaults(func=cmd_doctor)

    p = sub.add_parser("mcp", help="manage additional MCP servers")
    msub = p.add_subparsers(dest="mcp_command", required=True)
    m = msub.add_parser("add", help="add a local or remote MCP server")
    m.add_argument("name")
    m.add_argument("--local", action="store_true")
    m.add_argument("--remote")
    m.add_argument("--header", action="append", default=[])
    m.add_argument("--env", action="append", default=[])
    m.add_argument("--no-oauth", action="store_true")
    m.add_argument("rest", nargs=argparse.REMAINDER)
    m.set_defaults(func=cmd_mcp_add)
    m = msub.add_parser("remove", help="remove an MCP server")
    m.add_argument("name")
    m.set_defaults(func=cmd_mcp_remove)
    m = msub.add_parser("list", help="list MCP servers")
    m.set_defaults(func=cmd_mcp_list)
    return parser


def cmd_init(args) -> int:
    if MANIFEST_PATH.exists() and not args.force:
        raise SystemExit("FEFO: workspace already initialized; use --force to replace it.")
    name = args.name or ROOT.name
    manifest = default_manifest(name)
    manifest["provider"]["model"] = args.provider_model
    if args.harness:
        manifest["harnesses"] = args.harness
    repos = list(args.repo)
    if not repos and not args.yes and sys.stdin.isatty():
        print(f"FEFO init — workspace: {name}")
        print("Enter repository paths one per line; leave blank to finish.")
        while True:
            value = input("repo path> ").strip()
            if not value:
                break
            repos.append(value)
    for path in repos:
        add_repo(manifest, path, index=not args.no_index)
    save_manifest(manifest)
    sync_all(manifest)
    print(f"FEFO: initialized {name} with {len(manifest['repos'])} repositories")
    print_status(manifest)
    return 0


def cmd_add(args) -> int:
    manifest = load_manifest()
    repo = add_repo(
        manifest, args.path, name=args.name, role=args.role, stack=args.stack,
        test=args.test, lint=args.lint, build=args.build,
        index=not args.no_index, force=args.force,
    )
    sync_all(manifest)
    print(f"FEFO: added {repo['name']} ({repo['role']}/{repo['stack']}) at {repo['path']}")
    return 0


def cmd_remove(args) -> int:
    manifest = load_manifest()
    before = len(manifest["repos"])
    manifest["repos"] = [r for r in manifest["repos"] if r["name"] != args.name]
    if len(manifest["repos"]) == before:
        raise SystemExit(f"FEFO: repository not found: {args.name}")
    sync_all(manifest)
    print(f"FEFO: removed {args.name}")
    return 0


def cmd_sync(args) -> int:
    manifest = load_manifest()
    if args.check:
        drift = sync_all(manifest, check=True)
        for path in drift:
            print(f"DRIFT {path}")
        if drift or CONFLICTS:
            print(f"FEFO: {len(drift)} generated file(s) out of date; run ./bin/fefo sync")
            return 1
        print("FEFO: workspace in sync")
        return 0
    sync_all(manifest)
    print("FEFO: workspace synchronized")
    return 0


def cmd_adapters(args) -> int:
    """Claude adapters only. Needs no manifest: FEFO_ROOT=<orchestrator> ./bin/fefo adapters --check."""
    global CHECK
    CHECK = args.check
    DRIFT.clear()
    CONFLICTS.clear()
    try:
        sync_claude_adapters()
    finally:
        CHECK = False
    problems = check_mcp_parity()
    for path in DRIFT:
        print(("DRIFT " if args.check else "fix   ") + path)
    for problem in problems:
        print("DRIFT " + problem)
    failed = bool(CONFLICTS or problems or (args.check and DRIFT))
    if failed:
        print("FEFO: harness adapters out of sync" + ("; run without --check to regenerate" if args.check else ""))
    else:
        print("FEFO: harness adapters in sync")
    return 1 if failed else 0


def cmd_index(args) -> int:
    manifest = load_manifest()
    selected = set(args.names)
    repos = [r for r in manifest["repos"] if not selected or r["name"] in selected]
    if selected and len(repos) != len(selected):
        missing = selected - {r["name"] for r in repos}
        raise SystemExit(f"FEFO: unknown repository: {', '.join(sorted(missing))}")
    for repo in repos:
        ensure_codegraph(repo_path(repo))
    print_status(manifest)
    return 0


def cmd_status(args) -> int:
    print_status(load_manifest())
    return 0


def cmd_doctor(args) -> int:
    return doctor(load_manifest())


def parse_pairs(values: list[str], label: str) -> dict:
    result = {}
    for value in values:
        if "=" not in value:
            raise SystemExit(f"FEFO: {label} must be key=value: {value}")
        key, val = value.split("=", 1)
        result[key] = val
    return result


def split_mcp_rest(rest: list[str]) -> tuple[list[str], str | None, list[str], list[str], bool]:
    """Parse mcp flags that argparse.REMAINDER captured after the server name."""
    command: list[str] = []
    remote = None
    headers: list[str] = []
    environment: list[str] = []
    no_oauth = False
    index = 0
    while index < len(rest):
        value = rest[index]
        if value == "--":
            command.extend(rest[index + 1:])
            break
        if value == "--local":
            index += 1
            continue
        if value == "--remote" and index + 1 < len(rest):
            remote = rest[index + 1]
            index += 2
            continue
        if value == "--header" and index + 1 < len(rest):
            headers.append(rest[index + 1])
            index += 2
            continue
        if value == "--env" and index + 1 < len(rest):
            environment.append(rest[index + 1])
            index += 2
            continue
        if value == "--no-oauth":
            no_oauth = True
            index += 1
            continue
        command.append(value)
        index += 1
    return command, remote, headers, environment, no_oauth


def cmd_mcp_add(args) -> int:
    manifest = load_manifest()
    command, rest_remote, rest_headers, rest_env, rest_no_oauth = split_mcp_rest(list(args.rest))
    remote = args.remote or rest_remote
    headers = parse_pairs([*args.header, *rest_headers], "--header")
    environment = parse_pairs([*args.env, *rest_env], "--env")
    no_oauth = args.no_oauth or rest_no_oauth
    if remote:
        config = {"type": "remote", "url": remote, "oauth": False if no_oauth else True}
        if headers:
            config["headers"] = headers
    else:
        if not command:
            raise SystemExit("FEFO: local MCP needs a command after `--`.")
        config = {"type": "local", "command": command}
        if environment:
            config["environment"] = environment
    manifest.setdefault("mcp_servers", {})[args.name] = config
    sync_all(manifest)
    print(f"FEFO: added MCP {args.name}")
    return 0


def cmd_mcp_remove(args) -> int:
    manifest = load_manifest()
    if args.name not in (manifest.get("mcp_servers") or {}):
        raise SystemExit(f"FEFO: MCP not found: {args.name}")
    del manifest["mcp_servers"][args.name]
    sync_all(manifest)
    print(f"FEFO: removed MCP {args.name}")
    return 0


def cmd_mcp_list(args) -> int:
    manifest = load_manifest()
    servers = {r["mcp"]: {"type": "local", "command": ["codegraph", "serve", "--mcp", "--path", r["path"]]} for r in manifest["repos"]}
    servers.update(manifest.get("mcp_servers") or {})
    for name, cfg in servers.items():
        if cfg.get("type") == "local":
            print(f"{name}\tlocal\t{' '.join(cfg.get('command', []))}")
        else:
            print(f"{name}\tremote\t{cfg.get('url', '')}")
    if not servers:
        print("FEFO: no MCP servers configured")
    return 0


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
