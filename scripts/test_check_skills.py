"""Test cho scripts/check_skills.py: cổng giữ cho bản chép skill đúng từng byte so với bản đã ghim.

    python3 -m unittest discover -s scripts -p "test_*.py"
"""

from __future__ import annotations

import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import check_skills  # noqa: E402

COMMIT = "a" * 40
SKILL_MD = "---\nname: alpha\ndescription: demo\n---\n\n# Alpha\n"


def write(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")


def make_repo(root: Path) -> None:
    """A repo with one vendored skill (skills/alpha) and one active skill (.claude/skills/beta)."""
    write(root / "skills" / "README.md", "# Kho\n\n`alpha` và `beta`\n")
    write(root / "skills" / "alpha" / "SKILL.md", SKILL_MD)
    write(root / "skills" / "alpha" / "LICENSE", "MIT\n")
    write(root / "skills" / "alpha" / "data" / "x.csv", "a,b\n1,2\n")
    write(root / ".claude" / "skills" / "beta" / "SKILL.md", SKILL_MD.replace("alpha", "beta"))
    write(root / ".claude" / "skills" / "beta" / "LICENSE.txt", "Apache\n")
    entries = [
        {"name": "alpha", "path": "skills/alpha", "source": "https://github.com/o/alpha", "commit": COMMIT,
         "license": "MIT", "files": {}},
        {"name": "beta", "path": ".claude/skills/beta", "source": "https://github.com/o/beta", "commit": COMMIT,
         "license": "Apache-2.0", "files": {}},
    ]
    write(root / "skills" / "MANIFEST.json", json.dumps({"skills": entries}))
    check_skills.update(root, "alpha", None)
    check_skills.update(root, "beta", None)


class CheckSkillsTests(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmp.cleanup)
        self.root = Path(self._tmp.name)
        make_repo(self.root)

    def problems(self) -> list[str]:
        return check_skills.check(self.root)

    def assert_problem(self, fragment: str) -> None:
        found = self.problems()
        self.assertTrue(any(fragment in problem for problem in found), f"{fragment!r} not in {found}")

    def edit_manifest(self, change) -> None:
        manifest = check_skills.load(self.root)
        change(manifest)
        write(self.root / "skills" / "MANIFEST.json", json.dumps(manifest))

    def test_a_pinned_tree_passes(self):
        self.assertEqual(self.problems(), [])

    def test_one_changed_byte_fails(self):
        write(self.root / "skills" / "alpha" / "data" / "x.csv", "a,b\n1,3\n")
        self.assert_problem("SHA-256 không khớp")

    def test_a_changed_byte_in_the_active_skill_fails_too(self):
        write(self.root / ".claude" / "skills" / "beta" / "LICENSE.txt", "Apache!\n")
        self.assert_problem("beta: `LICENSE.txt` khác bản đã ghim")

    def test_an_extra_file_fails(self):
        write(self.root / "skills" / "alpha" / "extra.md", "x")
        self.assert_problem("không có trong manifest")

    def test_a_missing_file_fails(self):
        (self.root / "skills" / "alpha" / "data" / "x.csv").unlink()
        self.assert_problem("không còn trên đĩa")

    def test_a_directory_missing_from_the_manifest_fails(self):
        write(self.root / "skills" / "gamma" / "SKILL.md", SKILL_MD.replace("alpha", "gamma"))
        self.assert_problem("skills/gamma không có trong manifest")

    def test_a_manifest_skill_without_a_directory_fails(self):
        for path in sorted((self.root / "skills" / "alpha").rglob("*"), reverse=True):
            path.unlink() if path.is_file() else path.rmdir()
        (self.root / "skills" / "alpha").rmdir()
        self.assert_problem("không thấy thư mục skills/alpha")

    def test_the_commit_must_be_a_full_sha(self):
        self.edit_manifest(lambda m: m["skills"][0].__setitem__("commit", "main"))
        self.assert_problem("SHA đầy đủ 40 ký tự")
        self.edit_manifest(lambda m: m["skills"][0].__setitem__("commit", "abc1234"))
        self.assert_problem("SHA đầy đủ 40 ký tự")

    def test_the_source_must_be_github(self):
        self.edit_manifest(lambda m: m["skills"][0].__setitem__("source", "https://example.com/alpha"))
        self.assert_problem("repo GitHub")

    def test_the_skill_name_must_match_the_directory(self):
        write(self.root / "skills" / "alpha" / "SKILL.md", SKILL_MD.replace("name: alpha", "name: other"))
        check_skills.update(self.root, "alpha", None)
        self.assert_problem("phải trùng tên thư mục")

    def test_a_license_file_is_required(self):
        (self.root / "skills" / "alpha" / "LICENSE").unlink()
        check_skills.update(self.root, "alpha", None)
        self.assert_problem("thiếu file giấy phép")

    def test_the_readme_must_name_every_skill(self):
        write(self.root / "skills" / "README.md", "# Kho\n\nchỉ `alpha`\n")
        self.assert_problem("beta: skills/README.md chưa nhắc tới")

    def test_a_missing_readme_fails(self):
        (self.root / "skills" / "README.md").unlink()
        self.assert_problem("thiếu skills/README.md")

    def test_a_symlink_fails(self):
        (self.root / "skills" / "alpha" / "link.md").symlink_to(self.root / "skills" / "alpha" / "SKILL.md")
        self.assert_problem("symlink `link.md`")

    def test_a_duplicate_name_fails(self):
        self.edit_manifest(lambda m: m["skills"].append(dict(m["skills"][0])))
        self.assert_problem("bị lặp")

    def test_a_skill_path_outside_the_allowed_places_fails(self):
        self.edit_manifest(lambda m: m["skills"][0].__setitem__("path", "../elsewhere/alpha"))
        self.assert_problem("phải là skills/alpha")

    def test_a_pycache_file_is_not_hidden(self):
        # git add -f would commit it, and cp -r would carry it to another repo: the gate must see it.
        write(self.root / "skills" / "alpha" / "__pycache__" / "m.pyc", "x")
        self.assert_problem("__pycache__/m.pyc` là file rác")

    def test_a_ds_store_file_is_not_hidden(self):
        write(self.root / "skills" / "alpha" / "data" / ".DS_Store", "x")
        self.assert_problem("data/.DS_Store` là file rác")

    def test_junk_in_the_active_skill_is_not_hidden_either(self):
        write(self.root / ".claude" / "skills" / "beta" / "__pycache__" / "m.pyc", "x")
        self.assert_problem("beta: `__pycache__/m.pyc` là file rác")

    def test_update_refuses_to_record_junk(self):
        # Otherwise running a vendored script and then --update would hash its __pycache__ into the manifest.
        write(self.root / "skills" / "alpha" / "__pycache__" / "m.pyc", "x")
        with self.assertRaises(SystemExit):
            check_skills.update(self.root, "alpha", None)
        self.assertNotIn("__pycache__/m.pyc", check_skills.load(self.root)["skills"][0]["files"])

    def test_a_stray_file_directly_under_skills_fails(self):
        write(self.root / "skills" / "notes.txt", "x")
        self.assert_problem("file skills/notes.txt không thuộc kho")

    def test_a_symlinked_skill_directory_fails(self):
        (self.root / "skills" / "linked").symlink_to(self.root / "skills" / "alpha", target_is_directory=True)
        self.assert_problem("skills/linked là symlink")

    def test_update_records_new_bytes_and_the_new_commit(self):
        write(self.root / "skills" / "alpha" / "data" / "x.csv", "a,b\n9,9\n")
        self.assert_problem("SHA-256 không khớp")
        check_skills.update(self.root, "alpha", "b" * 40)
        self.assertEqual(self.problems(), [])
        self.assertEqual(check_skills.load(self.root)["skills"][0]["commit"], "b" * 40)

    def test_update_refuses_a_short_commit_and_an_unknown_skill(self):
        with self.assertRaises(SystemExit):
            check_skills.update(self.root, "alpha", "abc")
        with self.assertRaises(SystemExit):
            check_skills.update(self.root, "nope", None)

    def test_an_unreadable_manifest_is_reported_not_raised(self):
        write(self.root / "skills" / "MANIFEST.json", "{not json")
        self.assert_problem("không đọc được")

    def test_the_real_repository_passes(self):
        # The same check CI runs, so a broken manifest also shows up as a failing unit test.
        self.assertEqual(check_skills.check(check_skills.ROOT), [])


if __name__ == "__main__":
    unittest.main()
