#' Plot colony expansion over time
#'
#' Draws equivalent colony radius (mm) against time (days) as a line + point
#' plot using the `ggplot2` theme_minimal style.
#'
#' @param x A `grayleafspot_run` object, data frame, or list accepted by
#'   [as_grayleafspot_growth_data()].
#' @return A `ggplot2` object.
#' @export
plot_colony_expansion <- function(x) {
  data <- as_grayleafspot_growth_data(x)
  ggplot2::ggplot(data, ggplot2::aes(x = day, y = radius_mm)) +
    ggplot2::geom_line(colour = "#059669", linewidth = 1.1) +
    ggplot2::geom_point(colour = "#059669", size = 2) +
    ggplot2::labs(
      title = "Colony expansion",
      subtitle = "Equivalent colony radius",
      x = "Time (days)",
      y = "Radius (mm)"
    ) +
    ggplot2::theme_minimal(base_size = 12)
}

#' Plot relative growth rate and edge roughness
#'
#' @param x A `grayleafspot_run` object or data accepted by
#'   [as_grayleafspot_growth_data()].
#' @return A `ggplot2` object.
#' @export
plot_growth_roughness <- function(x) {
  data <- as_grayleafspot_growth_data(x)
  ggplot2::ggplot(data, ggplot2::aes(x = day)) +
    ggplot2::geom_line(ggplot2::aes(y = relative_growth_rate_per_day, colour = "Relative growth rate"), linewidth = 1.1) +
    ggplot2::geom_point(ggplot2::aes(y = relative_growth_rate_per_day, colour = "Relative growth rate"), size = 2) +
    ggplot2::geom_line(ggplot2::aes(y = edge_roughness, colour = "Edge roughness"), linewidth = 1.1) +
    ggplot2::geom_point(ggplot2::aes(y = edge_roughness, colour = "Edge roughness"), size = 2) +
    ggplot2::scale_colour_manual(values = c("Relative growth rate" = "#ea580c", "Edge roughness" = "#b45309")) +
    ggplot2::labs(title = "Relative growth and edge roughness", x = "Time (days)", y = "Growth / roughness", colour = NULL) +
    ggplot2::theme_minimal(base_size = 12) +
    ggplot2::theme(legend.position = "bottom")
}

#' Plot crack coverage and crack count over time
#'
#' @param x A `grayleafspot_run` object or data accepted by
#'   [as_grayleafspot_growth_data()].
#' @return A `ggplot2` object.
#' @export
plot_stress_remodeling <- function(x) {
  data <- as_grayleafspot_growth_data(x)
  ggplot2::ggplot(data, ggplot2::aes(x = day)) +
    ggplot2::geom_line(ggplot2::aes(y = crack_coverage_pct, colour = "Crack coverage"), linewidth = 1.1) +
    ggplot2::geom_point(ggplot2::aes(y = crack_coverage_pct, colour = "Crack coverage"), size = 2) +
    ggplot2::geom_line(ggplot2::aes(y = crack_count, colour = "Crack count"), linewidth = 1.1) +
    ggplot2::geom_point(ggplot2::aes(y = crack_count, colour = "Crack count"), size = 2) +
    ggplot2::scale_colour_manual(values = c("Crack coverage" = "#f59e0b", "Crack count" = "#7c2d12")) +
    ggplot2::labs(title = "Stress remodeling", x = "Time (days)", y = "Coverage / count", colour = NULL) +
    ggplot2::theme_minimal(base_size = 12) +
    ggplot2::theme(legend.position = "bottom")
}

#' Plot texture entropy and center-to-edge intensity delta over time
#'
#' @param x A `grayleafspot_run` object or data accepted by
#'   [as_grayleafspot_growth_data()].
#' @return A `ggplot2` object.
#' @export
plot_texture_organization <- function(x) {
  data <- as_grayleafspot_growth_data(x)
  ggplot2::ggplot(data, ggplot2::aes(x = day)) +
    ggplot2::geom_line(ggplot2::aes(y = entropy, colour = "Entropy"), linewidth = 1.1) +
    ggplot2::geom_point(ggplot2::aes(y = entropy, colour = "Entropy"), size = 2) +
    ggplot2::geom_line(ggplot2::aes(y = center_edge_delta, colour = "Center-to-edge delta"), linewidth = 1.1) +
    ggplot2::geom_point(ggplot2::aes(y = center_edge_delta, colour = "Center-to-edge delta"), size = 2) +
    ggplot2::scale_colour_manual(values = c("Entropy" = "#0f766e", "Center-to-edge delta" = "#14b8a6")) +
    ggplot2::labs(title = "Texture organization", x = "Time (days)", y = "Texture signal", colour = NULL) +
    ggplot2::theme_minimal(base_size = 12) +
    ggplot2::theme(legend.position = "bottom")
}

