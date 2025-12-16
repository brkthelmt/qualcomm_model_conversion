import argparse
import os
import subprocess
from pathlib import Path
import ast

def runtime_cli_token(name: str) -> str:
    m = {
        "TFLITE": "tflite",
        "ONNX": "onnx",
        "QNN_DLC": "qnn_dlc",
        "QNN_CONTEXT_BINARY": "qnn_context_binary",
        "PRECOMPILED_QNN_ONNX": "precompiled_qnn_onnx",
        "GENIE": "genie",
        "ONNXRUNTIME_GENAI": "onnxruntime_genai",
    }
    return m.get(name.strip(), name.strip().lower())

def supports_precision(runtime_name: str, precision_name: str) -> bool:
    if precision_name == "float":
        return True
    if runtime_name == "TFLITE":
        return precision_name == "w8a8"
    if runtime_name in {"ONNX"}:
        return precision_name in {"w8a8", "w8a16", "w16a16", "w4a16", "w4"}
    if runtime_name in {"QNN_DLC", "QNN_CONTEXT_BINARY", "PRECOMPILED_QNN_ONNX"}:
        return precision_name in {"w8a8", "w8a16", "w16a16", "w4a16", "w4"}
    if runtime_name in {"GENIE", "ONNXRUNTIME_GENAI"}:
        return precision_name in {"w4a16", "w4", "float"}
    return True

def detect_restrictions(model_dir: Path):
    text = ""
    for p in [model_dir / "model.py", model_dir / "export.py", model_dir / "evaluate.py"]:
        if p.exists():
            try:
                text += p.read_text(encoding="utf-8") + "\n"
            except Exception:
                pass
    restrictions = {
        "only_precisions": None,
        "only_runtimes": None,
        "onnx_only": False,
        "genai_only": False,
    }
    if "Only w8a16 precision is supported" in text:
        restrictions["only_precisions"] = {"w8a16"}
    if "Only w4a16 and w4 precisions are supported" in text:
        restrictions["only_precisions"] = {"w4a16", "w4"}
    if "Only Generative AI runtimes" in text or "is_exclusively_for_genai" in text:
        restrictions["genai_only"] = True
        restrictions["only_runtimes"] = {"GENIE", "ONNXRUNTIME_GENAI"}
    if "target_runtime != TargetRuntime.ONNX" in text:
        restrictions["onnx_only"] = True
        restrictions["only_runtimes"] = {"ONNX"}
    return restrictions

def apply_model_restrictions(runtimes: list[str], precision: str, restrictions: dict):
    if restrictions.get("only_precisions") is not None and precision not in restrictions["only_precisions"]:
        return []
    if restrictions.get("only_runtimes") is not None:
        runtimes = [r for r in runtimes if r in restrictions["only_runtimes"]]
    return runtimes

def parse_supported_map(p: Path):
    try:
        src = p.read_text(encoding="utf-8")
        tree = ast.parse(src)
    except Exception:
        return None
    target_names = {"supported_precision_runtimes", "SUPPORTED_PRECISION_RUNTIMES"}
    result = {}
    for node in ast.walk(tree):
        if isinstance(node, ast.Assign):
            names = []
            for t in node.targets:
                if isinstance(t, ast.Name):
                    names.append(t.id)
            if not names:
                continue
            if not any(n in target_names for n in names):
                continue
            if isinstance(node.value, ast.Dict):
                keys = node.value.keys
                vals = node.value.values
                for k, v in zip(keys, vals):
                    key_name = None
                    if isinstance(k, ast.Attribute) and isinstance(k.value, ast.Name) and k.value.id == "Precision":
                        key_name = k.attr
                    elif isinstance(k, ast.Name):
                        key_name = k.id
                    if key_name is None:
                        continue
                    runtimes = []
                    if isinstance(v, (ast.List, ast.Tuple, ast.Set)):
                        for elt in v.elts:
                            if isinstance(elt, ast.Attribute) and isinstance(elt.value, ast.Name) and elt.value.id in {"TargetRuntime", "Runtime", "Runtimes"}:
                                runtimes.append(elt.attr)
                            elif isinstance(elt, ast.Name):
                                runtimes.append(elt.id)
                    result[key_name] = runtimes
                if result:
                    return result
        elif isinstance(node, ast.AnnAssign):
            target = node.target
            if isinstance(target, ast.Name) and target.id in target_names:
                if isinstance(node.value, ast.Dict):
                    keys = node.value.keys
                    vals = node.value.values
                    for k, v in zip(keys, vals):
                        key_name = None
                        if isinstance(k, ast.Attribute) and isinstance(k.value, ast.Name) and k.value.id == "Precision":
                            key_name = k.attr
                        elif isinstance(k, ast.Name):
                            key_name = k.id
                        if key_name is None:
                            continue
                        runtimes = []
                        if isinstance(v, (ast.List, ast.Tuple, ast.Set)):
                            for elt in v.elts:
                                if isinstance(elt, ast.Attribute) and isinstance(elt.value, ast.Name) and elt.value.id in {"TargetRuntime", "Runtime", "Runtimes"}:
                                    runtimes.append(elt.attr)
                                elif isinstance(elt, ast.Name):
                                    runtimes.append(elt.id)
                        result[key_name] = runtimes
                    if result:
                        return result
    return None

