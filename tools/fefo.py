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
DEFAULT_MODEL = "opencode-go/deepseek-v4.1-flash"
HARNESSES = ("opencode", "claude", "cursor", "copilot")
ROLES = (
    "orchestrator", "api", "web", "mobile", "data", "infra", "legacy",
    "integration", "docs", "service", "library",
)
STACKS = (
    "django", "fastapi", "flask", "next", "react", "flutter",
    "docs", "infra", "generic",
)
GIT_ASKS = [
    "git commit *", "git -C * commit *",
    "git push *", "git -C * push *",
    "git merge *", "git -C * merge *",
    "git rebase *", "git -C * rebase *",
    "git reset --hard*", "git -C * reset --hard*",
]


# ---------------------------------------------------------------------------
# Files and manifest
# ---------------------------------------------------------------------------

def slugify(value: str) -> str:
    value = re.sub(r"[^a-zA-Z0-9]+", "-", value.strip().lower())
    return value.strip("-") or "repo"


def read_json(path: Path) -> dict:
    return json.loads(path.read_text())


def write_json(path: Path, data) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n")


def write_text(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.is_file() and path.read_text() == content:
        return
    path.write_text(content)


def default_manifest(name: str) -> dict:
    return {
        "fefo": 1,
        "name": name,
        "generated_at": None,
        "provider": {"model": DEFAULT_MODEL},
        "harnesses": list(HARNESSES),
        "repos": [],
        "mcp_servers": {},
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
    data["generated_at"] = datetime.now(timezone.utc).isoformat()
    write_json(MANIFEST_PATH, data)


def validate_manifest(data: dict) -> None:
    if data.get("fefo") != 1:
        raise SystemExit("FEFO: unsupported manifest version; expected fefo: 1.")
    if not data.get("name"):
        raise SystemExit("FEFO: manifest is missing a workspace name.")
    provider = data.get("provider") or {}
    if not provider.get("model"):
        raise SystemExit("FEFO: manifest is missing provider.model.")
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
    elif stack in ("next", "react"):
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
        "django": "api", "fastapi": "api", "flask": "api",
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

Provider: `{manifest['provider']['model']}`. FEFO does not hardcode a model in any
agent; change the provider or model in `.fefo/workspace.json` and run `sync`.
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
        f"`{manifest['provider']['model']}` (change in `.fefo/workspace.json`).",
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
    (vault / "repos").mkdir(parents=True, exist_ok=True)
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
        "model": manifest["provider"]["model"],
        "default_agent": "fefo",
        "instructions": ["AGENTS.md", "AGENTS.local.md"],
        "permissions": [
            {"action": "shell", "resource": resource, "effect": "ask"}
            for resource in GIT_ASKS
        ],
        "watcher": {"ignore": ["**/.codegraph/**", "**/node_modules/**", "**/.venv/**", "**/venv/**", "**/__pycache__/**"]},
        "experimental": {"subagent_depth": 2, "todo": True},
        "references": references,
        "mcp": {"timeout": {"startup": 90000}, "servers": servers},
    }
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


def generate_claude(manifest: dict) -> None:
    write_json(ROOT / ".mcp.json", {"mcpServers": claude_servers(manifest)})
    disabled = [
        name for name, cfg in (manifest.get("mcp_servers") or {}).items()
        if cfg.get("disabled")
    ]
    settings = {
        "$schema": "https://json.schemastore.org/claude-code-settings.json",
        "permissions": {"ask": [f"Bash({resource})" for resource in GIT_ASKS]},
    }
    if disabled:
        settings["disabledMcpjsonServers"] = disabled
    write_json(ROOT / ".claude" / "settings.json", settings)
    write_text(ROOT / "CLAUDE.md", f"# {manifest['name']}\n\n@AGENTS.md\n@AGENTS.local.md\n")

    agents_dir = ROOT / ".claude" / "agents"
    agents_dir.mkdir(parents=True, exist_ok=True)
    canonical = {}
    for path in sorted((ROOT / ".opencode" / "agents").glob("*.md")):
        text = path.read_text()
        fm = re.match(r"^---\n(.*?)\n---", text, re.S)
        fm = fm.group(1) if fm else ""
        desc = re.search(r"^description:\s*(.+)$", fm, re.M)
        desc = desc.group(1).strip().strip("\"'") if desc else path.stem
        canonical[path.stem] = (desc, bool(re.search(
            r"action:\s*edit\s*\n\s*resource:[^\n]*\n\s*effect:\s*deny", fm)))
    for agent_id, (desc, deny) in canonical.items():
        lines = ["---", f"name: {agent_id}", f"description: {json.dumps(desc, ensure_ascii=False)}"]
        if deny:
            lines.append("disallowedTools: Edit, Write")
        lines += ["---", "", f"Read `.opencode/agents/{agent_id}.md` and follow it in full.",
                  "It is the canonical definition of this agent, shared by OpenCode and Claude Code.", ""]
        write_text(agents_dir / f"{agent_id}.md", "\n".join(lines))
    marker = "canonical definition of this agent"
    for path in agents_dir.glob("*.md"):
        if path.stem not in canonical and marker in path.read_text():
            path.unlink()

    skills_dir = ROOT / ".claude" / "skills"
    skills_dir.mkdir(parents=True, exist_ok=True)
    for skill in sorted((ROOT / ".agents" / "skills").glob("*/SKILL.md")):
        link = skills_dir / skill.parent.name
        target = f"../../.agents/skills/{skill.parent.name}"
        if link.is_symlink() and os.readlink(link) == target:
            continue
        if link.exists() or link.is_symlink():
            if link.is_symlink():
                link.unlink()
            else:
                continue
        link.symlink_to(target)

    commands_dir = ROOT / ".claude" / "commands"
    commands_dir.mkdir(parents=True, exist_ok=True)
    for command in sorted((ROOT / ".opencode" / "commands").glob("*.md")):
        link = commands_dir / command.name
        target = f"../../.opencode/commands/{command.name}"
        if link.is_symlink() and os.readlink(link) == target:
            continue
        if link.exists() or link.is_symlink():
            if link.is_symlink():
                link.unlink()
            else:
                continue
        link.symlink_to(target)


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
"""
    write_text(ROOT / ".github" / "copilot-instructions.md", content)


def generate_fefo_readme(manifest: dict) -> None:
    write_text(ROOT / ".fefo" / "README.md", """# FEFO state

`workspace.json` is the source of truth. Edit it through `./bin/fefo` commands.

Generated from the manifest:

- `opencode.json`, `.mcp.json`, `.claude/`, `.cursor/rules/fefo.mdc`,
  `.github/copilot-instructions.md`, `CLAUDE.md`
- `AGENTS.md`, `docs/vault/`, `codegraph/README.md`

User-owned files that FEFO does not overwrite:

- `AGENTS.local.md`
- `docs/vault/decisions.md`
- non-generated sections of `docs/vault/repos/*.md`
""")


def sync_all(manifest: dict) -> None:
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
    print(f"Model: {manifest['provider']['model']}\n")
    print(f"{'REPO':<20} {'ROLE':<12} {'STACK':<10} {'INDEX':<10} PATH")
    for repo in manifest["repos"]:
        print(f"{repo['name']:<20} {repo['role']:<12} {repo['stack']:<10} {index_status(repo):<10} {repo['path']}")


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
    p.add_argument("--provider-model", default=DEFAULT_MODEL)
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
    p.set_defaults(func=cmd_sync)

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
    sync_all(manifest)
    print("FEFO: workspace synchronized")
    return 0


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
