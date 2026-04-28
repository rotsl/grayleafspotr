from __future__ import annotations

import csv
import json
import math
import os
from datetime import datetime, timezone
from pathlib import Path
from typing import Any
from urllib.parse import quote

import cv2
import numpy as np
from PIL import Image, ImageDraw
import torch
import torch.nn as nn
import torch.nn.functional as F

from pipeline.utils import (
    PETRI_DISH_DIAMETER_MM,
    parse_day,
    _attach_kinematics,
    _circle_mask,
    _clip_points_to_dish,
    _correct_background,
    _crack_polylines_from_skeleton,
    _detect_cracks,
    _detect_dish_geometry,
    _edge_roughness,
    _measure_crack_properties,
    _pixels_to_normalized,
    _normalized_points_to_pixels,
    _pixels_to_normalized_points,
    _polygon_from_mask,
    _radial_intensity_profile,
    _restrict_to_internal_band,
    _shannon_entropy,
    _shape_metrics,
    _texture_from_mask,
)


# --- CONFIG ---
DEFAULT_MODEL_PATH = "models/best_area_w_0.7.pt"
DEFAULT_IMAGE_SIZE = 256
DEVICE = "mps" if torch.backends.mps.is_available() else "cpu"


# --- Model Blocks ---
class ConvBlock(nn.Module):
    def __init__(self, in_channels: int, out_channels: int) -> None:
        super().__init__()
        self.block = nn.Sequential(
            nn.Conv2d(in_channels, out_channels, kernel_size=3, padding=1, bias=False),
            nn.ReLU(inplace=True),
            nn.Conv2d(out_channels, out_channels, kernel_size=3, padding=1, bias=False),
            nn.ReLU(inplace=True),
        )

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        return self.block(x)


class DownBlock(nn.Module):
    def __init__(self, in_channels: int, out_channels: int) -> None:
        super().__init__()
        self.pool = nn.MaxPool2d(kernel_size=2, stride=2)
        self.conv = ConvBlock(in_channels, out_channels)

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        return self.conv(self.pool(x))


class UpBlock(nn.Module):
    def __init__(self, in_channels: int, out_channels: int) -> None:
        super().__init__()
        self.up = nn.Upsample(scale_factor=2, mode="bilinear", align_corners=False)
        self.conv = ConvBlock(in_channels, out_channels)

    def forward(self, x: torch.Tensor, skip: torch.Tensor) -> torch.Tensor:
        x = self.up(x)
        if x.shape[-2:] != skip.shape[-2:]:
            x = F.interpolate(x, size=skip.shape[-2:], mode="bilinear", align_corners=False)
        x = torch.cat([skip, x], dim=1)
        return self.conv(x)


class SmallUNet(nn.Module):
    def __init__(self, in_channels: int = 3, out_channels: int = 1, base_channels: int = 16) -> None:
        super().__init__()
        self.enc1 = ConvBlock(in_channels, base_channels)
        self.enc2 = DownBlock(base_channels, base_channels * 2)
        self.enc3 = DownBlock(base_channels * 2, base_channels * 4)
        self.enc4 = DownBlock(base_channels * 4, base_channels * 8)
        self.bottleneck = DownBlock(base_channels * 8, base_channels * 16)
        self.up4 = UpBlock(base_channels * 16 + base_channels * 8, base_channels * 8)
        self.up3 = UpBlock(base_channels * 8 + base_channels * 4, base_channels * 4)
        self.up2 = UpBlock(base_channels * 4 + base_channels * 2, base_channels * 2)
        self.up1 = UpBlock(base_channels * 2 + base_channels, base_channels)
        self.head = nn.Conv2d(base_channels, out_channels, 1)

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        e1 = self.enc1(x)
        e2 = self.enc2(e1)
        e3 = self.enc3(e2)
        e4 = self.enc4(e3)
        b = self.bottleneck(e4)
        d4 = self.up4(b, e4)
        d3 = self.up3(d4, e3)
        d2 = self.up2(d3, e2)
        d1 = self.up1(d2, e1)
        return self.head(d1)


