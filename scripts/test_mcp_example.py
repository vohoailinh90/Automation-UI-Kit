"""Test cho các bản mẫu MCP (.claude/mcp/*.example.json), quy tắc chặn trong .claude/settings.json và docs/mcp.md.

Chỉ kiểm cái máy kiểm được: phiên bản ghim, cờ an toàn, quy tắc chặn còn khớp tên server, không có bí mật,
tài liệu không lệch với bản mẫu. Server có chạy được hay không thì phải thử tay (docs/mcp.md ghi đã thử gì).

    python3 -m unittest discover -s scripts -p "test_*.py"
"""

from __future__ import annotations

import json
import re
import shutil
import subprocess
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
EXAMPLES = ROOT / ".claude" / "mcp"
SETTINGS = ROOT / ".claude" / "settings.json"
DOC = ROOT / "docs" / "mcp.md"

UNSAFE_TOOL = "browser_run_code_unsafe"
PIN = re.compile(r"^@playwright/mcp@\d+\.\d+\.\d+$")
# A header value may hold an environment placeholder and nothing else: never a literal key.
PLACEHOLDER = re.compile(r"^(?:Bearer )?\$\{[A-Z][A-Z0-9_]*(?::-)?\}$")
# Key-shaped text anywhere in what this change ships (prose and shell blocks too, not only JSON): a Context7 key,
# a generic `sk-` key, a bearer token that is not an ${ENV} placeholder, or `SOMETHING_API_KEY=<value>`.
SECRET_LIKE = re.compile(
    r"ctx7[a-z]*-[A-Za-z0-9-]{6,}"
    r"|\bsk-[A-Za-z0-9_-]{16,}"
    r"|Bearer\s+(?!\$\{)[A-Za-z0-9._-]{16,}"
    r"|_API_KEY\s*[=:]\s*[\"']?(?!\$\{)[A-Za-z0-9._-]{12,}"
)


def load(name: str) -> dict:
    return json.loads((EXAMPLES / name).read_text(encoding="utf-8"))


def doc_text() -> str:
    return DOC.read_text(encoding="utf-8")


def doc_configs() -> list[dict]:
    """Every ```json block of the doc that is (or, as a bare `"key": value` fragment, can be wrapped into) an object."""
    configs = []
    for block in re.findall(r"```json\n(.*?)```", doc_text(), re.S):
        for candidate in (block, "{" + block + "}"):
            try:
                configs.append(json.loads(candidate))
                break
            except ValueError:
                continue
    return configs


def servers_in(config: dict) -> dict:
    return config.get("mcpServers", {})


def headers_everywhere() -> list[tuple[str, str]]:
    found = []
    for source, config in [(path.name, json.loads(path.read_text(encoding="utf-8"))) for path in sorted(EXAMPLES.glob("*.json"))] + [
        ("docs/mcp.md", config) for config in doc_configs()
    ]:
        for server in servers_in(config).values():
            found += [(source, value) for value in server.get("headers", {}).values()]
    return found


class PlaywrightExampleTests(unittest.TestCase):
    def setUp(self):
        self.config = load("playwright.example.json")
        self.server = self.config["mcpServers"]["playwright"]

    def test_it_defines_exactly_one_server_named_playwright(self):
        # The deny rule below is written against this key.
        self.assertEqual(list(self.config["mcpServers"]), ["playwright"])

    def test_it_runs_through_npx_with_an_exact_version(self):
        # `npx` fetches and runs the package every session: @latest or a range would run code nobody reviewed.
        self.assertEqual(self.server["command"], "npx")
        self.assertRegex(self.server["args"][0], PIN)

    def test_the_safety_flags_are_exactly_these_three(self):
        self.assertEqual(self.server["args"][1:], ["--headless", "--isolated", "--no-webmcp"])

    def test_the_example_carries_no_sandbox_path_or_environment_override(self):
        self.assertNotIn("--no-sandbox", self.server["args"])
        self.assertFalse([arg for arg in self.server["args"] if arg.startswith("--executable-path")])
        self.assertNotIn("env", self.server)

    def test_every_version_in_the_doc_is_the_pinned_one(self):
        pinned = self.server["args"][0]
        mentioned = set(re.findall(r"@playwright/mcp@[0-9][0-9.]*", doc_text()))
        self.assertEqual(mentioned, {pinned})

    def test_every_install_command_in_the_doc_names_the_pinned_version(self):
        # Without a version, npx would fetch whatever is latest to install a browser revision the pin does not expect.
        self.assertIsNone(re.search(r"npx @playwright/mcp(?!@\d)", doc_text()))

    def test_the_container_recipe_is_the_example_plus_a_browser_path_and_no_sandbox(self):
        recipes = [
            config["args"] for config in doc_configs() if "--executable-path" in config.get("args", [])
        ]
        self.assertEqual(len(recipes), 1)
        recipe = recipes[0]
        self.assertEqual(recipe[: len(self.server["args"])], self.server["args"])
        self.assertIn("--no-sandbox", recipe)
        self.assertTrue(recipe[recipe.index("--executable-path") + 1].startswith("/opt/pw-browsers/"))


