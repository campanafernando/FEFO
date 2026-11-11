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
        self.assertEqual(opencode["model"], "opencode-go/deepseek-v4.1-flash")

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


if __name__ == "__main__":
    unittest.main()