def load_model(weights_path: str = DEFAULT_MODEL_PATH) -> SmallUNet:
    model = SmallUNet(in_channels=3, out_channels=1, base_channels=16)
    checkpoint = torch.load(weights_path, map_location=DEVICE)
    if isinstance(checkpoint, dict) and "model_state_dict" in checkpoint:
        state_dict = checkpoint["model_state_dict"]
    else:
        state_dict = checkpoint
    model.load_state_dict(state_dict, strict=True)
    model.eval()
    model.to(DEVICE)
    return model


def infer_image(model: SmallUNet, img: Image.Image, threshold: float = 0.5) -> tuple[Image.Image, Image.Image]:
    img_arr = np.array(img.convert("RGB"))
    img_resized = cv2.resize(img_arr, (DEFAULT_IMAGE_SIZE, DEFAULT_IMAGE_SIZE))
    x = torch.from_numpy(img_resized.transpose(2, 0, 1)).float() / 255.0
    x = x.unsqueeze(0).to(DEVICE)
    with torch.no_grad():
        raw = model(x)[0, 0].detach().cpu().numpy()
    mask = (raw > threshold).astype(np.uint8) * 255
    mask = cv2.resize(mask, (img.width, img.height), interpolation=cv2.INTER_NEAREST)
    overlay = np.array(img).copy().astype(np.uint8)
    overlay[mask > 0] = (overlay[mask > 0] * 0.5 + np.array([255, 0, 0]) * 0.5).astype(np.uint8)
    return Image.fromarray(overlay), Image.fromarray(mask)


