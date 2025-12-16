import os
import ast
from pathlib import Path
import argparse

ROOT = Path(__file__).resolve().parents[1]
MODELS_DIR = ROOT / "qai_hub_models" / "models"

def get_models_dir(repo_dir: str | None) -> Path:
    if repo_dir:
        base = Path(repo_dir)
        return base / "qai_hub_models" / "models"
    tmp_root = Path(os.environ.get("TMPDIR", "/tmp")) / "ai-hub-models"
    if not (tmp_root / ".git").exists():
        try:
            import subprocess
            subprocess.run([
                "git", "clone", "--depth", "1", "-b", "main",
                "https://github.com/quic/ai-hub-models.git", str(tmp_root)
            ], check=True)
        except Exception:
            # 尝试镜像
            try:
                import subprocess
                subprocess.run([
                    "git", "clone", "--depth", "1", "-b", "main",
                    "https://ghfast.top/github.com/quic/ai-hub-models.git", str(tmp_root)
                ], check=True)
            except Exception:
                subprocess.run([
                    "git", "clone", "--depth", "1", "-b", "main",
                    "https://mirror.ghproxy.com/https://github.com/quic/ai-hub-models.git", str(tmp_root)
                ], check=True)
    return tmp_root / "qai_hub_models" / "models"

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

def collect(models_dir: Path):
    rows = []
    for d in sorted(models_dir.iterdir()):
        if not d.is_dir():
            continue
        model = d.name
        candidates = [d / "evaluate.py", d / "export.py"]
        mapping = None
        for c in candidates:
            if c.exists():
                mapping = parse_supported_map(c)
                if mapping:
                    break
        if mapping:
            restrictions = detect_restrictions(d)
            for precision, runtimes in mapping.items():
                filtered = [r for r in runtimes if supports_precision(r, precision)]
                filtered = apply_model_restrictions(filtered, precision, restrictions)
                if filtered:
                    rows.append((model, precision, ", ".join(filtered)))
    return rows

def to_markdown(rows):
    lines = []
    lines.append("| Model | Precision | Runtimes |")
    lines.append("|---|---|---|")
    for m, p, r in rows:
        lines.append(f"| {m} | {p} | {r} |")
    return "\n".join(lines)

def to_csv(rows):
    lines = ["model,precision,runtimes"]
    def runtime_cli_token(name: str) -> str:
        name = name.strip()
        mapping = {
            "TFLITE": "tflite",
            "ONNX": "onnx",
            "QNN_DLC": "qnn_dlc",
            "QNN_CONTEXT_BINARY": "qnn_context_binary",
            "PRECOMPILED_QNN_ONNX": "precompiled_qnn_onnx",
            "GENIE": "genie",
            "ONNXRUNTIME_GENAI": "onnxruntime_genai",
        }
        return mapping.get(name, name.lower())
    for m, p, r in rows:
        runtime_names = [s.strip() for s in r.split(",")]
        runtimes = ";".join(runtime_cli_token(s) for s in runtime_names if s)
        lines.append(f"{m},{p},{runtimes}")
    return "\n".join(lines)

if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--format", choices=["md", "csv"], default="md")
    ap.add_argument("--repo-dir", default=None)
    args = ap.parse_args()
    models_dir = get_models_dir(args.repo_dir)
    rows = collect(models_dir)
    if args.format == "csv":
        print(to_csv(rows))
    else:
        print(to_markdown(rows))
