from __future__ import annotations

import argparse
import os
import shutil
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
VENDOR = ROOT / "vendor"
REPO = VENDOR / "Grounded-SAM-2"
COMMIT = "b7a9c29f196edff0eb54dbe14588d7ae5e3dde28"
REMOTE = "https://github.com/IDEA-Research/Grounded-SAM-2.git"


def run(command: list[str], cwd: Path | None = None) -> None:
    print("+", " ".join(command), flush=True)
    subprocess.run(command, cwd=cwd, check=True)


def ensure_grounded_sam(download_checkpoints: bool) -> None:
    VENDOR.mkdir(parents=True, exist_ok=True)
    if not REPO.exists():
        run(["git", "clone", REMOTE, str(REPO)])
    run(["git", "fetch", "--depth", "1", "origin", COMMIT], cwd=REPO)
    run(["git", "checkout", "--detach", COMMIT], cwd=REPO)
    run([sys.executable, "-m", "pip", "install", "-e", "."], cwd=REPO)
    run(
        [sys.executable, "-m", "pip", "install", "--no-build-isolation", "-e", "grounding_dino"],
        cwd=REPO,
    )
    if not download_checkpoints:
        return
    bash = shutil.which("bash")
    if bash is None:
        raise RuntimeError("bash is required for the official checkpoint scripts; use WSL or Docker")
    run([bash, "download_ckpts.sh"], cwd=REPO / "checkpoints")
    run([bash, "download_ckpts.sh"], cwd=REPO / "gdino_checkpoints")


def prefetch_huggingface(include_qwen: bool) -> None:
    from huggingface_hub import snapshot_download

    snapshot_download(
        repo_id="Marqo/marqo-fashionSigLIP",
        revision="c56244cc94f92419e8369fa71efdaf403b124ce8",
    )
    if include_qwen:
        snapshot_download(
            repo_id="Qwen/Qwen3-VL-4B-Instruct",
            revision="ebb281ec70b05090aa6165b016eac8ec08e71b17",
        )
        snapshot_download(
            repo_id="Qwen/Qwen3-VL-2B-Instruct",
            revision="89644892e4d85e24eaac8bacfd4f463576704203",
        )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--download-checkpoints", action="store_true")
    parser.add_argument("--prefetch-huggingface", action="store_true")
    parser.add_argument("--include-qwen", action="store_true")
    args = parser.parse_args()
    os.chdir(ROOT)
    ensure_grounded_sam(args.download_checkpoints)
    if args.prefetch_huggingface:
        prefetch_huggingface(args.include_qwen)


if __name__ == "__main__":
    main()