def analyze_image_local(
    image_path: str,
    threshold: float = 0.5,
    model_path: str = DEFAULT_MODEL_PATH,
    plate_diameter_mm: float = PETRI_DISH_DIAMETER_MM,
) -> dict[str, Any]:
    img = Image.open(image_path).convert("RGB")
    width, height = img.size
    gray = np.array(img.convert("L"))

    center_x, center_y, radius_px = _detect_dish_geometry(gray)
    pixel_to_mm = (plate_diameter_mm / 2.0) / max(radius_px, 1.0)
    dish_mask = _circle_mask(width, height, center_x, center_y, radius_px)
    detected_dish_center, detected_dish_radius = _pixels_to_normalized(center_x, center_y, radius_px, width, height)

    model = load_model(model_path)
    overlay_pil, mask_pil = infer_image(model, img, threshold)
    mask_np = (np.array(mask_pil) > 0) & dish_mask

    filename = os.path.basename(image_path)
    day = parse_day(filename)
    engine_model = "localunet-smallunet"

    area_px, perimeter_px, eccentricity = _shape_metrics(mask_np)
    area_mm2 = float(area_px * pixel_to_mm ** 2)
    perimeter_mm = float(perimeter_px * pixel_to_mm)
    equivalent_radius_mm = float(math.sqrt(area_mm2 / math.pi)) if area_mm2 > 0 else 0.0
    diameter_mm = equivalent_radius_mm * 2.0
    circularity = float(4 * math.pi * area_px / perimeter_px ** 2) if perimeter_px > 0 else 0.0
    edge_roughness_val = _edge_roughness(area_px, perimeter_px)

    texture = _texture_from_mask(gray, mask_np)
    texture["entropy"] = _shannon_entropy(gray[mask_np])
    radial_profile = _radial_intensity_profile(gray, mask_np, pixel_to_mm)
    texture["centerToEdgeDelta"] = radial_profile["centerToEdgeDelta"]
    texture["densityIndex"] = radial_profile["densityIndex"]

    corrected_gray = _correct_background(gray, dish_mask).astype(np.float32) / 255.0
    proportional_band_mm = max(0.25, equivalent_radius_mm * 0.10)
    internal_mask = _restrict_to_internal_band(mask_np, pixel_to_mm, band_mm=proportional_band_mm)
    crack_mask, crack_skeleton, crack_threshold = _detect_cracks(
        corrected_gray, internal_mask, std_threshold=0.3, min_size=15
    )
    crack_props = _measure_crack_properties(crack_skeleton)
    crack_polylines = _crack_polylines_from_skeleton(crack_skeleton, width, height)

    total_crack_length_px = float(crack_props["total_length_px"])
    total_crack_length_mm = total_crack_length_px * pixel_to_mm
    coverage_pct = min(100.0, (total_crack_length_px / max(perimeter_px, 1.0)) * 100.0)
    proportional_coverage_pct = min(
        100.0,
        (total_crack_length_px / max(math.sqrt(max(area_px, 1.0)), 1.0)) * 10.0,
    )
    internal_band_description = (
        f"Internal-band crack analysis used a {proportional_band_mm:.2f} mm inward band with "
        f"{crack_props['num_segments']} detected crack segments."
    )

    refined_polygon_xy = _polygon_from_mask(mask_np, width, height)
    if len(refined_polygon_xy) >= 3:
        refined_polygon_xy = _clip_points_to_dish(refined_polygon_xy, center_x, center_y, radius_px)
    colony_polygon = _pixels_to_normalized_points(refined_polygon_xy, width, height)

    qc_notes = " ".join([
        f"Local inference using {engine_model}.",
        f"Dish geometry calibrated from grayscale image edges using an assumed {plate_diameter_mm:.0f} mm petri dish.",
        "Saved colony geometry is clipped to remain inside the detected dish.",
        "Crack analysis computed classically from the final internal-band mask.",
    ])

    return {
        "id": Path(filename).with_suffix("").as_posix(),
        "filename": filename,
        "day": day,
        "imageUrl": "/input_images/" + quote(filename),
        "pixelToMm": pixel_to_mm,
        "overlay": overlay_pil,
        "mask": mask_pil,
        "morphology": {
            "areaMm2": area_mm2,
            "equivalentRadiusMm": equivalent_radius_mm,
            "diameterMm": diameter_mm,
            "perimeterMm": perimeter_mm,
            "circularity": circularity,
            "eccentricity": eccentricity,
            "edgeRoughness": edge_roughness_val,
        },
        "texture": texture,
        "cracks": {
            "count": len(crack_polylines),
            "totalLengthMm": total_crack_length_mm,
            "coveragePct": coverage_pct,
            "proportionalCoveragePct": proportional_coverage_pct,
            "internalBandSummary": internal_band_description,
        },
        "kinematics": {
            "radialVelocity": 0.0,
            "areaGrowthRate": 0.0,
            "relativeGrowthRate": 0.0,
            "radialAcceleration": 0.0,
        },
        "qcStatus": "pass",
        "qcNotes": qc_notes,
        "rawAnalysis": {
            "dish_center": detected_dish_center,
            "dish_radius": detected_dish_radius,
            "colony_polygon": colony_polygon,
            "cracks": crack_polylines,
            "internal_band_description": internal_band_description,
            "radial_profile": radial_profile,
            "crack_analysis": {
                "analysis_band_mm": proportional_band_mm,
                "analysis_threshold": float(crack_threshold),
                "crack_area_px": int(crack_mask.sum()),
                **crack_props,
            },
            "morphology_estimates": {
                "area_mm2": area_mm2,
                "perimeter_mm": perimeter_mm,
                "diameter_mm": diameter_mm,
            },
            "segmentation_diagnostics": {
                "petri_dish_diameter_mm": plate_diameter_mm,
                "refined_mask_area_px": int(area_px),
                "hybrid_strategy": "localunet",
                "hybrid_strategy_reason": "SmallUNet-only segmentation, no SAM or classical refinement.",
                "sam_decision": "not_run",
            },
        },
        "_engineModel": engine_model,
    }