class DenyRuleTests(unittest.TestCase):
    def setUp(self):
        self.settings = json.loads(SETTINGS.read_text(encoding="utf-8"))
        self.key = next(iter(load("playwright.example.json")["mcpServers"]))
        self.rule = f"mcp__{self.key}__{UNSAFE_TOOL}"

    def test_the_unsafe_tool_is_denied(self):
        self.assertIn(self.rule, self.settings["permissions"]["deny"])

    def test_the_rule_names_the_server_key_the_example_really_uses(self):
        # Rename the key in the example and the rule stops matching any tool, silently.
        self.assertEqual(self.rule, "mcp__playwright__browser_run_code_unsafe")

    def test_the_settings_file_enables_no_server_and_allows_no_mcp_tool(self):
        # The servers are opt-in: committed settings must not switch them on for everyone.
        for forbidden in ("mcpServers", "enableAllProjectMcpServers", "enabledMcpjsonServers"):
            self.assertNotIn(forbidden, self.settings)
        allowed = self.settings.get("permissions", {}).get("allow", [])
        self.assertFalse([rule for rule in allowed if rule.startswith("mcp__")])

    def test_the_doc_names_the_rule_before_it_tells_you_to_enable_the_server(self):
        text = doc_text()
        self.assertIn(self.rule, text)
        self.assertLess(text.index(self.rule), text.index("cp .claude/mcp/playwright.example.json .mcp.json"))


class Context7ExampleTests(unittest.TestCase):
    def setUp(self):
        self.config = load("context7.example.json")
        self.server = self.config["mcpServers"]["context7"]

    def test_it_defines_exactly_one_server_named_context7(self):
        self.assertEqual(list(self.config["mcpServers"]), ["context7"])

    def test_it_is_the_plain_remote_url_and_nothing_else(self):
        # No key, no environment, no query string: authentication is the sign-in flow described in docs/mcp.md.
        self.assertEqual(self.server, {"type": "http", "url": "https://mcp.context7.com/mcp"})

    def test_no_header_anywhere_holds_a_literal_secret(self):
        headers = headers_everywhere()
        self.assertTrue(headers, "the doc is expected to show one header variant")
        for source, value in headers:
            self.assertRegex(value, PLACEHOLDER, f"{source}: a header value must be an environment placeholder")

    def test_the_documented_key_variant_reads_the_key_from_the_environment(self):
        variants = [
            servers_in(config)["context7"]
            for config in doc_configs()
            if "headers" in servers_in(config).get("context7", {})
        ]
        self.assertEqual(len(variants), 1)
        self.assertEqual(variants[0]["url"], self.server["url"])
        self.assertEqual(variants[0]["headers"], {"Authorization": "Bearer ${CONTEXT7_API_KEY:-}"})

    def test_no_key_shaped_text_in_the_doc_or_the_files_under_claude_mcp(self):
        shipped = [DOC, SETTINGS, *sorted(EXAMPLES.rglob("*"))]
        for path in shipped:
            if path.is_file():
                text = path.read_text(encoding="utf-8")
                found = SECRET_LIKE.search(text)
                self.assertIsNone(found, f"{path.relative_to(ROOT)} holds key-shaped text: {found and found.group(0)!r}")

    def test_the_doc_says_queries_leave_the_machine_and_that_sign_in_was_not_run(self):
        text = " ".join(doc_text().split()).lower()
        for phrase in ("rời máy bạn", "chưa từng chạy thật", "chưa chạy thử ở đây", "không được che"):
            self.assertTrue(phrase in text, f"docs/mcp.md must still say \"{phrase}\"")


class HygieneTests(unittest.TestCase):
    def test_gitignore_keeps_the_local_config_and_the_server_output_out_of_commits(self):
        lines = (ROOT / ".gitignore").read_text(encoding="utf-8").splitlines()
        self.assertIn("/.mcp.json", lines)
        self.assertIn("/.playwright-mcp/", lines)

    @unittest.skipUnless(shutil.which("git") and (ROOT / ".git").exists(), "needs a git checkout")
    def test_neither_is_tracked(self):
        tracked = subprocess.run(
            ["git", "ls-files", "--", ".mcp.json", ".playwright-mcp"], cwd=ROOT, capture_output=True, text=True, check=True
        ).stdout
        self.assertEqual(tracked.strip(), "")

    def test_the_doc_uses_the_port_playwright_config_uses(self):
        port = re.search(r"const PORT = (\d+)", (ROOT / "playwright.config.ts").read_text(encoding="utf-8")).group(1)
        text = doc_text()
        self.assertIn(f"http://localhost:{port}", text)
        self.assertIn(f"npm run dev -- --port {port}", text)

    def test_the_doc_states_the_prerequisites(self):
        text = doc_text()
        self.assertIn("Node.js 18", text)
        self.assertIn("npx", text)

    def test_every_path_the_doc_names_exists(self):
        paths = set(re.findall(r"`((?:\.claude|scripts|docs|e2e)/[\w./-]*)`", doc_text()))
        self.assertTrue(paths)
        for name in sorted(paths):
            self.assertTrue((ROOT / name).exists(), f"docs/mcp.md names `{name}`, which does not exist")

    def test_the_readme_points_at_the_doc(self):
        self.assertIn("docs/mcp.md", (ROOT / "README.md").read_text(encoding="utf-8"))


if __name__ == "__main__":
    unittest.main()
