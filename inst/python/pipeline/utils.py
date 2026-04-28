"""Shared image-processing utilities for the SmallUNet pipeline."""
from __future__ import annotations

import math
import re
import warnings
from typing import Any

import cv2
import numpy as np
from scipy import ndimage, signal
from skimage import measure, morphology
from skimage.feature import canny
from skimage.filters import gaussian, sobel, threshold_local
from skimage.morphology import convex_hull_image, dilation, remove_small_objects, skeletonize

warnings.filterwarnings(
    "ignore",
    message=r"Parameter `min_size` is deprecated.*",
    category=FutureWarning,
)
warnings.filterwarnings(
    "ignore",
    message=r"Parameter `area_threshold` is deprecated.*",
    category=FutureWarning,
)

PETRI_DISH_DIAMETER_MM = 90.0


def parse_day(filename: str) -> int:
    match = re.search(r"day(\d+)", filename, re.IGNORECASE)
    if not match:
        match = re.search(r"d(\d+)", filename, re.IGNORECASE)
    if match:
        return int(match.group(1))
    generic = re.search(r"(\d+)", filename)
    return int(generic.group(1)) if generic else 0


def _circle_mask(width: int, height: int, center_x: float, center_y: float, radius_px: float) -> np.ndarray:
    yy, xx = np.indices((height, width))
    return (xx - center_x) ** 2 + (yy - center_y) ** 2 <= radius_px**2


def _score_circle_candidate(gray: np.ndarray, center_x: float, center_y: float, radius_px: float) -> float:
    angles = np.linspace(0.0, 2.0 * math.pi, 360, endpoint=False)
    inner_radius = max(radius_px - 6.0, radius_px * 0.985)
    outer_radius = min(radius_px + 6.0, radius_px * 1.015)

    inside_x = np.clip(np.round(center_x + inner_radius * np.cos(angles)).astype(int), 0, gray.shape[1] - 1)
    inside_y = np.clip(np.round(center_y + inner_radius * np.sin(angles)).astype(int), 0, gray.shape[0] - 1)
    outside_x = np.clip(np.round(center_x + outer_radius * np.cos(angles)).astype(int), 0, gray.shape[1] - 1)
    outside_y = np.clip(np.round(center_y + outer_radius * np.sin(angles)).astype(int), 0, gray.shape[0] - 1)

    ring_contrast = np.abs(
        gray[outside_y, outside_x].astype(np.float32) - gray[inside_y, inside_x].astype(np.float32)
    ).mean()
    centeredness = 1.0 - (
        math.hypot(center_x - (gray.shape[1] / 2.0), center_y - (gray.shape[0] / 2.0))
        / max(min(gray.shape) / 2.0, 1.0)
    )
    return float(ring_contrast + max(centeredness, 0.0) * 8.0)


def _detect_dish_geometry(gray: np.ndarray) -> tuple[float, float, float]:
    height, width = gray.shape
    scale = 1.0
    working = gray
    max_dim = max(height, width)
    if max_dim > 1200:
        scale = 1200.0 / max_dim
        working = cv2.resize(gray, dsize=None, fx=scale, fy=scale, interpolation=cv2.INTER_AREA)

    blurred = cv2.GaussianBlur(working, (9, 9), 2.0)
    min_dim = min(working.shape)
    min_radius = max(int(min_dim * 0.35), 40)
    max_radius = max(int(min_dim * 0.52), min_radius + 5)

    circles = cv2.HoughCircles(
        blurred,
        cv2.HOUGH_GRADIENT,
        dp=1.2,
        minDist=min_dim * 0.5,
        param1=120,
        param2=30,
        minRadius=min_radius,
        maxRadius=max_radius,
    )

    if circles is not None and len(circles[0]) > 0:
        scored = []
        for candidate in circles[0]:
            cx, cy, radius = map(float, candidate)
            score = _score_circle_candidate(working, cx, cy, radius)
            scored.append((score, cx, cy, radius))
        _, cx, cy, radius = max(scored, key=lambda item: item[0])
        return cx / scale, cy / scale, radius / scale

    fallback_radius = min(height, width) * 0.47
    return width / 2.0, height / 2.0, fallback_radius


