from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any

try:
    from dotenv import load_dotenv
except ModuleNotFoundError:
    def load_dotenv(*args: Any, **kwargs: Any) -> bool:
        return False


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Run gray leaf spot analysis.")
    parser.add_argument("--input-dir", default="input_images")
    parser.add_argument("--output-dir", default="outputs")
    parser.add_argument("--plate-diameter-mm", type=float, default=90.0)
    parser.add_argument("--run-name", default="")
    parser.add_argument("--filename", action="append", dest="filenames")
    parser.add_argument("--json", action="store_true", dest="json_output")
    parser.add_argument("--engine-model", default="localunet", choices=["localunet"])
    parser.add_argument("--model-path", default=None,
                        help="Absolute path to best_area_w_0.7.pt. "
                             "Defaults to 'models/best_area_w_0.7.pt' relative to cwd.")
    return parser


def main() -> None:
    load_dotenv(".env")
    parser = build_parser()
    args = parser.parse_args()
    from pipeline import analysislocal
    input_dir = Path(args.input_dir)
    output_dir = Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)
    if args.filenames:
        images = [input_dir / f for f in args.filenames]
    else:
        images = list(input_dir.glob("**/*"))
        images = [p for p in images if p.suffix.lower() in {".png", ".jpg", ".jpeg", ".bmp", ".tif", ".tiff", ".webp"}]
    model_path = args.model_path or analysislocal.DEFAULT_MODEL_PATH
    results = [analysislocal.analyze_image_local(str(img_path), threshold=0.5, model_path=model_path) for img_path in images]
    payload = analysislocal.write_localunet_outputs(results, output_dir, run_name=args.run_name)
    if args.json_output:
        print(json.dumps(payload, default=str))
        return
    print(json.dumps(payload["run"], indent=2))


if __name__ == "__main__":
    main()