def write_localunet_outputs(results: list[dict[str, Any]], output_dir: Path, run_name: str = "") -> dict:
    timestamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    run_dir = output_dir / (f"{timestamp}_localunet" + (f"_{run_name}" if run_name else ""))
    run_dir.mkdir(parents=True, exist_ok=True)
    overlay_dir = run_dir / "overlays"
    overlay_dir.mkdir(exist_ok=True)

    engine_model = ""
    for res in results:
        stem = Path(res["filename"]).stem
        overlay_path = overlay_dir / (stem + "_overlay.png")
        mask_path = overlay_dir / (stem + "_mask.png")
        overlay_img = res["overlay"].convert("RGBA")
        width, height = overlay_img.size
        draw = ImageDraw.Draw(overlay_img, "RGBA")
        for crack in (res.get("rawAnalysis") or {}).get("cracks") or []:
            crack_xy = _normalized_points_to_pixels(crack, width, height)
            if len(crack_xy) >= 2:
                draw.line([tuple(pt) for pt in crack_xy], fill=(255, 220, 0, 220), width=2)
        overlay_img.convert("RGB").save(overlay_path)
        res["mask"].save(mask_path)
        res.setdefault("rawAnalysis", {})["overlayImage"] = str(overlay_path.relative_to(run_dir))
        res.pop("overlay")
        res.pop("mask")
        engine_model = str(res.pop("_engineModel", engine_model))

    results = _attach_kinematics(results)

    analysis_json_path = run_dir / "analysis.json"
    analysis_json_path.write_text(json.dumps(results, indent=2), encoding="utf-8")

    analysis_csv_path = run_dir / "analysis.csv"
    with analysis_csv_path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.writer(handle)
        writer.writerow([
            "filename", "day", "area_mm2", "radius_mm", "diameter_mm", "perimeter_mm",
            "circularity", "eccentricity", "edge_roughness", "contrast", "correlation",
            "energy", "homogeneity", "texture_entropy", "center_to_edge_intensity_delta",
            "density_index", "ring_spacing_mm", "radial_velocity_mm_per_day",
            "area_growth_rate_mm2_per_day", "relative_growth_rate_per_day",
            "crack_count", "crack_length_mm", "crack_coverage_pct", "qc_status",
        ])
        for res in results:
            writer.writerow([
                res["filename"],
                res["day"],
                res["morphology"]["areaMm2"],
                res["morphology"]["equivalentRadiusMm"],
                res["morphology"]["diameterMm"],
                res["morphology"]["perimeterMm"],
                res["morphology"]["circularity"],
                res["morphology"]["eccentricity"],
                res["morphology"]["edgeRoughness"],
                res["texture"]["contrast"],
                res["texture"].get("correlation", 0.0),
                res["texture"].get("energy", 0.0),
                res["texture"].get("homogeneity", 0.0),
                res["texture"]["entropy"],
                res["texture"]["centerToEdgeDelta"],
                res["texture"]["densityIndex"],
                res.get("rawAnalysis", {}).get("radial_profile", {}).get("ringSpacingMm", 0.0),
                res["kinematics"]["radialVelocity"],
                res["kinematics"]["areaGrowthRate"],
                res["kinematics"]["relativeGrowthRate"],
                res["cracks"]["count"],
                res["cracks"]["totalLengthMm"],
                res["cracks"]["coveragePct"],
                res["qcStatus"],
            ])

    manifest = {
        "engine": "local",
        "engine_model": engine_model,
        "created_at": datetime.now(timezone.utc).isoformat(),
        "output_dir": str(run_dir.resolve()),
        "overlay_dir": str(overlay_dir.resolve()),
        "analysis_json": str(analysis_json_path.resolve()),
        "analysis_csv": str(analysis_csv_path.resolve()),
    }
    manifest_json_path = run_dir / "manifest.json"
    manifest_json_path.write_text(json.dumps(manifest, indent=2), encoding="utf-8")

    return {"results": results, "run": manifest}