def _pixels_to_normalized(center_x: float, center_y: float, radius_px: float, width: int, height: int) -> tuple[dict[str, float], float]:
    return (
        {
            "x": float(np.clip((center_x / max(width, 1)) * 1000.0, 0.0, 1000.0)),
            "y": float(np.clip((center_y / max(height, 1)) * 1000.0, 0.0, 1000.0)),
        },
        float(np.clip((radius_px / max(width, 1)) * 1000.0, 0.0, 1000.0)),
    )


def _clip_points_to_dish(points_xy: np.ndarray, center_x: float, center_y: float, radius_px: float) -> np.ndarray:
    if len(points_xy) == 0:
        return points_xy
    clipped = points_xy.astype(float).copy()
    deltas = clipped - np.array([center_x, center_y], dtype=float)
    distances = np.linalg.norm(deltas, axis=1)
    outside = distances > radius_px
    if np.any(outside):
        safe_distances = np.maximum(distances[outside], 1e-6)
        scale = (radius_px - 1.0) / safe_distances
        clipped[outside] = np.column_stack(
            [
                center_x + deltas[outside, 0] * scale,
                center_y + deltas[outside, 1] * scale,
            ]
        )
    return clipped


def _pixels_to_normalized_points(points_xy: np.ndarray, width: int, height: int) -> list[dict[str, float]]:
    if len(points_xy) == 0:
        return []
    return [
        {
            "x": float(np.clip((point[0] / max(width, 1)) * 1000.0, 0.0, 1000.0)),
            "y": float(np.clip((point[1] / max(height, 1)) * 1000.0, 0.0, 1000.0)),
        }
        for point in points_xy
    ]


def _normalized_points_to_pixels(points_xy: list[dict[str, float]], width: int, height: int) -> np.ndarray:
    if not points_xy:
        return np.empty((0, 2), dtype=float)
    points: list[tuple[float, float]] = []
    for point in points_xy:
        try:
            x = float(point.get("x", 0.0))
            y = float(point.get("y", 0.0))
        except AttributeError:
            continue
        points.append(
            (
                float(np.clip((x / 1000.0) * max(width - 1, 1), 0.0, max(width - 1, 1))),
                float(np.clip((y / 1000.0) * max(height - 1, 1), 0.0, max(height - 1, 1))),
            )
        )
    return np.asarray(points, dtype=float)


def _correct_background(gray: np.ndarray, dish_mask: np.ndarray) -> np.ndarray:
    gray_f = gray.astype(np.float32)
    background = cv2.GaussianBlur(gray_f, (0, 0), sigmaX=45, sigmaY=45)
    corrected = gray_f / np.maximum(background, 1.0)
    corrected = cv2.normalize(corrected, None, 0, 255, cv2.NORM_MINMAX)
    corrected = corrected.astype(np.uint8)
    corrected[~dish_mask] = 0
    return corrected


def _restrict_to_internal_band(colony_mask: np.ndarray, pixel_size_mm: float, band_mm: float = 3.0) -> np.ndarray:
    colony = np.asarray(colony_mask, dtype=bool)
    if colony.sum() == 0:
        return colony
    radius_px = max(1, int(round(float(band_mm) / max(float(pixel_size_mm), 1e-6))))
    inner = morphology.erosion(colony, morphology.disk(radius_px))
    if inner.sum() == 0:
        return colony
    return inner.astype(bool)


