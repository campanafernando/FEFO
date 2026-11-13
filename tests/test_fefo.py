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
        self.tmp.cleanup()

    def make_repo(self, name: str, stack: str) -> Path:
        path = self.base / name
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

        opencode = json.loads((self.workspace / "opencode.json").read_text())
        self.assertEqual(set(opencode["mcp"]["servers"]), {"codegraph-api", "codegraph-web"})
        self.assertEqual(opencode["default_agent"], "fefo")
        self.assertNotIn("model", opencode, "no model is pinned unless the manifest asks for one")

        claude = json.loads((self.workspace / ".mcp.json").read_text())
        self.assertEqual(set(claude["mcpServers"]), {"codegraph-api", "codegraph-web"})

        self.assertTrue((self.workspace / ".claude/agents/fefo.md").is_file())
        self.assertTrue((self.workspace / ".claude/skills/codegraph").is_symlink())
        self.assertTrue((self.workspace / "CLAUDE.md").is_file())
        self.assertTrue((self.workspace / ".cursor/rules/fefo.mdc").is_file())
        self.assertTrue((self.workspace / ".github/copilot-instructions.md").is_file())
        self.assertTrue((self.workspace / "docs/vault/repos/api.md").is_file())
        self.assertIn("codegraph-api", (self.workspace / "AGENTS.md").read_text())

        doctor = self.run_fefo("doctor")
        self.assertEqual(doctor.returncode, 0, doctor.stdout + doctor.stderr)

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


if __name__ == "__main__":
    unittest.main()
