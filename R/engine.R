list_grayleafspot_images <- function(input_dir) {
  if (!dir.exists(input_dir)) {
    return(character())
  }
  pattern <- "\\.(png|jpg|jpeg|bmp|tif|tiff|webp)$"
  files <- list.files(input_dir, recursive = TRUE, full.names = TRUE, ignore.case = TRUE)
  files[grepl(pattern, files, ignore.case = TRUE)]
}

compute_kinematics <- function(results) {
  if (length(results) == 0) {
    return(results)
  }
  ordered <- results[order(vapply(results, function(x) x$day, numeric(1)))]
  area <- vapply(ordered, function(x) x$morphology$areaMm2, numeric(1))
  radius <- vapply(ordered, function(x) x$morphology$equivalentRadiusMm, numeric(1))
  day <- vapply(ordered, function(x) x$day, numeric(1))

  area_growth_rate <- c(NA_real_, diff(area) / pmax(diff(day), 1))
  relative_growth_rate <- c(NA_real_, diff(log1p(area)) / pmax(diff(day), 1))
  radial_velocity <- c(NA_real_, diff(radius) / pmax(diff(day), 1))
  radial_acceleration <- c(NA_real_, diff(radial_velocity) / pmax(diff(day), 1))

  for (i in seq_along(ordered)) {
    ordered[[i]]$kinematics$areaGrowthRate <- area_growth_rate[i]
    ordered[[i]]$kinematics$relativeGrowthRate <- relative_growth_rate[i]
    ordered[[i]]$kinematics$radialVelocity <- radial_velocity[i]
    ordered[[i]]$kinematics$radialAcceleration <- radial_acceleration[i]
  }
  ordered
}

