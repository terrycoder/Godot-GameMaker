import json
import os
import shutil
import subprocess
import sys


def _find_godot() -> str | None:
    configured = os.environ.get("GODOT_EXE", "").strip()
    if configured:
        return configured if os.path.isfile(configured) else None
    for candidate in ("godot", "godot4"):
        resolved = shutil.which(candidate)
        if resolved:
            return resolved
    return None


def main() -> int:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")
    root = os.path.dirname(os.path.abspath(__file__))
    command = sys.argv[1] if len(sys.argv) > 1 else "help"
    godot = _find_godot()
    if godot is None:
        print(json.dumps({
            "ok": False,
            "command": command,
            "code": "cli.godot_not_found",
            "error_zh": "未找到 Godot。请设置 GODOT_EXE，或把 Godot 4.6.2 加入 PATH。",
        }, ensure_ascii=False))
        return 2
    process = subprocess.run(
        [godot, "--headless", "--path", root, "--script", "gm_cli.gd", "--", command],
        cwd=root,
        check=False,
    )
    return process.returncode


if __name__ == "__main__":
    raise SystemExit(main())
