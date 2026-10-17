#!/usr/bin/env python3
"""Kiểm tra kho skill giao diện: mỗi skill chép từ bên thứ ba phải đúng từng byte với bản đã ghim.

    python3 scripts/check_skills.py                       # kiểm tra (CI chạy lệnh này)
    python3 scripts/check_skills.py --update NAME --commit <40 ký tự hex>
                                                          # sau khi CỐ Ý nâng một skill: ghi lại SHA-256 và commit nguồn

`skills/MANIFEST.json` ghi, cho từng skill: nguồn, commit đã ghim, giấy phép và SHA-256 của MỌI file.
Kiểm tra này là việc máy làm được nên không giao cho người đọc diff (xem CLAUDE.md):

  * file nào đổi một byte, thiếu, hoặc thừa so với manifest là lỗi;
  * thư mục dưới `skills/` hay `.claude/skills/` không có trong manifest (và ngược lại) là lỗi;
  * mỗi skill phải có SKILL.md với `name:` trùng tên thư mục, và file giấy phép đi kèm;
  * commit phải là SHA 40 ký tự; nguồn phải là GitHub;
  * `skills/README.md` phải nhắc tên từng skill; không có symlink.

Chỉ dùng thư viện chuẩn. Không có tên file nào được bỏ qua: `__pycache__` hay `.DS_Store` nằm trong một skill cũng là lỗi
(file bị `git add -f` vẫn được `cp -r` sang repo khác). Chạy script của skill ngay trong kho thì xóa `__pycache__` trước khi kiểm.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
JUNK = ("__pycache__", ".DS_Store")
TOP_LEVEL_FILES = ("MANIFEST.json", "README.md")
LICENSE_NAMES = ("LICENSE", "LICENSE.txt", "LICENSE.md")
COMMIT = re.compile(r"^[0-9a-f]{40}$")
SHA256 = re.compile(r"^[0-9a-f]{64}$")
SKILL_PATH = re.compile(r"^(skills|\.claude/skills)/([A-Za-z0-9][A-Za-z0-9._-]*)$")
REQUIRED = ("name", "path", "source", "commit", "license", "files")


def sha256_of(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def tree(directory: Path) -> tuple[list[str], list[str]]:
    """Relative paths of the files under a directory, and of any symlinks (which are never allowed)."""
    files: list[str] = []
    links: list[str] = []
    for current, dirs, names in os.walk(directory):
        here = Path(current)
        for name in list(dirs):
            if (here / name).is_symlink():
                links.append((here / name).relative_to(directory).as_posix())
                dirs.remove(name)
        for name in names:
            path = here / name
            relative = path.relative_to(directory).as_posix()
            (links if path.is_symlink() else files).append(relative)
    return sorted(files), sorted(links)


def junk(relative_paths: list[str]) -> list[str]:
    """Paths that pass through a __pycache__ directory or are a .DS_Store file."""
    return [path for path in relative_paths if any(part in JUNK for part in path.split("/"))]


def frontmatter_name(text: str) -> str | None:
    lines = text.splitlines()
    if not lines or lines[0].strip() != "---":
        return None
    for line in lines[1:]:
        if line.strip() == "---":
            return None
        match = re.match(r"^name:\s*(.+?)\s*$", line)
        if match:
            return match.group(1).strip("'\"")
    return None


def load(root: Path) -> dict:
    return json.loads((root / "skills" / "MANIFEST.json").read_text(encoding="utf-8"))


def check_entry(root: Path, entry: dict, readme: str) -> list[str]:
    problems: list[str] = []
    label = entry.get("name", "?")
    missing = [key for key in REQUIRED if key not in entry]
    if missing:
        return [f"{label}: thiếu trường {', '.join(missing)} trong manifest"]
    match = SKILL_PATH.match(entry["path"])
    if not match or match.group(2) != entry["name"]:
        problems.append(f"{label}: path `{entry['path']}` phải là skills/{label} hoặc .claude/skills/{label}")
        return problems
    if not entry["source"].startswith("https://github.com/"):
        problems.append(f"{label}: nguồn phải là một repo GitHub, không phải `{entry['source']}`")
    if not COMMIT.match(entry["commit"]):
        problems.append(f"{label}: commit `{entry['commit']}` phải là SHA đầy đủ 40 ký tự hex (không dùng nhánh hay tag)")
    if not str(entry["license"]).strip():
        problems.append(f"{label}: thiếu giấy phép")
    for relative, digest in entry["files"].items():
        if not SHA256.match(str(digest)):
            problems.append(f"{label}: SHA-256 của `{relative}` không hợp lệ")
    if f"`{label}`" not in readme:
        problems.append(f"{label}: skills/README.md chưa nhắc tới skill này (đặt tên trong dấu `)")

    directory = root / entry["path"]
    if not directory.is_dir() or directory.is_symlink():
        problems.append(f"{label}: không thấy thư mục {entry['path']}")
        return problems
    actual, links = tree(directory)
    problems += [f"{label}: symlink `{link}` không được phép trong kho" for link in links]
    declared = sorted(entry["files"])
    problems += [f"{label}: file `{name}` có trong manifest nhưng không còn trên đĩa" for name in sorted(set(declared) - set(actual))]
    extra = sorted(set(actual) - set(declared))
    problems += [f"{label}: `{name}` là file rác (__pycache__/.DS_Store): xóa nó, kể cả khi đã được commit" for name in junk(extra)]
    problems += [f"{label}: file `{name}` nằm trong thư mục nhưng không có trong manifest" for name in extra if name not in junk(extra)]
    for name in sorted(set(actual) & set(declared)):
        if sha256_of(directory / name) != entry["files"][name]:
            problems.append(f"{label}: `{name}` khác bản đã ghim (SHA-256 không khớp): file đã bị sửa")
    if not any(name in entry["files"] for name in LICENSE_NAMES):
        problems.append(f"{label}: thiếu file giấy phép ({'/'.join(LICENSE_NAMES)}) trong thư mục skill")
    skill_md = directory / "SKILL.md"
    if "SKILL.md" not in entry["files"] or not skill_md.is_file():
        problems.append(f"{label}: thiếu SKILL.md")
    else:
        found = frontmatter_name(skill_md.read_text(encoding="utf-8"))
        if found != entry["name"]:
            problems.append(f"{label}: `name:` trong SKILL.md là `{found}`, phải trùng tên thư mục `{entry['name']}`")
    return problems


def check(root: Path) -> list[str]:
    try:
        manifest = load(root)
    except (OSError, ValueError) as error:
        return [f"không đọc được skills/MANIFEST.json: {error}"]
    skills = manifest.get("skills")
    if not isinstance(skills, list) or not skills:
        return ["skills/MANIFEST.json phải có danh sách `skills` không rỗng"]
    readme_path = root / "skills" / "README.md"
    readme = readme_path.read_text(encoding="utf-8") if readme_path.is_file() else ""
    problems = [] if readme else ["thiếu skills/README.md"]
    names = [entry.get("name") for entry in skills]
    problems += [f"tên skill `{name}` bị lặp trong manifest" for name in sorted({n for n in names if names.count(n) > 1})]
    for entry in skills:
        problems += check_entry(root, entry, readme)
    listed = {entry.get("path") for entry in skills}
    for base in ("skills", ".claude/skills"):
        directory = root / base
        if not directory.is_dir():
            continue
        for child in sorted(directory.iterdir()):
            if child.is_symlink():
                problems.append(f"{base}/{child.name} là symlink, không được phép trong kho")
            elif child.is_dir():
                if f"{base}/{child.name}" not in listed:
                    problems.append(f"thư mục {base}/{child.name} không có trong manifest: một skill bị gỡ khỏi manifest sẽ không còn được kiểm")
            elif base == "skills" and child.name not in TOP_LEVEL_FILES:
                problems.append(f"file skills/{child.name} không thuộc kho (chỉ có {' và '.join(TOP_LEVEL_FILES)} ở cấp này)")
    return problems


def update(root: Path, name: str, commit: str) -> None:
    manifest = load(root)
    entry = next((item for item in manifest["skills"] if item.get("name") == name), None)
    if entry is None:
        raise SystemExit(f"không có skill `{name}` trong manifest")
    if not COMMIT.match(commit):
        raise SystemExit("--commit phải là SHA đầy đủ 40 ký tự hex")
    directory = root / entry["path"]
    files, links = tree(directory)
    if links:
        raise SystemExit(f"symlink không được phép: {', '.join(links)}")
    if junk(files):
        raise SystemExit(f"xóa file rác trước khi ghi SHA-256: {', '.join(junk(files))}")
    recorded = {relative: sha256_of(directory / relative) for relative in files}
    if entry["files"] and recorded != entry["files"] and commit == entry["commit"]:
        raise SystemExit(
            f"file của `{name}` đã đổi nhưng --commit vẫn là commit đang ghim ({commit[:7]}): "
            "truyền commit upstream của bản mới, để SHA-256 và nguồn không lệch nhau"
        )
    entry["commit"] = commit
    entry["files"] = recorded
    (root / "skills" / "MANIFEST.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Kiểm tra kho skill giao diện đã ghim.")
    parser.add_argument("--update", metavar="NAME", help="ghi lại SHA-256 của skill này sau khi cố ý nâng bản (cần --commit)")
    parser.add_argument("--commit", metavar="SHA", help="commit đầy đủ của nguồn, bản mà các file đang chép (chỉ dùng với --update)")
    args = parser.parse_args(argv)
    if args.commit and not args.update:
        parser.error("--commit chỉ dùng cùng --update")
    if args.update and not args.commit:
        parser.error("--update cần --commit <sha đầy đủ>: manifest phải ghi đúng commit của bản vừa chép")
    if args.update:
        update(ROOT, args.update, args.commit)
        print(f"đã ghi lại SHA-256 và commit của `{args.update}`; xem diff của skills/MANIFEST.json trước khi commit")
        return 0
    problems = check(ROOT)
    if problems:
        print("\n".join(f"LỖI  {problem}" for problem in problems), file=sys.stderr)
        print(f"check_skills: {len(problems)} lỗi", file=sys.stderr)
        return 1
    manifest = load(ROOT)
    total = sum(len(entry["files"]) for entry in manifest["skills"])
    print(f"check_skills: OK, {len(manifest['skills'])} skill, {total} file khớp bản đã ghim")
    return 0


if __name__ == "__main__":
    sys.exit(main())