analyze_grayleafspot_image <- function(path, plate_diameter_mm = 90) {
  gray <- read_grayscale_matrix(path)
  height <- nrow(gray)
  width <- ncol(gray)
  center_x <- (width + 1) / 2
  center_y <- (height + 1) / 2
  dish_radius_px <- min(width, height) * 0.45
  dish_mask <- circle_mask(width, height, center_x, center_y, dish_radius_px)
  dish_values <- gray[dish_mask]
  if (!length(dish_values)) {
    dish_values <- as.vector(gray)
  }

  threshold <- safe_quantile(dish_values, 0.45, default = 0.5)
  colony_mask <- dish_mask & gray <= threshold
  area_px <- sum(colony_mask)
  perimeter_px <- estimate_perimeter_px(colony_mask)
  area_fraction <- if (sum(dish_mask) > 0) area_px / sum(dish_mask) else 0
  pixel_to_mm <- (plate_diameter_mm / 2) / dish_radius_px
  area_mm2 <- area_px * pixel_to_mm^2
  equivalent_radius_mm <- sqrt(area_mm2 / pi)
  diameter_mm <- 2 * equivalent_radius_mm
  perimeter_mm <- perimeter_px * pixel_to_mm
  circularity <- if (perimeter_mm > 0) 4 * pi * area_mm2 / (perimeter_mm^2) else 0
  eccentricity <- eccentricity_from_mask(colony_mask)
  edge_roughness <- if (equivalent_radius_mm > 0) perimeter_mm / (2 * pi * equivalent_radius_mm) - 1 else 0

  colony_values <- gray[colony_mask]
  texture_entropy <- shannon_entropy(colony_values)
  contrast <- stats::sd(dish_values)
  homogeneity <- 1 / (1 + stats::var(dish_values))
  energy <- mean(dish_values^2)
  correlation <- if (height > 1) stats::cor(as.vector(gray[-height, ]), as.vector(gray[-1, ]), use = "complete.obs") else 0
  if (!is.finite(correlation)) {
    correlation <- 0
  }
  center_mean <- annulus_mean(gray, center_x, center_y, dish_radius_px, 0.0, 0.33)
  middle_mean <- annulus_mean(gray, center_x, center_y, dish_radius_px, 0.33, 0.66)
  outer_mean <- annulus_mean(gray, center_x, center_y, dish_radius_px, 0.66, 1.0)
  center_edge_delta <- outer_mean - center_mean
  density_index <- if (length(colony_values)) mean(colony_values < threshold, na.rm = TRUE) else 0

  radial_profile <- radial_profile_summary(gray, center_x, center_y, dish_radius_px, bins = 30)
  radial_means <- radial_profile$meanIntensity
  ring_spacing_mm <- if (length(radial_means) >= 2) {
    radius_fraction <- radial_profile$radiusFraction
    peak_idx <- which.max(stats::filter(radial_means, rep(1 / 3, 3), sides = 2, circular = TRUE))
    if (length(peak_idx)) {
      radius_fraction[max(1, peak_idx[1])] * dish_radius_px * pixel_to_mm
    } else {
      0
    }
  } else {
    0
  }

  crack_threshold <- safe_quantile(colony_values, 0.12, default = threshold)
  crack_pixels <- colony_mask & gray <= crack_threshold
  crack_coverage_pct <- if (sum(colony_mask) > 0) 100 * sum(crack_pixels & colony_mask) / sum(colony_mask) else 0

  qc_status <- if (area_fraction < 0.02 || area_fraction > 0.85) "warning" else "pass"
  qc_notes <- if (qc_status == "warning") {
    "Heuristic check flagged the colony area as unusually small or large."
  } else {
    "Heuristic check passed."
  }

  colony_polygon <- mask_to_polygon(colony_mask, scale_to = 1000)
  crack_components <- connected_components(crack_pixels & colony_mask, min_size = 12)
  crack_segments <- lapply(crack_components, function(component) {
    segment <- component_to_segment(component, width = width, height = height, scale_to = 1000)
    lapply(segment, function(point) {
      list(x = unname(point$x), y = unname(point$y))
    })
  })
  crack_count <- length(crack_components)
  crack_length_mm <- if (crack_count > 0) {
    sum(vapply(crack_components, nrow, integer(1))) * pixel_to_mm * 0.7
  } else {
    0
  }
  internal_band_description <- summarise_internal_band(center_mean, middle_mean, outer_mean, crack_coverage_pct)

  list(
    id = paste0(tools::file_path_sans_ext(basename(path)), "-", as.integer(round(area_px)), "-", as.integer(round(diameter_mm * 100))),
    filename = basename(path),
    day = guess_day_from_filename(path),
    imageUrl = normalizePath(path, winslash = "/", mustWork = FALSE),
    pixelToMm = pixel_to_mm,
    morphology = list(
      areaMm2 = area_mm2,
      equivalentRadiusMm = equivalent_radius_mm,
      diameterMm = diameter_mm,
      perimeterMm = perimeter_mm,
      circularity = circularity,
      eccentricity = eccentricity,
      edgeRoughness = edge_roughness
    ),
    texture = list(
      contrast = contrast,
      correlation = correlation,
      energy = energy,
      homogeneity = homogeneity,
      entropy = texture_entropy,
      centerToEdgeDelta = center_edge_delta,
      densityIndex = density_index,
      radialZonation = list(
        core = center_mean,
        middle = middle_mean,
        outer = outer_mean
      )
    ),
    cracks = list(
      count = crack_count,
      totalLengthMm = crack_length_mm,
      coveragePct = crack_coverage_pct,
      proportionalCoveragePct = crack_coverage_pct,
      internalBandSummary = internal_band_description
    ),
    kinematics = list(
      radialVelocity = NA_real_,
      areaGrowthRate = NA_real_,
      relativeGrowthRate = NA_real_,
      radialAcceleration = NA_real_
    ),
    qcStatus = qc_status,
    qcNotes = qc_notes,
    rawAnalysis = list(
      dish_center = list(x = center_x, y = center_y),
      dish_radius = dish_radius_px,
      colony_polygon = lapply(seq_len(nrow(colony_polygon)), function(i) {
        list(x = unname(colony_polygon[i, "x"]), y = unname(colony_polygon[i, "y"]))
      }),
      cracks = crack_segments,
      internal_band_description = internal_band_description,
      radial_profile = list(
        radiusFraction = radial_profile$radiusFraction,
        radiusMm = radial_profile$radiusMm,
        meanIntensity = radial_profile$meanIntensity,
        ringSpacingMm = ring_spacing_mm,
        centerToEdgeDelta = center_edge_delta,
        densityIndex = density_index
      ),
      crack_analysis = list(
        analysis_band_mm = dish_radius_px * pixel_to_mm * 0.25,
        analysis_threshold = crack_threshold,
        crack_area_px = sum(crack_pixels & colony_mask),
        total_length_px = crack_count * 12,
        num_segments = crack_count,
        mean_segment_length_px = if (crack_count > 0) (sum(crack_pixels & colony_mask) / crack_count) else 0
      ),
      morphology_estimates = list(
        area_mm2 = area_mm2,
        perimeter_mm = perimeter_mm,
        diameter_mm = diameter_mm
      ),
      segmentation_diagnostics = list(
        petri_dish_diameter_mm = plate_diameter_mm,
        initial_mask_area_px = area_px,
        classical_mask_area_px = area_px,
        unet_mask_area_px = NA_real_,
        hybrid_pre_sam_area_px = area_px,
        refined_mask_area_px = area_px,
        refinement_area_ratio = 1,
        refinement_iou_with_classical_mask = 1,
        refinement_centroid_shift_px = 0,
        classical_unet_iou = NA_real_,
        classical_unet_size_ratio = NA_real_,
        hybrid_strategy = "legacy-r-heuristic",
        hybrid_strategy_reason = "Legacy R-only heuristic is retained only as a fallback helper.",
        base_hybrid_area_px = area_px,
        sam_decision = "not used",
        sam_error = "SAM is not part of the legacy R-only fallback.",
        sam_area_px = NA_real_,
        sam_final_area_px = NA_real_,
        sam_iou_with_base = NA_real_,
        sam_iou_with_classical = NA_real_,
        sam_area_ratio_vs_base = NA_real_
      )
    )
  )
}