def ensure_repo(repo_dir: Path | None) -> Path:
    base = repo_dir if repo_dir else Path(os.environ.get("AIHM_REPO_DIR", ""))
    if not str(base):
        tmp_root = Path(os.environ.get("TMPDIR", "/tmp"))
        base = tmp_root / "ai-hub-models"
    if not (base / ".git").exists():
        base.parent.mkdir(parents=True, exist_ok=True)
        try:
            subprocess.run(["git", "clone", "--depth", "1", "-b", "main", "https://github.com/quic/ai-hub-models.git", str(base)], check=True)
        except Exception:
            try:
                subprocess.run(["git", "clone", "--depth", "1", "-b", "main", "https://ghfast.top/github.com/quic/ai-hub-models.git", str(base)], check=True)
            except Exception:
                subprocess.run(["git", "clone", "--depth", "1", "-b", "main", "https://mirror.ghproxy.com/https://github.com/quic/ai-hub-models.git", str(base)], check=True)
    return base

def collect_combos(repo_root: Path, model_id: str):
    models_dir = repo_root / "qai_hub_models" / "models"
    d = models_dir / model_id
    candidates = [d / "evaluate.py", d / "export.py"]
    mapping = None
    for c in candidates:
        if c.exists():
            mapping = parse_supported_map(c)
            if mapping:
                break
    rows = []
    if mapping:
        restrictions = detect_restrictions(d)
        for precision, runtimes in mapping.items():
            filtered = [r for r in runtimes if supports_precision(r, precision)]
            filtered = apply_model_restrictions(filtered, precision, restrictions)
            if filtered:
                rows.extend([(model_id, precision, r) for r in filtered])
    return rows

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--model-id", required=True)
    ap.add_argument("--action", choices=["list", "fetch"], default="list")
    ap.add_argument("--repo-dir", default=None)
    ap.add_argument("--output-dir", default=None)
    ap.add_argument("--runtime-filter", default=None)
    ap.add_argument("--precision-filter", default=None)
    ap.add_argument("--unzip", action="store_true")
    args = ap.parse_args()

    repo_root = ensure_repo(Path(args.repo_dir).expanduser() if args.repo_dir else None)

    combos = collect_combos(repo_root, args.model_id)
    if args.runtime_filter:
        rf = {s.strip().upper() for s in args.runtime_filter.split(",") if s.strip()}
        combos = [c for c in combos if c[2].upper() in rf]
    if args.precision_filter:
        pf = {s.strip() for s in args.precision_filter.split(",") if s.strip()}
        combos = [c for c in combos if c[1] in pf]

    if args.action == "list":
        for _, p, r in combos:
            print(f"{args.model_id},{p},{runtime_cli_token(r)}")
        return

    base_out = Path(args.output_dir).expanduser() if args.output_dir else Path.cwd() / "models" / args.model_id
    base_out.mkdir(parents=True, exist_ok=True)
    get_script = Path(__file__).resolve().parent / "get_model_file.py"
    for _, p, r in combos:
        rt = runtime_cli_token(r)
        out_dir = base_out / rt
        out_dir.mkdir(parents=True, exist_ok=True)
        cmd = [
            "python3", str(get_script),
            "--model", args.model_id,
            "--format", rt,
            "--repo-dir", str(repo_root),
            "--output-dir", str(out_dir),
        ]
        if args.unzip:
            cmd.append("--unzip")
        subprocess.run(cmd, check=True)

if __name__ == "__main__":
    main()