def _detect_cracks(image: np.ndarray, mask: np.ndarray, std_threshold: float = 0.3, min_size: int = 15) -> tuple[np.ndarray, np.ndarray, float]:
    if mask.sum() == 0:
        return np.zeros_like(mask, dtype=bool), np.zeros_like(mask, dtype=bool), 0.0

    filled_mask = ndimage.binary_fill_holes(mask)
    try:
        analysis_mask = convex_hull_image(filled_mask)
    except Exception:
        analysis_mask = filled_mask

    values = image[analysis_mask]
    mean_val = float(values.mean()) if values.size else 0.0
    std_val = float(values.std()) if values.size else 0.0
    threshold = mean_val - std_threshold * std_val

    smoothed = gaussian(image, sigma=1.5)
    edges = sobel(smoothed)
    edges[~analysis_mask] = 0
    canny_edges = canny(smoothed, sigma=1.5, low_threshold=0.02, high_threshold=0.08) & analysis_mask

    masked_image = np.asarray(image, dtype=float).copy()
    masked_image[~analysis_mask] = mean_val
    local_thresh = threshold_local(masked_image, block_size=51, offset=0.02)
    local_dark = (image < local_thresh) & analysis_mask
    global_dark = (image < threshold) & analysis_mask

    edge_threshold = np.percentile(edges[analysis_mask], 70) if np.any(analysis_mask) else 0.0
    strong_edges = edges > edge_threshold
    crack_mask = (local_dark | global_dark) & (strong_edges | canny_edges)

    very_dark = (image < mean_val - 2.0 * std_val) & analysis_mask
    crack_mask = crack_mask | very_dark

    props = measure.regionprops(analysis_mask.astype(int))
    if props:
        centroid = props[0].centroid
        y_coords, x_coords = np.ogrid[:image.shape[0], :image.shape[1]]
        dist_from_center = np.sqrt((y_coords - centroid[0]) ** 2 + (x_coords - centroid[1]) ** 2)
        equiv_radius = np.sqrt(analysis_mask.sum() / np.pi)
        central_mask = (dist_from_center < equiv_radius * 0.7) & analysis_mask
    else:
        central_mask = analysis_mask

    local_bright = (image > local_thresh + 0.01) & analysis_mask
    global_bright = (image > mean_val + std_threshold * 0.5 * std_val) & analysis_mask
    very_bright = (image > mean_val + 0.8 * std_val) & analysis_mask
    central_bright = (image > mean_val + 0.5 * std_val) & central_mask
    bright_cracks = (local_bright | global_bright) & (strong_edges | canny_edges)
    crack_mask = crack_mask | bright_cracks | very_bright | central_bright

    crack_mask = dilation(crack_mask, morphology.disk(2)) & analysis_mask
    if crack_mask.sum() > 0:
        crack_mask = remove_small_objects(crack_mask.astype(bool), min_size=min_size)
    crack_skeleton = skeletonize(crack_mask) if crack_mask.sum() > 0 else np.zeros_like(crack_mask, dtype=bool)
    return crack_mask.astype(bool), crack_skeleton.astype(bool), float(threshold)


def _measure_crack_properties(crack_skeleton: np.ndarray) -> dict[str, float | int]:
    if crack_skeleton.sum() == 0:
        return {
            "total_length_px": 0,
            "num_segments": 0,
            "mean_segment_length_px": 0.0,
        }
    _labeled, num_segments = ndimage.label(crack_skeleton)
    total_length = int(crack_skeleton.sum())
    mean_length = total_length / num_segments if num_segments > 0 else 0.0
    return {
        "total_length_px": total_length,
        "num_segments": int(num_segments),
        "mean_segment_length_px": float(mean_length),
    }


def _crack_polylines_from_skeleton(crack_skeleton: np.ndarray, width: int, height: int) -> list[list[dict[str, float]]]:
    contours, _ = cv2.findContours(crack_skeleton.astype(np.uint8), cv2.RETR_LIST, cv2.CHAIN_APPROX_NONE)
    polylines: list[list[dict[str, float]]] = []
    for contour in contours:
        points = contour.reshape(-1, 2).astype(float)
        if len(points) < 2:
            continue
        epsilon = max(1.0, 0.01 * cv2.arcLength(contour, False))
        approx = cv2.approxPolyDP(contour, epsilon, False).reshape(-1, 2).astype(float)
        if len(approx) < 2:
            continue
        polylines.append(_pixels_to_normalized_points(approx, width, height))
    return polylines