#' Scatter plot of colony shape vs crack stress
#'
#' Plots eccentricity against crack coverage percentage, with point size
#' proportional to colony diameter and colour encoding time (day).
#'
#' @param x A `grayleafspot_run` object or data accepted by
#'   [as_grayleafspot_growth_data()].
#' @return A `ggplot2` object.
#' @export
plot_shape_vs_stress <- function(x) {
  data <- as_grayleafspot_growth_data(x)
  ggplot2::ggplot(data, ggplot2::aes(x = eccentricity, y = crack_coverage_pct, size = diameter_mm, colour = day)) +
    ggplot2::geom_point(alpha = 0.85) +
    ggplot2::scale_colour_gradient(low = "#4f46e5", high = "#0f766e") +
    ggplot2::labs(title = "Shape vs stress", x = "Eccentricity", y = "Crack coverage (%)", colour = "Day", size = "Diameter") +
    ggplot2::theme_minimal(base_size = 12)
}

#' Plot radial growth rate and colony area by plate over time
#'
#' Produces a faceted panel with colony area (mm\eqn{^2}) on one facet and
#' radial growth rate (mm/day) on the other.  When each plate appears only once
#' in the data, points from all plates are connected in day order.
#'
#' @param x A `grayleafspot_run` object or data accepted by
#'   [as_grayleafspot_growth_data()].
#' @return A `ggplot2` object.
#' @export
plot_radial_growth_area <- function(x) {
  data <- as_grayleafspot_growth_data(x)
  required <- c("day", "filename", "area_mm2", "radial_velocity_mm_per_day")
  if (!all(required %in% names(data)) || nrow(data) < 1) {
    return(ggplot2::ggplot() + ggplot2::annotate("text", x = 0.5, y = 0.5, label = "No radial growth data available") + ggplot2::theme_void())
  }

  plot_data <- rbind(
    data.frame(
      day = data$day,
      plate = as.character(data$filename),
      metric = "Radial area (mm^2)",
      value = data$area_mm2,
      stringsAsFactors = FALSE
    ),
    data.frame(
      day = data$day,
      plate = as.character(data$filename),
      metric = "Radial growth (mm/day)",
      value = data$radial_velocity_mm_per_day,
      stringsAsFactors = FALSE
    )
  )
  plot_data <- plot_data[is.finite(plot_data$day) & is.finite(plot_data$value), , drop = FALSE]
  if (!nrow(plot_data)) {
    return(ggplot2::ggplot() + ggplot2::annotate("text", x = 0.5, y = 0.5, label = "No radial growth data available") + ggplot2::theme_void())
  }
  plot_data$metric <- factor(plot_data$metric, levels = c("Radial area (mm^2)", "Radial growth (mm/day)"))
  plot_data <- plot_data[order(plot_data$metric, plot_data$plate, plot_data$day), , drop = FALSE]

  counts <- stats::aggregate(day ~ metric + plate, data = plot_data, FUN = length)
  names(counts)[names(counts) == "day"] <- "n"
  line_data <- merge(plot_data, counts[counts$n >= 2, c("metric", "plate")], by = c("metric", "plate"))
  line_data <- line_data[order(line_data$metric, line_data$plate, line_data$day), , drop = FALSE]
  if (!nrow(line_data)) {
    line_data <- plot_data[order(plot_data$metric, plot_data$day), , drop = FALSE]
    line_data$plate <- as.character(line_data$metric)
  }

  ggplot2::ggplot(plot_data, ggplot2::aes(x = day, y = value, colour = plate, group = plate)) +
    ggplot2::geom_line(
      data = line_data,
      ggplot2::aes(x = day, y = value, colour = plate, group = plate),
      linewidth = 1.1
    ) +
    ggplot2::geom_point(size = 2) +
    ggplot2::facet_wrap(~metric, scales = "free_y", ncol = 1) +
    ggplot2::labs(title = "Radial growth and area by plate", x = "Time (days)", y = NULL, colour = "Plate") +
    ggplot2::theme_minimal(base_size = 12) +
    ggplot2::theme(legend.position = "bottom")
}

