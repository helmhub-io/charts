#!/usr/bin/env python3
"""
Safer HelmHubIO -> HelmHubIO migrator for this charts repo.

Goals:
- Replace image repositories and chart registries:
  * docker.io/helmhubio/*            -> docker.io/helmhubio/*
  * oci://registry-1.docker.io/helmhubiocharts -> oci://registry-1.docker.io/helmhubiocharts
- Update GitHub repo links to the new org:
  * github.com/helmhub-io/charts      -> github.com/helmhub-io/charts
  * /tree|/blob/(main|master)/bitnami/ -> same with helmhubio/
- Update values.yaml image.repository fields from bitnami/<img> -> helmhubio/<img>
- Keep in-container paths (/opt/bitnami, /bitnami) untouched.
- Avoid corrupting YAML by using YAML-aware edits for Chart.yaml and values.yaml.
- Optionally rename the top-level 'bitnami' directory to 'helmhubio'.

Usage:
    python tools/migrate_bitnami_to_helmhubio.py               # dry-run
    python tools/migrate_bitnami_to_helmhubio.py --apply       # apply changes
    python tools/migrate_bitnami_to_helmhubio.py --apply --rename-folders    # also rename top-level bitnami -> helmhubio
    python tools/migrate_bitnami_to_helmhubio.py --apply --rename-all        # rename any file/dir names containing 'bitnami'
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
from pathlib import Path
from typing import Any, Dict, List

try:
    from ruamel.yaml import YAML
except Exception as e:
    print("This script requires 'ruamel.yaml'. Install with: pip install ruamel.yaml", file=sys.stderr)
    raise


ROOT = Path(__file__).resolve().parents[1]


SAFE_TEXT_PATTERNS = [
    # Registry and chart repo changes
    (re.compile(r"oci://registry-1\.docker\.io/bitnamicharts"), "oci://registry-1.docker.io/helmhubiocharts"),
    (re.compile(r"docker\.io/bitnami/"), "docker.io/helmhubio/"),
    (re.compile(r"docker\.io/bitnamilegacy/"), "docker.io/helmhubio/"),
    # GitHub org and paths
    (re.compile(r"github\.com/bitnami/charts"), "github.com/helmhub-io/charts"),
    (re.compile(r"/(tree|blob)/(main|master)/bitnami/"), r"/\1/\2/helmhubio/"),
]


README_BRAND_PATTERNS = [
    # In README-like files, rebrand visible text conservatively
    (re.compile(r"\bBitnami\b"), "HelmHubIO"),
]


def load_yaml(path: Path) -> Any:
    yaml = YAML()
    yaml.preserve_quotes = True
    yaml.width = 4096
    with path.open("r", encoding="utf-8") as f:
        return yaml.load(f)


def dump_yaml(data: Any, path: Path):
    yaml = YAML()
    yaml.preserve_quotes = True
    yaml.width = 4096
    with path.open("w", encoding="utf-8") as f:
        yaml.dump(data, f)


def update_chart_yaml(path: Path) -> bool:
    try:
        data = load_yaml(path)
    except Exception:
        return False
    if not isinstance(data, dict):
        return False
    changed = False

    # annotations.images: list of image refs as strings (or nested structure)
    annotations = data.get("annotations") or {}
    images = annotations.get("images")
    if isinstance(images, list):
        new_images = []
        for item in images:
            if isinstance(item, str):
                new = item.replace("docker.io/helmhubio/", "docker.io/helmhubio/")
                new = new.replace("docker.io/helmhubiolegacy/", "docker.io/helmhubio/")
                if new != item:
                    changed = True
                new_images.append(new)
            else:
                new_images.append(item)
        if new_images != images:
            annotations["images"] = new_images
            data["annotations"] = annotations
    elif isinstance(images, str):
        new_images = images.replace("docker.io/helmhubio/", "docker.io/helmhubio/")
        new_images = new_images.replace("docker.io/helmhubiolegacy/", "docker.io/helmhubio/")
        if new_images != images:
            annotations["images"] = new_images
            data["annotations"] = annotations
            changed = True

    # dependencies[*].repository
    for dep in (data.get("dependencies") or []):
        if isinstance(dep, dict) and isinstance(dep.get("repository"), str):
            repo = dep["repository"]
            new_repo = repo.replace(
                "oci://registry-1.docker.io/helmhubiocharts",
                "oci://registry-1.docker.io/helmhubiocharts",
            )
            if new_repo != repo:
                dep["repository"] = new_repo
                changed = True

    # home and sources
    if isinstance(data.get("home"), str):
        home = data["home"]
        new_home = home
        if "bitnami" in home:
            # Point to HelmHubIO repo if old home referenced bitnami
            new_home = "https://github.com/helmhub-io/charts"
        new_home = new_home.replace("github.com/helmhub-io/charts", "github.com/helmhub-io/charts")
        new_home = re.sub(r"/(tree|blob)/(main|master)/bitnami/", r"/\1/\2/helmhubio/", new_home)
        if new_home != home:
            data["home"] = new_home
            changed = True

    if isinstance(data.get("sources"), list):
        new_sources = []
        for s in data["sources"]:
            if isinstance(s, str):
                s2 = s.replace("github.com/helmhub-io/charts", "github.com/helmhub-io/charts")
                s2 = re.sub(r"/(tree|blob)/(main|master)/bitnami/", r"/\1/\2/helmhubio/", s2)
                if s2 != s:
                    changed = True
                new_sources.append(s2)
            else:
                new_sources.append(s)
        data["sources"] = new_sources

    # maintainers urls
    if isinstance(data.get("maintainers"), list):
        for m in data["maintainers"]:
            if isinstance(m, dict) and isinstance(m.get("url"), str):
                old = m["url"]
                new = old.replace("github.com/helmhub-io/charts", "github.com/helmhub-io/charts")
                if new != old:
                    m["url"] = new
                    changed = True

    # tags list: rename bitnami-* to helmhubio-*
    if isinstance(data.get("tags"), list):
        new_tags = []
        for t in data["tags"]:
            if isinstance(t, str):
                t2 = t.replace("bitnami", "helmhubio")
                if t2 != t:
                    changed = True
                new_tags.append(t2)
            else:
                new_tags.append(t)
        data["tags"] = new_tags

    if changed:
        dump_yaml(data, path)
    return changed


def update_values_yaml(path: Path) -> bool:
    try:
        data = load_yaml(path)
    except Exception:
        return False
    changed = False

    def visit(obj: Any) -> Any:
        nonlocal changed
        if isinstance(obj, dict):
            # Typical structure: image: { registry: docker.io, repository: bitnami/mysql, tag: ... }
            if "image" in obj and isinstance(obj["image"], dict):
                img = obj["image"]
                repo = img.get("repository")
                if isinstance(repo, str):
                    # Replace leading bitnami/ only, keep suffix
                    if repo.startswith("bitnami/"):
                        img["repository"] = "helmhubio/" + repo.split("/", 1)[1]
                        changed = True
                    elif repo.startswith("bitnamilegacy/"):
                        img["repository"] = "helmhubio/" + repo.split("/", 1)[1]
                        changed = True
                    elif repo.startswith("docker.io/helmhubio/"):
                        img["repository"] = repo.replace("docker.io/helmhubio/", "docker.io/helmhubio/")
                        changed = True
                    elif repo.startswith("docker.io/helmhubiolegacy/"):
                        img["repository"] = repo.replace("docker.io/helmhubiolegacy/", "docker.io/helmhubio/")
                        changed = True
            # Recurse
            for k, v in list(obj.items()):
                obj[k] = visit(v)
        elif isinstance(obj, list):
            for i, v in enumerate(obj):
                obj[i] = visit(v)
        return obj

    visit(data)
    if changed:
        dump_yaml(data, path)
    return changed


def update_values_schema_json(path: Path) -> bool:
    try:
        txt = path.read_text(encoding="utf-8")
        data = json.loads(txt)
    except Exception:
        return False
    changed = False

    def visit(obj: Any) -> Any:
        nonlocal changed
        if isinstance(obj, dict):
            # Update default strings inside schema
            for k, v in list(obj.items()):
                if isinstance(v, str):
                    new = v
                    if new.startswith("bitnami/"):
                        new = "helmhubio/" + new.split("/", 1)[1]
                    if new.startswith("bitnamilegacy/"):
                        new = "helmhubio/" + new.split("/", 1)[1]
                    new = new.replace("docker.io/helmhubio/", "docker.io/helmhubio/")
                    new = new.replace("docker.io/helmhubiolegacy/", "docker.io/helmhubio/")
                    if new != v:
                        obj[k] = new
                        changed = True
                else:
                    obj[k] = visit(v)
        elif isinstance(obj, list):
            for i, v in enumerate(obj):
                obj[i] = visit(v)
        return obj

    visit(data)
    if changed:
        path.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    return changed


def safe_text_replace(path: Path, readme_mode: bool = False) -> bool:
    try:
        text = path.read_text(encoding="utf-8")
    except Exception:
        return False
    orig = text

    # Do not touch in-container paths
    # We simply avoid a global 'bitnami' replacement here. Only apply SAFE_TEXT_PATTERNS.
    for rx, repl in SAFE_TEXT_PATTERNS:
        text = rx.sub(repl, text)

    if readme_mode:
        for rx, repl in README_BRAND_PATTERNS:
            text = rx.sub(repl, text)
        # In docs, also rewrite generic repository mentions "bitnami/<repo>" -> "helmhubio/<repo>"
        text = re.sub(r"\bbitnami/([a-z0-9_.-]+)", r"helmhubio/\1", text)

    # In GitHub workflow/action files, aggressively rewrite org/name usages like 'bitnami/xyz' -> 'helmhub-io/xyz'
    if ".github" in str(path):
        text = re.sub(r"\bbitnami/([A-Za-z0-9_.-]+)", r"helmhub-io/\1", text)

    if text != orig:
        path.write_text(text, encoding="utf-8")
        return True
    return False


def rename_top_folder(apply: bool) -> bool:
    src = ROOT / "bitnami"
    dst = ROOT / "helmhubio"
    if not src.exists():
        return False
    if dst.exists():
        return False
    if apply:
        os.rename(src, dst)
    return True


def rename_all_paths(apply: bool) -> int:
    """Rename any directory or file containing 'bitnami' in its name to 'helmhubio'.
    Skips .git, .venv, and hidden top-level control dirs.
    Returns number of renames performed (dry-run prints list).
    """
    skip_dirs = {".git", ".venv", ".github"}  # do not rename .github itself
    renames: List[tuple[Path, Path]] = []
    for root, dirs, files in os.walk(ROOT, topdown=False):
        rpath = Path(root)
        # skip .git and .venv subtrees entirely
        if any(part in skip_dirs for part in rpath.parts):
            continue
        for name in dirs + files:
            if "bitnami" in name:
                src = rpath / name
                dst = rpath / name.replace("bitnami", "helmhubio")
                if src != dst:
                    renames.append((src, dst))
    # sort deepest paths first
    renames.sort(key=lambda p: len(str(p[0])), reverse=True)
    count = 0
    for src, dst in renames:
        if apply:
            dst.parent.mkdir(parents=True, exist_ok=True)
            os.rename(src, dst)
        count += 1
    return count


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--apply", action="store_true", help="Apply changes (default is dry-run)")
    ap.add_argument("--rename-folders", action="store_true", help="Rename top-level 'bitnami' -> 'helmhubio'")
    ap.add_argument("--rename-all", action="store_true", help="Rename any file/dir names containing 'bitnami' -> 'helmhubio'")
    ap.add_argument("--root", default=None, help="Operate on this repo root instead of the script's parent")
    ap.add_argument("--rebrand", action="store_true", help="No-op flag (rebranding is applied by default); accepted for compatibility")
    args = ap.parse_args()

    # Determine the effective ROOT based on --root, if provided
    global ROOT
    if args.root:
        ROOT = Path(args.root).resolve()

    changed_files: List[str] = []

    # Determine which top-level chart dirs exist (pre or post rename)
    top_levels = [d for d in [ROOT/"bitnami", ROOT/"helmhubio"] if d.exists()]

    # 1) YAML-aware updates
    for tl in top_levels:
        for chart_yaml in tl.glob("*/Chart.yaml"):
            if update_chart_yaml(chart_yaml):
                changed_files.append(str(chart_yaml))
        for values_yaml in tl.glob("*/values.yaml"):
            if update_values_yaml(values_yaml):
                changed_files.append(str(values_yaml))
        for schema_json in tl.glob("*/values.schema.json"):
            if update_values_schema_json(schema_json):
                changed_files.append(str(schema_json))

    # 2) Safe text replacement across the whole repo (not only charts), excluding binary/hidden control dirs
    for root, dirs, files in os.walk(ROOT):
        rpath = Path(root)
        if any(part in {".git", ".venv"} for part in rpath.parts):
            continue
        for fname in files:
            path = rpath / fname
            if not path.is_file():
                continue
            # Only process text-like files by extension
            if path.suffix.lower() in {".md", ".tpl", ".txt", ".yaml", ".yml", ".json", ".conf", ""}:
                # Skip YAML we handled structurally (Chart.yaml, values.yaml, values.schema.json) to avoid duplicate writes
                if path.name in {"Chart.yaml", "values.yaml", "values.schema.json"}:
                    continue
                readme_mode = path.suffix.lower() == ".md"
                if safe_text_replace(path, readme_mode=readme_mode):
                    changed_files.append(str(path))

    # 3) Rename top folder (optional)
    renamed = False
    if args.rename_folders:
        renamed = rename_top_folder(apply=args.apply)
    # Optional: rename any other file/dir names containing 'bitnami'
    renamed_count = 0
    if args.rename_all:
        renamed_count = rename_all_paths(apply=args.apply)

    if not args.apply:
        print("Dry-run complete. Files that would change:")
        for f in changed_files:
            print(" -", f)
        if args.rename_folders:
            print(" - [dir] bitnami -> helmhubio" if (ROOT/"bitnami").exists() else " - [dir] (already renamed)")
        sys.exit(0)

    print(f"Applied updates to {len(changed_files)} files.")
    if renamed:
        print("Renamed directory: bitnami -> helmhubio")
    if args.rename_all:
        print(f"Renamed {renamed_count} file/directory names containing 'bitnami'.")


if __name__ == "__main__":
    main()
