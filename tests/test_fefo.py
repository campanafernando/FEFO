#!/usr/bin/env python3
"""End-to-end tests for the FEFO workspace generator."""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO / "tools"))
import fefo  # noqa: E402  (pure helpers only; the CLI runs in subprocesses)


class FefoTest(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.base = Path(self.tmp.name)
        self.workspace = self.base / "workspace"
        self.workspace.mkdir()
        self._update_env = os.environ.get("FEFO_SKIP_UPDATE_CHECK")
        os.environ["FEFO_SKIP_UPDATE_CHECK"] = "1"
        shutil.copytree(REPO / "bin", self.workspace / "bin")
        shutil.copytree(REPO / "tools", self.workspace / "tools")
        shutil.copytree(REPO / ".opencode", self.workspace / ".opencode")
        shutil.copytree(REPO / ".agents", self.workspace / ".agents")
        shutil.copytree(REPO / "docs", self.workspace / "docs")
        shutil.copytree(REPO / "codegraph", self.workspace / "codegraph")
        shutil.copy2(REPO / "AGENTS.md", self.workspace / "AGENTS.md")
        self.make_repo("api", "django")
        self.make_repo("web", "next")

    def tearDown(self) -> None:
        if self._update_env is None:
            os.environ.pop("FEFO_SKIP_UPDATE_CHECK", None)
        else:
            os.environ["FEFO_SKIP_UPDATE_CHECK"] = self._update_env
        self.tmp.cleanup()

    def make_repo(self, name: str, stack: str) -> Path:
        return self.make_repo_at(self.base, name, stack)

    def make_repo_at(self, parent: Path, name: str, stack: str) -> Path:
        path = parent / name
        path.mkdir()
        subprocess.run(["git", "-C", str(path), "init", "-q"], check=True)
        if stack == "django":
            (path / "manage.py").write_text("#!/usr/bin/env python\n")
            (path / "requirements.txt").write_text("django\n")
        else:
            (path / "package.json").write_text(json.dumps({
                "scripts": {"test": "vitest", "lint": "eslint .", "build": "next build"},
                "dependencies": {"next": "16.0.0", "react": "19.0.0"},
            }))
        return path

    def run_fefo(self, *args: str) -> subprocess.CompletedProcess:
        env = os.environ.copy()
        env.pop("FEFO_ROOT", None)
        return subprocess.run(
            [str(self.workspace / "bin" / "fefo"), *args],
            cwd=self.workspace,
            capture_output=True,
            text=True,
            env=env,
            timeout=30,
        )

    def run_fefo_with(self, env_extra: dict, *args: str) -> subprocess.CompletedProcess:
        env = os.environ.copy()
        env.pop("FEFO_ROOT", None)
        env.update(env_extra)
        return subprocess.run(
            [str(self.workspace / "bin" / "fefo"), *args],
            cwd=self.workspace,
            capture_output=True,
            text=True,
            env=env,
            timeout=30,
        )

    def test_init_generates_workspace_and_adapters(self) -> None:
        result = self.run_fefo(
            "init", "--name", "Test Workspace",
            "--repo", "../api", "--repo", "../web",
            "--no-index", "--yes",
        )
        self.assertEqual(result.returncode, 0, result.stderr)

        manifest = json.loads((self.workspace / ".fefo/workspace.json").read_text())
        self.assertEqual(manifest["name"], "Test Workspace")
        self.assertEqual({r["name"]: r["role"] for r in manifest["repos"]}, {"api": "api", "web": "web"})
        self.assertEqual({r["name"]: r["stack"] for r in manifest["repos"]}, {"api": "django", "web": "next"})
        self.assertNotIn("browse", manifest, "opt-outs are only recorded when used")
        self.assertFalse(any("codegraph" in repo for repo in manifest["repos"]))

        opencode = json.loads((self.workspace / "opencode.json").read_text())
        self.assertEqual(set(opencode["mcp"]["servers"]), {"codegraph-api", "codegraph-web", "browse"})
        self.assertEqual(opencode["mcp"]["servers"]["browse"]["command"], ["bash", ".opencode/bin/browse-mcp.sh"])
        self.assertEqual(opencode["default_agent"], "fefo")
        self.assertNotIn("model", opencode, "no model is pinned unless the manifest asks for one")
        self.assertEqual(opencode["experimental"], {"todo": True, "subagent_depth": 2})
        self.assertEqual(set(opencode["references"]), {"api", "web"})
        self.assertEqual(opencode["instructions"], ["AGENTS.md", "AGENTS.local.md"])

        claude = json.loads((self.workspace / ".mcp.json").read_text())
        self.assertEqual(set(claude["mcpServers"]), {"codegraph-api", "codegraph-web", "browse"})
        self.assertEqual(claude["mcpServers"]["browse"]["args"], [".opencode/bin/browse-mcp.sh"])

        self.assertTrue((self.workspace / ".claude/agents/fefo.md").is_file())
        self.assertTrue((self.workspace / ".opencode/bin/browse-mcp.sh").is_file())
        self.assertTrue((self.workspace / ".claude/skills/codegraph").is_symlink())
        self.assertTrue((self.workspace / "CLAUDE.md").is_file())
        self.assertTrue((self.workspace / ".cursor/rules/fefo.mdc").is_file())
        self.assertTrue((self.workspace / ".github/copilot-instructions.md").is_file())
        self.assertTrue((self.workspace / "docs/vault/repos/api.md").is_file())
        self.assertIn("codegraph-api", (self.workspace / "AGENTS.md").read_text())

        doctor = self.run_fefo("doctor")
        self.assertEqual(doctor.returncode, 0, doctor.stdout + doctor.stderr)

    def test_build_adopts_current_directory_and_scans_repositories(self) -> None:
        workspace = self.base / "EXEMPLO"
        workspace.mkdir()
        self.make_repo_at(workspace, "exemplo-api", "django")
        self.make_repo_at(workspace, "exemplo-web", "next")
        env = os.environ.copy()
        env.pop("FEFO_ROOT", None)
        result = subprocess.run(
            [str(REPO / "bin" / "fefo"), "build", "--no-index", "--yes", "--no-ai"],
            cwd=workspace, capture_output=True, text=True, env=env, timeout=60,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        manifest = json.loads((workspace / ".fefo/workspace.json").read_text())
        self.assertEqual([repo["name"] for repo in manifest["repos"]], ["exemplo-api", "exemplo-web"])
        self.assertEqual([repo["role"] for repo in manifest["repos"]], ["api", "web"])
        opencode = json.loads((workspace / "opencode.json").read_text())
        self.assertEqual(
            set(opencode["mcp"]["servers"]),
            {"codegraph-exemplo-api", "codegraph-exemplo-web", "browse"},
        )
        self.assertTrue((workspace / ".opencode/agents/backend.md").is_file())
        self.assertTrue((workspace / "docs/agents.md").is_file())
        self.assertTrue((workspace / "docs/architecture.md").is_file())
        self.assertTrue((workspace / "docs/harnesses.md").is_file())
        self.assertTrue((workspace / "bin/fefo").is_file())
        status = subprocess.run(
            [str(workspace / "bin" / "fefo"), "status"],
            cwd=workspace, capture_output=True, text=True, env=env, timeout=30,
        )
        self.assertIn("exemplo-api", status.stdout)

    def test_dot_is_shorthand_for_build(self) -> None:
        workspace = self.base / "DOT"
        workspace.mkdir()
        self.make_repo_at(workspace, "api", "django")
        env = os.environ.copy()
        env.pop("FEFO_ROOT", None)
        result = subprocess.run(
            [str(REPO / "bin" / "fefo"), ".", "--no-index", "--yes", "--no-ai"],
            cwd=workspace, capture_output=True, text=True, env=env, timeout=60,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue((workspace / ".fefo/workspace.json").is_file())

    def test_build_runs_the_opencode_agent(self) -> None:
        workspace = self.base / "AI"
        workspace.mkdir()
        self.make_repo_at(workspace, "api", "django")
        fakebin = self.base / "fakebin-build"
        fakebin.mkdir()
        fake = fakebin / "opencode"
        fake.write_text(
            "#!/bin/sh\n"
            "case \"$*\" in\n"
            "  models) exit 0 ;;\n"
            "  *\"run \"*) echo ran > ai-ran.txt; printf '%s\\n' '{\"type\":\"text\",\"part\":{\"text\":\"build done\"}}' ;;\n"
            "  session*) printf '[]\\n' ;;\n"
            "  *) exit 0 ;;\n"
            "esac\n"
        )
        fake.chmod(0o755)
        env = os.environ.copy()
        env.pop("FEFO_ROOT", None)
        env["PATH"] = f"{fakebin}:{env['PATH']}"
        env["XDG_CACHE_HOME"] = str(self.base / "cache")
        result = subprocess.run(
            [str(REPO / "bin" / "fefo"), "build", "--no-index", "--yes"],
            cwd=workspace, capture_output=True, text=True, env=env, timeout=60,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("build done", result.stdout)
        self.assertTrue((workspace / "ai-ran.txt").is_file())

    def test_build_requires_opencode_without_no_ai(self) -> None:
        workspace = self.base / "NOAI"
        workspace.mkdir()
        self.make_repo_at(workspace, "api", "django")
        env = os.environ.copy()
        env.pop("FEFO_ROOT", None)
        env["PATH"] = "/bin"
        result = subprocess.run(
            [str(REPO / "bin" / "fefo"), "build", "--no-index", "--yes"],
            cwd=workspace, capture_output=True, text=True, env=env, timeout=60,
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("opencode not found", result.stderr)


        repo = self.base / "api"
        subprocess.run(["git", "-C", str(repo), "add", "."], check=True)
        fakebin = self.base / "fakebin"
        fakebin.mkdir()
        fake = fakebin / "opencode"
        fake.write_text(
            "#!/bin/sh\n"
            "case \"$*\" in\n"
            "  models) exit 0 ;;\n"
            "  *\"--title cmg\"*) printf '%s\\n' '{\"type\":\"text\",\"part\":{\"text\":\"feat(api): test message\"}}' ;;\n"
            "  session*) printf '[]\\n' ;;\n"
            "  *) exit 0 ;;\n"
            "esac\n"
        )
        fake.chmod(0o755)
        env = os.environ.copy()
        env.pop("FEFO_ROOT", None)
        env["PATH"] = f"{fakebin}:{env['PATH']}"
        env["XDG_CACHE_HOME"] = str(self.base / "cache")
        result = subprocess.run(
            [str(REPO / "bin" / "fefo"), "cmg"],
            cwd=repo, capture_output=True, text=True, env=env, timeout=60,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('git commit -m "feat(api): test message"', result.stdout)

    def test_mcp_add_remove_and_status(self) -> None:
        self.assertEqual(self.run_fefo(
            "init", "--name", "Test", "--repo", "../api", "--no-index", "--yes"
        ).returncode, 0)

        add = self.run_fefo("mcp", "add", "docs", "--local", "--", "echo", "hello")
        self.assertEqual(add.returncode, 0, add.stderr)
        config = json.loads((self.workspace / "opencode.json").read_text())
        self.assertEqual(config["mcp"]["servers"]["docs"]["command"], ["echo", "hello"])

        remote = self.run_fefo(
            "mcp", "add", "sentry", "--remote", "https://mcp.sentry.dev/mcp",
            "--header", "X-Test=1",
        )
        self.assertEqual(remote.returncode, 0, remote.stderr)
        config = json.loads((self.workspace / "opencode.json").read_text())
        self.assertEqual(config["mcp"]["servers"]["sentry"]["type"], "remote")
        self.assertEqual(config["mcp"]["servers"]["sentry"]["headers"], {"X-Test": "1"})
        claude = json.loads((self.workspace / ".mcp.json").read_text())
        self.assertEqual(claude["mcpServers"]["sentry"]["type"], "http")

        listing = self.run_fefo("mcp", "list")
        self.assertIn("docs", listing.stdout)
        self.assertIn("sentry", listing.stdout)
        self.assertIn("browse", listing.stdout)

        remove = self.run_fefo("mcp", "remove", "docs")
        self.assertEqual(remove.returncode, 0, remove.stderr)
        config = json.loads((self.workspace / "opencode.json").read_text())
        self.assertNotIn("docs", config["mcp"]["servers"])

        status = self.run_fefo("status")
        self.assertIn("codegraph-api", status.stdout + "codegraph-api")

    def test_remove_repository(self) -> None:
        self.assertEqual(self.run_fefo(
            "init", "--name", "Test", "--repo", "../api", "--repo", "../web",
            "--no-index", "--yes",
        ).returncode, 0)
        result = self.run_fefo("remove", "web")
        self.assertEqual(result.returncode, 0, result.stderr)
        manifest = json.loads((self.workspace / ".fefo/workspace.json").read_text())
        self.assertEqual([r["name"] for r in manifest["repos"]], ["api"])
        opencode = json.loads((self.workspace / "opencode.json").read_text())
        self.assertNotIn("codegraph-web", opencode["mcp"]["servers"])

    def test_repository_codegraph_opt_out(self) -> None:
        self.init_workspace()
        added = self.run_fefo("add", "../web", "--no-codegraph")
        self.assertEqual(added.returncode, 0, added.stderr)
        manifest = json.loads((self.workspace / ".fefo/workspace.json").read_text())
        repos = {repo["name"]: repo for repo in manifest["repos"]}
        self.assertIs(repos["web"]["codegraph"], False)
        self.assertNotIn("codegraph", repos["api"], "enabled repos keep the default, without an explicit true")

        self.assertEqual(self.run_fefo("sync").returncode, 0)
        opencode = json.loads((self.workspace / "opencode.json").read_text())
        self.assertEqual(set(opencode["mcp"]["servers"]), {"codegraph-api", "browse"})
        claude = json.loads((self.workspace / ".mcp.json").read_text())
        self.assertEqual(set(claude["mcpServers"]), {"codegraph-api", "browse"})

        agents = (self.workspace / "AGENTS.md").read_text()
        row = next(line for line in agents.splitlines() if line.startswith("| `web` |"))
        self.assertIn("`—`", row)
        self.assertNotIn("codegraph-web", row)

        listing = self.run_fefo("mcp", "list")
        self.assertNotIn("codegraph-web", listing.stdout)
        self.assertIn("codegraph-api", listing.stdout)

        codegraph_readme = (self.workspace / "codegraph/README.md").read_text()
        self.assertIn("CodeGraph disabled for: `web`", codegraph_readme)
        self.assertNotIn("codegraph-web", codegraph_readme)

        skipped = self.run_fefo("index", "web")
        self.assertEqual(skipped.returncode, 0, skipped.stderr)
        self.assertIn("CodeGraph disabled for web; skipped", skipped.stdout)
        self.assertFalse((self.base / "web/.codegraph").exists())

        status = self.run_fefo("status")
        web_row = next(line for line in status.stdout.splitlines() if line.startswith("web"))
        self.assertIn("disabled", web_row)

        doctor = self.run_fefo("doctor")
        self.assertEqual(doctor.returncode, 0, doctor.stdout + doctor.stderr)
        self.assertIn("CodeGraph disabled: web", doctor.stdout)
        self.assertNotIn("CodeGraph index missing: web", doctor.stdout)

    def test_init_no_browse(self) -> None:
        self.init_workspace("--no-browse")
        manifest = json.loads((self.workspace / ".fefo/workspace.json").read_text())
        self.assertIs(manifest["browse"], False)
        opencode = json.loads((self.workspace / "opencode.json").read_text())
        self.assertNotIn("browse", opencode["mcp"]["servers"])
        claude = json.loads((self.workspace / ".mcp.json").read_text())
        self.assertNotIn("browse", claude["mcpServers"])
        listing = self.run_fefo("mcp", "list")
        self.assertNotIn("browse", {line.split("\t")[0] for line in listing.stdout.splitlines()})
        launcher = self.workspace / ".opencode/bin/browse-mcp.sh"
        self.assertFalse(launcher.exists())
        doctor = self.run_fefo("doctor")
        self.assertEqual(doctor.returncode, 0, doctor.stdout + doctor.stderr)
        self.assertIn("browse MCP disabled", doctor.stdout)

        path = self.workspace / ".fefo/workspace.json"
        manifest["browse"] = True
        path.write_text(json.dumps(manifest))
        self.assertEqual(self.run_fefo("sync").returncode, 0)
        self.assertTrue(launcher.is_file())
        manifest["browse"] = False
        path.write_text(json.dumps(manifest))
        self.assertEqual(self.run_fefo("sync").returncode, 0)
        self.assertFalse(launcher.exists())

    def test_update_gate_blocks_stale_opencode(self) -> None:
        self.init_workspace()
        latest = self.base / "latest.json"
        latest.write_text('{"version": "99.0.0"}\n')
        env = {
            "FEFO_SKIP_UPDATE_CHECK": "0",
            "FEFO_UPDATE_URL": latest.as_uri(),
            "XDG_CACHE_HOME": str(self.base / "cache"),
        }
        blocked = self.run_fefo_with(env, "sync")
        self.assertEqual(blocked.returncode, 1)
        self.assertIn("older than the latest 99.0.0", blocked.stderr)
        allowed = self.run_fefo_with(env, "status")
        self.assertEqual(allowed.returncode, 0)
        self.assertIn("WARN", allowed.stdout)

    def test_template_sentinel_keeps_bootstrap_docs(self) -> None:
        self.init_workspace()
        agents = (self.workspace / "AGENTS.md").read_text()
        codegraph = (self.workspace / "codegraph/README.md").read_text()
        index = (self.workspace / "docs/vault/00-INDEX.md").read_text()
        (self.workspace / ".fefo/template").write_text("template\n")
        self.assertEqual(self.run_fefo("sync").returncode, 0)
        self.assertEqual(agents, (self.workspace / "AGENTS.md").read_text())
        self.assertEqual(codegraph, (self.workspace / "codegraph/README.md").read_text())
        self.assertEqual(index, (self.workspace / "docs/vault/00-INDEX.md").read_text())

    def init_workspace(self, *extra: str) -> None:
        result = self.run_fefo("init", "--name", "Test", "--repo", "../api", "--no-index", "--yes", *extra)
        self.assertEqual(result.returncode, 0, result.stderr)

    def tree(self) -> dict:
        return {
            str(p.relative_to(self.workspace)): p.read_bytes()
            for p in sorted(self.workspace.rglob("*"))
            if p.is_file() and not p.is_symlink() and ".git" not in p.parts
        }

    def test_force_push_is_denied_after_the_asks(self) -> None:
        self.init_workspace()
        rules = json.loads((self.workspace / "opencode.json").read_text())["permissions"]
        index = {(r["resource"], r["effect"]): i for i, r in enumerate(rules)}
        self.assertLess(index[("git push *", "ask")], index[("git push --force*", "deny")])
        self.assertIn(("*", "ask"), index)  # fefo plugin rule

    def test_provider_model_is_opt_in(self) -> None:
        self.init_workspace("--provider-model", "opencode-go/deepseek-v4.1-flash")
        opencode = json.loads((self.workspace / "opencode.json").read_text())
        self.assertEqual(opencode["model"], "opencode-go/deepseek-v4.1-flash")

    def test_noop_sync_changes_nothing(self) -> None:
        self.init_workspace()
        before = self.tree()
        self.assertEqual(self.run_fefo("sync").returncode, 0)
        self.assertEqual(before, self.tree())
        self.assertEqual(self.run_fefo("sync", "--check").returncode, 0)

    def test_sync_check_reports_drift_and_writes_nothing(self) -> None:
        self.init_workspace()
        (self.workspace / "opencode.json").write_text("{}\n")
        before = self.tree()
        result = self.run_fefo("sync", "--check")
        self.assertEqual(result.returncode, 1)
        self.assertIn("DRIFT opencode.json", result.stdout)
        self.assertEqual(before, self.tree())

    def test_manifest_overrides_survive_sync(self) -> None:
        self.init_workspace()
        path = self.workspace / ".fefo/workspace.json"
        manifest = json.loads(path.read_text())
        manifest["plugins"] = ["opencode-fefo"]
        manifest["opencode"] = {"formatter": True, "permissions": [{"action": "shell", "resource": "rm *", "effect": "deny"}]}
        manifest["claude_settings"] = {"hooks": {"Stop": []}, "permissions": {"ask": ["Bash(npm publish*)"]}}
        path.write_text(json.dumps(manifest))
        self.assertEqual(self.run_fefo("sync").returncode, 0)
        self.assertEqual(self.run_fefo("sync").returncode, 0)
        opencode = json.loads((self.workspace / "opencode.json").read_text())
        self.assertEqual(opencode["plugins"], ["opencode-fefo"])
        self.assertTrue(opencode["formatter"])
        resources = [r["resource"] for r in opencode["permissions"]]
        self.assertIn("git push *", resources)
        self.assertIn("rm *", resources)
        settings = json.loads((self.workspace / ".claude/settings.json").read_text())
        self.assertIn("hooks", settings)
        self.assertIn("Bash(git push *)", settings["permissions"]["ask"])
        self.assertIn("Bash(npm publish*)", settings["permissions"]["ask"])
        self.assertIn("Bash(git push --force*)", settings["permissions"]["deny"])

    def test_read_only_agents_block_edit_and_shell(self) -> None:
        self.init_workspace()
        for agent in ("architect", "security"):
            wrapper = (self.workspace / f".claude/agents/{agent}.md").read_text()
            self.assertIn("disallowedTools: Edit, Write", wrapper)
        doctor = self.run_fefo("doctor")
        self.assertNotIn("can still write through the shell", doctor.stdout)

    def test_doctor_flags_agent_that_denies_edit_but_not_shell(self) -> None:
        self.init_workspace()
        (self.workspace / ".opencode/agents/leaky.md").write_text(
            "---\ndescription: x\nmode: subagent\npermissions:\n"
            "  - effect: deny\n    action: edit\n    resource: \"*\"\n---\nbody\n")
        self.assertIn("leaky.md: denies edit but can still write through the shell", self.run_fefo("doctor").stdout)

    def test_doctor_flags_removed_experimental_key(self) -> None:
        self.init_workspace()
        config = json.loads((self.workspace / "opencode.json").read_text())
        config["experimental"]["background_compaction"] = True
        (self.workspace / "opencode.json").write_text(json.dumps(config))
        self.assertIn("removed experimental keys: background_compaction", self.run_fefo("doctor").stdout)

    def test_adapters_work_without_manifest(self) -> None:
        orchestrator = self.base / "orchestrator"
        (orchestrator / ".opencode/agents").mkdir(parents=True)
        (orchestrator / ".opencode/agents/reviewer.md").write_text(
            "---\ndescription: Reviews\nmode: subagent\npermissions:\n  - { action: edit, resource: \"*\", effect: deny }\n---\nbody\n")
        env = {**os.environ, "FEFO_ROOT": str(orchestrator)}
        run = lambda *a: subprocess.run([str(self.workspace / "bin/fefo"), *a], capture_output=True, text=True, env=env, timeout=30)
        self.assertEqual(run("adapters", "--check").returncode, 1)
        self.assertEqual(run("adapters").returncode, 0)
        self.assertIn("disallowedTools: Edit, Write", (orchestrator / ".claude/agents/reviewer.md").read_text())
        self.assertEqual(run("adapters", "--check").returncode, 0)


class HelpersTest(unittest.TestCase):
    def test_permission_rules_any_key_order_and_flow_style(self) -> None:
        fm = "description: x\npermissions:\n  - effect: deny\n    action: edit\n    resource: \"*\"\n  - { action: shell, resource: \"git diff*\", effect: allow }\n"
        rules = fefo.permission_rules(fm)
        self.assertEqual(len(rules), 2)
        self.assertEqual(fefo.rule_effect(rules, "edit"), "deny")
        self.assertEqual(fefo.blocked_tools(fm), ["Edit", "Write"])

    def test_blanket_shell_deny_blocks_bash(self) -> None:
        fm = "permissions:\n  - action: shell\n    resource: \"*\"\n    effect: deny\n"
        self.assertEqual(fefo.blocked_tools(fm), ["Bash"])

    def test_v1_permission_block_is_not_a_v2_rule(self) -> None:
        self.assertEqual(fefo.permission_rules("permission:\n  edit: deny\n"), [])

    def test_deep_merge_rules(self) -> None:
        merged = fefo.deep_merge(
            {"a": {"x": 1}, "list": [1, 2], "command": ["a", "b"]},
            {"a": {"y": 2}, "list": [2, 3], "command": ["c"]},
        )
        self.assertEqual(merged, {"a": {"x": 1, "y": 2}, "list": [1, 2, 3], "command": ["c"]})

    def test_detects_nest(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            (Path(tmp) / "package.json").write_text(json.dumps({"dependencies": {"@nestjs/core": "11"}}))
            self.assertEqual(fefo.detect_stack(Path(tmp)), "nest")

    def test_version_tuple(self) -> None:
        self.assertEqual(fefo.version_tuple("v2.4.1"), (2, 4, 1))
        self.assertEqual(fefo.version_tuple("2.5.0-beta.1"), (2, 5, 0))
        self.assertEqual(fefo.version_tuple((2, 4, 0)), (2, 4, 0))

    def test_manifest_rejects_non_boolean_browse(self) -> None:
        with self.assertRaises(SystemExit) as error:
            fefo.validate_manifest({"fefo": 1, "name": "Test", "browse": "yes"})
        self.assertIn("'browse' must be a boolean", str(error.exception))

    def test_manifest_rejects_non_boolean_repo_codegraph(self) -> None:
        with self.assertRaises(SystemExit) as error:
            fefo.validate_manifest({
                "fefo": 1, "name": "Test",
                "repos": [{"name": "api", "path": "../api", "role": "api", "stack": "django", "codegraph": 0}],
            })
        self.assertIn("'codegraph' must be a boolean", str(error.exception))


if __name__ == "__main__":
    unittest.main()
