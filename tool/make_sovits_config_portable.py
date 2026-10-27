"""Replace stale installation paths in tts_infer.yaml, with a one-time backup.

Use the engine's bundled Python (PyYAML is already installed). The default is a
read-only preview; --apply performs the migration. No model files are modified.
"""

import argparse
import ntpath
import re
import shutil
from pathlib import Path

import yaml


PATH_KEYS = {
    "t2s_weights_path",
    "vits_weights_path",
    "bert_base_path",
    "cnhuhbert_base_path",
}


def portable_path(value, root):
    if not isinstance(value, str) or not ntpath.isabs(value):
        return value

    normalized = value.replace("\\", "/")
    root_prefix = str(root).replace("\\", "/").rstrip("/") + "/"
    if normalized.lower().startswith(root_prefix.lower()):
        relative = normalized[len(root_prefix):]
    else:
        # Recover paths saved before the versioned installation was moved.
        match = re.search(r"/GPT-SoVITS(?:-[^/]+)?/(.+)$", normalized, re.I)
        if not match:
            return value
        relative = match.group(1)

    destination = (root / relative).resolve()
    # Never rebase an external model or a missing file to an unrelated target.
    if not destination.is_relative_to(root.resolve()) or not destination.exists():
        return value
    return destination.relative_to(root.resolve()).as_posix()


def migrate(root, apply=False):
    root = root.resolve()
    config_path = root / "GPT_SoVITS" / "configs" / "tts_infer.yaml"
    original = config_path.read_text(encoding="utf-8-sig")
    config = yaml.safe_load(original)
    changes = []
    for section, settings in config.items():
        if not isinstance(settings, dict):
            continue
        for key in PATH_KEYS:
            old = settings.get(key)
            new = portable_path(old, root)
            if new != old:
                settings[key] = new
                changes.append((section, key, old, new))

    if changes and apply:
        backup = config_path.with_name(config_path.name + ".before-portable.bak")
        if not backup.exists():
            shutil.copy2(config_path, backup)
        # Serialize to a sibling first so a failed write leaves the config intact.
        temporary = config_path.with_name(config_path.name + ".portable.tmp")
        try:
            temporary.write_text(
                yaml.safe_dump(config, allow_unicode=True, sort_keys=False),
                encoding="utf-8",
            )
            temporary.replace(config_path)
        finally:
            if temporary.exists():
                temporary.unlink()
    return changes


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("root", type=Path, help="GPT-SoVITS installation root")
    parser.add_argument("--apply", action="store_true")
    args = parser.parse_args()
    changes = migrate(args.root, apply=args.apply)
    for section, key, old, new in changes:
        print(f"{section}.{key}: {old} -> {new}")
    mode = "Applied" if args.apply else "Preview"
    print(f"{mode}: {len(changes)} path(s).")


if __name__ == "__main__":
    main()
