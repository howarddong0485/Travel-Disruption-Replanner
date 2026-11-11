"""Jac 0.37.23 sealing compatibility: resolve staged imports in the staged tree.

The upstream sealer launches its precompiler with the original checkout as cwd.
That lets copied modules resolve some class identities against the old paths.
Only the child working directory is corrected here; all compiler checks and
the normal sealed manifest/finalization remain enabled. No runtime file changes.
"""
import os;
import sys;
import from pathlib { Path }
import from contextlib { chdir }
import from importlib { import_module }
import from importlib.metadata { version }

with entry {
    if version("jaclang") != "0.37.23" {
        raise RuntimeError("Review the sealing compatibility shim before changing Jac versions");
    }
    project_dir = Path(__file__).resolve().parent.parent / "travel-planner";
    os.chdir(project_dir);
    config = import_module("jaclang.project.config");
    config.get_config(start_path=project_dir, force_discover=True);
    sealing = import_module("jaclang.dist.seal");
    original = sealing.run_precompiler;
    def staged_precompiler(stage: str, flags: list[str]) -> int {
        with chdir(stage) { return original(stage, flags); }
    }
    sealing.run_precompiler = staged_precompiler;
    project = import_module("jaclang.cli.commands.project");
    output = str(Path(os.environ.get("ROAM_BUILD_OUTPUT", "../.ci/artifacts")).resolve());
    sys.exit(project.bundle(output=output, target="jab", fat=False, app="travel"));
}