#' Pearson correlation heatmap of numeric morphology features
#'
#' @param x A `grayleafspot_run` object or data accepted by
#'   [as_grayleafspot_growth_data()].
#' @return A `ggplot2` object.
#' @export
plot_feature_heatmap <- function(x) {
  data <- as_grayleafspot_growth_data(x)
  cols <- c("area_mm2", "radius_mm", "diameter_mm", "perimeter_mm", "circularity", "eccentricity", "edge_roughness", "entropy", "center_edge_delta", "density_index", "crack_count", "crack_coverage_pct", "relative_growth_rate_per_day")
  cols <- cols[cols %in% names(data)]
  if (nrow(data) < 2 || length(cols) < 2) {
    return(ggplot2::ggplot() + ggplot2::annotate("text", x = 0.5, y = 0.5, label = "Need at least two images") + ggplot2::theme_void())
  }
  numeric_data <- data[, cols, drop = FALSE]
  numeric_data <- numeric_data[vapply(numeric_data, is.numeric, logical(1))]
  if (length(numeric_data) < 2) {
    return(ggplot2::ggplot() + ggplot2::annotate("text", x = 0.5, y = 0.5, label = "Need at least two varying features") + ggplot2::theme_void())
  }
  spreads <- vapply(numeric_data, stats::sd, numeric(1), na.rm = TRUE)
  numeric_data <- numeric_data[is.finite(spreads) & spreads > 0]
  if (length(numeric_data) < 2) {
    return(ggplot2::ggplot() + ggplot2::annotate("text", x = 0.5, y = 0.5, label = "Need at least two varying features") + ggplot2::theme_void())
  }
  corr <- stats::cor(as.data.frame(numeric_data), use = "pairwise.complete.obs")
  corr_df <- as.data.frame(as.table(corr))
  names(corr_df) <- c("x", "y", "value")
  ggplot2::ggplot(corr_df, ggplot2::aes(x = x, y = y, fill = value)) +
    ggplot2::geom_tile(color = "white") +
    ggplot2::scale_fill_gradient2(low = "#dc2626", mid = "white", high = "#2563eb", limits = c(-1, 1)) +
    ggplot2::labs(title = "Feature correlation heatmap", x = NULL, y = NULL, fill = "Pearson r") +
    ggplot2::theme_minimal(base_size = 12) +
    ggplot2::theme(axis.text.x = ggplot2::element_text(angle = 30, hjust = 1))
}

#' Plot the radial intensity profile from the first image in a run
#'
#' Reads the `radialProfile` field from `raw_results`. When called with a plain
#' data frame, the function auto-discovers the most recent `analysis.json` under
#' `outputs/` in the working directory.
#'
#' @param x A `grayleafspot_run` object, a path to a run directory or
#'   `analysis.json`, a list of raw results, or a data frame.
#' @return A `ggplot2` object.
#' @export
plot_radial_profile <- function(x) {
  raw_results <- NULL
  if (inherits(x, "grayleafspot_run")) {
    raw_results <- x$raw_results
    x <- x$results
  } else if (is.character(x) && length(x) == 1) {
    path <- if (endsWith(x, ".json")) x else file.path(x, "analysis.json")
    if (file.exists(path)) raw_results <- jsonlite::read_json(path, simplifyVector = FALSE)
  } else if (is.list(x) && !is.data.frame(x) && !is.null(x$raw_results)) {
    raw_results <- x$raw_results
    x <- x$results
  } else if (is.list(x) && !is.data.frame(x) && length(x) > 0 && !is.null(x[[1]]$rawAnalysis)) {
    raw_results <- x
  }
  if (is.null(raw_results) || !length(raw_results)) {
    candidates <- list.files("outputs", "analysis\\.json$", recursive = TRUE, full.names = TRUE)
    if (length(candidates)) {
      raw_results <- jsonlite::read_json(
        candidates[which.max(file.mtime(candidates))],
        simplifyVector = FALSE
      )
    }
  }
  if (!is.null(raw_results) && length(raw_results)) {
    profile <- raw_results[[1]]$rawAnalysis$radial_profile
    if (is.null(profile)) {
      return(ggplot2::ggplot() + ggplot2::annotate("text", x = 0.5, y = 0.5, label = "No radial profile available") + ggplot2::theme_void())
    }
    profile_df <- tibble::tibble(
      radius_fraction = as.numeric(unlist(profile$radiusFraction %||% numeric(), use.names = FALSE)),
      mean_intensity = as.numeric(unlist(profile$meanIntensity %||% numeric(), use.names = FALSE))
    )
    profile_df <- profile_df[is.finite(profile_df$radius_fraction) & is.finite(profile_df$mean_intensity), , drop = FALSE]
    if (!nrow(profile_df)) {
      return(ggplot2::ggplot() + ggplot2::annotate("text", x = 0.5, y = 0.5, label = "No radial profile available") + ggplot2::theme_void())
    }
    return(
      ggplot2::ggplot(profile_df, ggplot2::aes(x = radius_fraction, y = mean_intensity)) +
        ggplot2::geom_line(colour = "#2563eb", linewidth = 1.1) +
        ggplot2::geom_point(colour = "#2563eb", size = 2) +
        ggplot2::labs(title = "Radial intensity profile", x = "Normalized radius", y = "Mean grayscale intensity") +
        ggplot2::theme_minimal(base_size = 12)
    )
  }
  return(ggplot2::ggplot() + ggplot2::annotate("text", x = 0.5, y = 0.5, label = "No radial profile available") + ggplot2::theme_void())
}

