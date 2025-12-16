import argparse
import os
from pathlib import Path
import sys
import zipfile
import importlib
import io
from contextlib import redirect_stdout, redirect_stderr


def parse_runtime(fmt: str):
    s = fmt.strip().lower()
    if s in ("onnx", "onnxruntime"):
        return "onnx"
    if s in ("tflite", "litert"):
        return "tflite"
    if s in ("qnn_dlc", "dlc"):
        return "qnn_dlc"
    if s in ("qnn_context_binary", "context_binary", "bin"):
        return "qnn_context_binary"
    if s in ("precompiled_qnn_onnx", "precompiled_onnx"):
        return "precompiled_qnn_onnx"
    if s in ("genie",):
        return "genie"
    if s in ("onnxruntime_genai", "genai"):
        return "onnxruntime_genai"
    raise ValueError(f"Unsupported format: {fmt}")


def ensure_dir(path: Path) -> None:
    path.mkdir(parents=True, exist_ok=True)


def extract_zip_to_folder(zip_path: Path, out_dir: Path) -> list[Path]:
    ensure_dir(out_dir)
    with zipfile.ZipFile(zip_path, "r") as zf:
        zf.extractall(out_dir)
        return [out_dir / n for n in zf.namelist()]


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Get model file by name and format. Supports local override.",
        add_help=False,
    )
    parser.add_argument("--model", required=False, help="Model name (folder id)")
    parser.add_argument(
        "--format",
        required=False,
        help="Desired output format (e.g., onnx, tflite, qnn_dlc, qnn_context_binary)",
    )
    parser.add_argument(
        "--local-path",
        default=None,
        help="Local model file path to use directly",
    )
    parser.add_argument(
        "--output-dir",
        default=None,
        help="Directory to store downloaded/extracted assets",
    )
    parser.add_argument(
        "--unzip",
        action="store_true",
        help="If the downloaded asset is a .zip, extract and return extracted paths",
    )
    parser.add_argument(
        "--repo-dir",
        default=None,
        help="Path to ai-hub-models repo; no auto-download; uses AIHM_REPO_DIR if unset",
    )
    parser.add_argument("-h", "--help", action="store_true", help="Show help")

    args = parser.parse_args()

    if args.help:
        if args.model:
            model_id = args.model.strip()
            try:
                env_dir = os.environ.get("AIHM_REPO_DIR")
                repo_root = Path(args.repo_dir).expanduser() if args.repo_dir else (Path(env_dir).expanduser() if env_dir else None)
                if repo_root is None:
                    raise RuntimeError("Repository path required. Provide --repo-dir or set AIHM_REPO_DIR.")
                sys.path.append(str(repo_root))
                export_mod = importlib.import_module(
                    f"qai_hub_models.models.{model_id}.export"
                )
                old_argv = sys.argv[:]
                sys.argv = ["export.py", "--help"]
                buf_out = io.StringIO()
                buf_err = io.StringIO()
                try:
                    with redirect_stdout(buf_out), redirect_stderr(buf_err):
                        export_mod.main()
                except SystemExit:
                    pass
                finally:
                    sys.argv = old_argv
                help_txt = buf_out.getvalue() + buf_err.getvalue()
                print(help_txt.strip())
            except Exception as e:
                env_dir = os.environ.get("AIHM_REPO_DIR")
                base = Path(args.repo_dir).expanduser() if args.repo_dir else (Path(env_dir).expanduser() if env_dir else None)
                if base is None:
                    raise RuntimeError("Repository path required. Provide --repo-dir or set AIHM_REPO_DIR.")
                export_path = base / "qai_hub_models" / "models" / model_id / "export.py"
                print(
                    f"Unable to load model export help ({e}).\n"
                    f"Run: python {export_path} --help",
                    file=sys.stderr,
                )
            return
        else:
            print(
                "Usage: python scripts/get_model_file.py --model <name> --format <fmt> [--local-path PATH] [--output-dir DIR] [--unzip]\n"
                "When --model is provided with --help, prints that model's export.py --help."
            )
            return

    if not args.model or not args.format:
        print("--model and --format are required unless using --help", file=sys.stderr)
        sys.exit(2)

    model_id = args.model.strip()
    runtime = parse_runtime(args.format)

    if args.local_path:
        p = Path(args.local_path).expanduser()
        if not p.exists():
            print(f"Local path does not exist: {p}", file=sys.stderr)
            sys.exit(1)
        print(str(p))
        return

    out_dir = (
        Path(args.output_dir).expanduser()
        if args.output_dir
        else Path.cwd() / "build" / model_id / runtime
    )
    ensure_dir(out_dir)

    env_dir = os.environ.get("AIHM_REPO_DIR")
    repo_root = Path(args.repo_dir).expanduser() if args.repo_dir else (Path(env_dir).expanduser() if env_dir else None)
    if repo_root is None:
        print("Repository path required. Provide --repo-dir or set AIHM_REPO_DIR.", file=sys.stderr)
        sys.exit(2)
    sys.path.append(str(repo_root))
    from qai_hub_models.models.common import TargetRuntime, Precision
    from qai_hub_models.utils.fetch_static_assets import fetch_static_assets

    rt_enum = TargetRuntime[runtime.upper()] if hasattr(TargetRuntime, runtime.upper()) else None
    if rt_enum is None:
        mapping = {
            "onnx": TargetRuntime.ONNX,
            "tflite": TargetRuntime.TFLITE,
            "qnn_dlc": TargetRuntime.QNN_DLC,
            "qnn_context_binary": TargetRuntime.QNN_CONTEXT_BINARY,
            "precompiled_qnn_onnx": TargetRuntime.PRECOMPILED_QNN_ONNX,
            "genie": TargetRuntime.GENIE,
            "onnxruntime_genai": TargetRuntime.ONNXRUNTIME_GENAI,
        }
        rt_enum = mapping[runtime]

    paths, _ = fetch_static_assets(
        model_id=model_id,
        runtime=rt_enum,
        precision=Precision.float,
        device=None,
        components=None,
        qaihm_version_tag=None,
        output_folder=str(out_dir),
    )

    if not paths:
        print("No assets found", file=sys.stderr)
        sys.exit(2)

    emitted: list[Path] = []
    for p in paths:
        path = Path(p)
        if args.unzip and path.suffix == ".zip":
            extracted_dir = out_dir / path.stem
            extracted = extract_zip_to_folder(path, extracted_dir)
            emitted.extend(extracted)
        else:
            emitted.append(path)

    for e in emitted:
        print(str(e))


if __name__ == "__main__":
    main()