def _polygon_from_mask(mask: np.ndarray, width: int, height: int) -> np.ndarray:
    contours, _ = cv2.findContours(mask.astype(np.uint8), cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    if not contours:
        return np.empty((0, 2), dtype=float)
    contour = max(contours, key=cv2.contourArea)
    epsilon = max(2.0, 0.006 * cv2.arcLength(contour, True))
    approx = cv2.approxPolyDP(contour, epsilon, True).reshape(-1, 2).astype(float)
    if len(approx) < 3:
        return np.empty((0, 2), dtype=float)
    approx[:, 0] = np.clip(approx[:, 0], 0, width - 1)
    approx[:, 1] = np.clip(approx[:, 1], 0, height - 1)
    return approx


def _texture_from_mask(gray: np.ndarray, mask: np.ndarray) -> dict[str, Any]:
    masked = gray[mask]
    if masked.size == 0:
        masked = gray.reshape(-1)

    energy = float(np.mean((masked / 255.0) ** 2))
    contrast = float(np.std(masked))
    horizontal_diff = np.abs(np.diff(gray.astype(float), axis=1))
    homogeneity = float(1.0 / (1.0 + np.mean(horizontal_diff)))
    correlation = float(np.clip(np.corrcoef(masked[:-1], masked[1:])[0, 1] if masked.size > 2 else 0.0, -1.0, 1.0))

    coords = np.column_stack(np.nonzero(mask))
    if coords.size == 0:
        coords = np.column_stack(np.nonzero(np.ones_like(mask, dtype=bool)))
    centroid = coords.mean(axis=0)
    distances = np.sqrt((coords[:, 0] - centroid[0]) ** 2 + (coords[:, 1] - centroid[1]) ** 2)
    max_distance = float(distances.max()) if distances.size else 1.0
    zonation = {}
    for label, lower, upper in (
        ("core", 0.0, 1.0 / 3.0),
        ("middle", 1.0 / 3.0, 2.0 / 3.0),
        ("outer", 2.0 / 3.0, 1.0),
    ):
        selector = np.logical_and(distances >= lower * max_distance, distances < upper * max_distance)
        zone_pixels = gray[coords[selector][:, 0], coords[selector][:, 1]] if np.any(selector) else masked
        zonation[label] = float(np.std(zone_pixels))

    return {
        "contrast": contrast,
        "correlation": correlation,
        "energy": energy,
        "homogeneity": homogeneity,
        "radialZonation": zonation,
    }


def _shannon_entropy(masked_values: np.ndarray, bins: int = 32) -> float:
    if masked_values.size == 0:
        return 0.0
    hist, _ = np.histogram(masked_values, bins=bins, range=(0, 255), density=True)
    hist = hist[hist > 0]
    if hist.size == 0:
        return 0.0
    return float(-(hist * np.log2(hist)).sum())


def _edge_roughness(area_px: float, perimeter_px: float) -> float:
    if area_px <= 0 or perimeter_px <= 0:
        return 0.0
    equivalent_circle_perimeter = 2.0 * math.sqrt(math.pi * area_px)
    return float(max(perimeter_px / max(equivalent_circle_perimeter, 1e-6) - 1.0, 0.0))


def _radial_intensity_profile(
    gray: np.ndarray,
    mask: np.ndarray,
    pixel_to_mm: float,
    bins: int = 24,
) -> dict[str, Any]:
    coords = np.column_stack(np.nonzero(mask))
    if coords.size == 0:
        return {
            "radiusFraction": [],
            "radiusMm": [],
            "meanIntensity": [],
            "ringSpacingMm": 0.0,
            "centerToEdgeDelta": 0.0,
            "densityIndex": 0.0,
        }

    centroid = coords.mean(axis=0)
    distances = np.sqrt((coords[:, 0] - centroid[0]) ** 2 + (coords[:, 1] - centroid[1]) ** 2)
    max_distance = float(distances.max()) if distances.size else 1.0
    bin_edges = np.linspace(0.0, max_distance, bins + 1)
    profile_means: list[float] = []
    radius_fraction: list[float] = []
    radius_mm: list[float] = []

    for start, end in zip(bin_edges[:-1], bin_edges[1:]):
        selector = (distances >= start) & (distances < end)
        if not np.any(selector):
            continue
        band_pixels = gray[coords[selector][:, 0], coords[selector][:, 1]]
        profile_means.append(float(np.mean(band_pixels)))
        midpoint = (start + end) / 2.0
        radius_fraction.append(float(midpoint / max(max_distance, 1e-6)))
        radius_mm.append(float(midpoint * pixel_to_mm))

    if not profile_means:
        return {
            "radiusFraction": [],
            "radiusMm": [],
            "meanIntensity": [],
            "ringSpacingMm": 0.0,
            "centerToEdgeDelta": 0.0,
            "densityIndex": 0.0,
        }

    smoothed = ndimage.gaussian_filter1d(np.asarray(profile_means, dtype=float), sigma=1.0, mode="nearest")
    peak_indices, _ = signal.find_peaks(smoothed, distance=max(1, bins // 8))
    if len(peak_indices) >= 2:
        peak_positions = np.asarray(radius_mm, dtype=float)[peak_indices]
        ring_spacing_mm = float(np.mean(np.diff(peak_positions)))
    else:
        ring_spacing_mm = 0.0

    center_slice = max(1, len(profile_means) // 3)
    edge_slice = max(1, len(profile_means) // 4)
    center_mean = float(np.mean(profile_means[:center_slice]))
    edge_mean = float(np.mean(profile_means[-edge_slice:]))
    colony_pixels = gray[mask]
    density_index = float(np.clip(1.0 - (np.mean(colony_pixels) / 255.0), 0.0, 1.0))

    return {
        "radiusFraction": radius_fraction,
        "radiusMm": radius_mm,
        "meanIntensity": profile_means,
        "ringSpacingMm": ring_spacing_mm,
        "centerToEdgeDelta": edge_mean - center_mean,
        "densityIndex": density_index,
    }


def _shape_metrics(mask: np.ndarray) -> tuple[float, float, float]:
    labeled = measure.label(mask.astype(np.uint8))
    regions = measure.regionprops(labeled)
    if not regions:
        return 0.0, 0.0, 0.0
    region = max(regions, key=lambda item: item.area)
    perimeter = float(region.perimeter if region.perimeter > 0 else 0.0)
    return float(region.area), perimeter, float(region.eccentricity)


def _attach_kinematics(results: list[dict[str, Any]]) -> list[dict[str, Any]]:
    sorted_results = sorted(results, key=lambda item: (item["day"], item["filename"]))
    for index, result in enumerate(sorted_results):
        if index == 0:
            continue
        previous = sorted_results[index - 1]
        delta_t = result["day"] - previous["day"]
        if delta_t <= 0:
            continue
        velocity = (
            result["morphology"]["equivalentRadiusMm"] - previous["morphology"]["equivalentRadiusMm"]
        ) / delta_t
        area_rate = (result["morphology"]["areaMm2"] - previous["morphology"]["areaMm2"]) / delta_t
        relative_growth_rate = area_rate / max(previous["morphology"]["areaMm2"], 1e-6)
        acceleration = 0.0
        if index > 1:
            prior = sorted_results[index - 2]
            prior_dt = previous["day"] - prior["day"]
            if prior_dt > 0:
                prior_velocity = (
                    previous["morphology"]["equivalentRadiusMm"] - prior["morphology"]["equivalentRadiusMm"]
                ) / prior_dt
                acceleration = (velocity - prior_velocity) / delta_t
        result["kinematics"] = {
            "radialVelocity": velocity,
            "areaGrowthRate": area_rate,
            "relativeGrowthRate": relative_growth_rate,
            "radialAcceleration": acceleration,
        }
    return sorted_results
