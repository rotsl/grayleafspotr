#' Coerce a grayleafspot run object to a tidy data frame
#'
#' Extracts the results table from a `grayleafspot_run` object and normalises
#' column aliases so that downstream plotting helpers see a consistent schema.
#'
#' @param x A `grayleafspot_run` object, a plain `data.frame` / `tibble`, or a
#'   list with a `$results` element.
#' @return A [tibble::tibble()] with one row per image.
#' @export
as_grayleafspot_growth_data <- function(x) {
  if (inherits(x, "grayleafspot_run")) {
    return(normalize_grayleafspot_results(x$results))
  }
  if (is.list(x) && !is.data.frame(x) && !is.null(x$results)) {
    return(normalize_grayleafspot_results(x$results))
  }
  normalize_grayleafspot_results(x)
}

flatten_grayleafspot_result <- function(result) {
  list(
    id = result$id %||% "",
    filename = result$filename %||% "",
    day = result$day %||% NA_integer_,
    pixelToMm = result$pixelToMm %||% NA_real_,
    morphology = list(
      areaMm2 = result$morphology$areaMm2 %||% NA_real_,
      equivalentRadiusMm = result$morphology$equivalentRadiusMm %||% NA_real_,
      diameterMm = result$morphology$diameterMm %||% NA_real_,
      perimeterMm = result$morphology$perimeterMm %||% NA_real_,
      circularity = result$morphology$circularity %||% NA_real_,
      eccentricity = result$morphology$eccentricity %||% NA_real_,
      edgeRoughness = result$morphology$edgeRoughness %||% NA_real_
    ),
    texture = list(
      contrast = result$texture$contrast %||% NA_real_,
      correlation = result$texture$correlation %||% NA_real_,
      energy = result$texture$energy %||% NA_real_,
      homogeneity = result$texture$homogeneity %||% NA_real_,
      entropy = result$texture$entropy %||% NA_real_,
      centerToEdgeDelta = result$texture$centerToEdgeDelta %||% NA_real_,
      densityIndex = result$texture$densityIndex %||% NA_real_,
      radialZonation = result$texture$radialZonation %||% list(core = NA_real_, middle = NA_real_, outer = NA_real_)
    ),
    cracks = list(
      count = result$cracks$count %||% NA_real_,
      totalLengthMm = result$cracks$totalLengthMm %||% NA_real_,
      coveragePct = result$cracks$coveragePct %||% NA_real_,
      proportionalCoveragePct = result$cracks$proportionalCoveragePct %||% NA_real_,
      internalBandSummary = result$cracks$internalBandSummary %||% ""
    ),
    kinematics = list(
      radialVelocity = result$kinematics$radialVelocity %||% NA_real_,
      areaGrowthRate = result$kinematics$areaGrowthRate %||% NA_real_,
      relativeGrowthRate = result$kinematics$relativeGrowthRate %||% NA_real_,
      radialAcceleration = result$kinematics$radialAcceleration %||% NA_real_
    ),
    qcStatus = result$qcStatus %||% "warning",
    qcNotes = result$qcNotes %||% "",
    rawAnalysis = result$rawAnalysis %||% list()
  )
}

results_to_csv <- function(results) {
  rows <- lapply(results, function(result) {
    list(
      id = result$id %||% "",
      filename = result$filename %||% "",
      day = result$day %||% NA_integer_,
      area_mm2 = result$morphology$areaMm2 %||% NA_real_,
      radius_mm = result$morphology$equivalentRadiusMm %||% NA_real_,
      diameter_mm = result$morphology$diameterMm %||% NA_real_,
      perimeter_mm = result$morphology$perimeterMm %||% NA_real_,
      circularity = result$morphology$circularity %||% NA_real_,
      eccentricity = result$morphology$eccentricity %||% NA_real_,
      edge_roughness = result$morphology$edgeRoughness %||% NA_real_,
      contrast = result$texture$contrast %||% NA_real_,
      correlation = result$texture$correlation %||% NA_real_,
      energy = result$texture$energy %||% NA_real_,
      homogeneity = result$texture$homogeneity %||% NA_real_,
      entropy = result$texture$entropy %||% NA_real_,
      center_edge_delta = result$texture$centerToEdgeDelta %||% NA_real_,
      density_index = result$texture$densityIndex %||% NA_real_,
      core = result$texture$radialZonation$core %||% NA_real_,
      middle = result$texture$radialZonation$middle %||% NA_real_,
      outer = result$texture$radialZonation$outer %||% NA_real_,
      crack_count = result$cracks$count %||% NA_real_,
      crack_length_mm = result$cracks$totalLengthMm %||% NA_real_,
      crack_coverage_pct = result$cracks$coveragePct %||% NA_real_,
      proportional_crack_coverage_pct = result$cracks$proportionalCoveragePct %||% NA_real_,
      radial_velocity_mm_per_day = result$kinematics$radialVelocity %||% NA_real_,
      area_growth_rate_mm2_per_day = result$kinematics$areaGrowthRate %||% NA_real_,
      relative_growth_rate_per_day = result$kinematics$relativeGrowthRate %||% NA_real_,
      radial_acceleration = result$kinematics$radialAcceleration %||% NA_real_,
      qc_status = result$qcStatus %||% "warning",
      qc_notes = result$qcNotes %||% ""
    )
  })
  dplyr::bind_rows(rows)
}

`%||%` <- function(x, y) {
  if (is.null(x) || length(x) == 0) y else x
}

#' Read a saved grayleafspot run from disk
#'
#' Loads a run directory (containing `analysis.json`, `analysis.csv`, and
#' `manifest.json`) or a single JSON / CSV file and returns a
#' `grayleafspot_run` object.
#'
#' @param path Character. Path to a run directory or to an individual
#'   `analysis.json` / `analysis.csv` file.
#' @return A `grayleafspot_run` object with elements `$run`, `$results`, and
#'   `$raw_results`.
#' @export
read_grayleafspot_results <- function(path) {
  if (length(path) != 1) {
    stop("`path` must be a single file or directory path.")
  }
  if (dir.exists(path)) {
    manifest_path <- file.path(path, "manifest.json")
    json_path <- file.path(path, "analysis.json")
    csv_path <- file.path(path, "analysis.csv")
    manifest <- if (file.exists(manifest_path)) jsonlite::read_json(manifest_path, simplifyVector = TRUE) else list()
    raw_results <- if (file.exists(json_path)) {
      jsonlite::read_json(json_path, simplifyVector = FALSE)
    } else {
      list()
    }
    results <- if (file.exists(csv_path)) {
      readr::read_csv(csv_path, show_col_types = FALSE)
    } else if (length(raw_results)) {
      results_to_csv(raw_results)
    } else {
      tibble::tibble()
    }
    results <- normalize_grayleafspot_results(results)
    return(structure(list(run = manifest, results = results, raw_results = raw_results), class = "grayleafspot_run"))
  }

  ext <- tolower(tools::file_ext(path))
  if (ext == "json") {
    return(jsonlite::read_json(path, simplifyVector = FALSE))
  }
  if (ext == "csv") {
    return(readr::read_csv(path, show_col_types = FALSE))
  }
  stop("Unsupported file type. Use a directory, JSON, or CSV file.")
}

#' Write grayleafspot results to disk
#'
#' Serialises a list of result records to `analysis.json`, `analysis.csv`, and
#' `manifest.json` under `output_dir` and returns a `grayleafspot_run` object.
#'
#' @param results A list of per-image result records (as produced by the Python
#'   pipeline or `analyze_grayleafspot_image()`).
#' @param output_dir Character. Directory to write outputs into (created if
#'   absent).
#' @param engine Character. Engine label stored in the manifest.
#' @param engine_model Character. Engine-model label stored in the manifest.
#' @param run_name Optional character. Human-readable run name for the manifest.
#' @return A `grayleafspot_run` object.
#' @export
write_grayleafspot_results <- function(results, output_dir, engine = "python-local", engine_model = "packaged-python-pipeline", run_name = NULL) {
  ensure_dir(output_dir)
  results <- lapply(results, flatten_grayleafspot_result)
  run_id <- if (is.null(run_name) || !nzchar(run_name)) default_run_id() else slugify(run_name)
  analysis_path <- file.path(output_dir, "analysis.json")
  csv_path <- file.path(output_dir, "analysis.csv")
  manifest_path <- file.path(output_dir, "manifest.json")

  jsonlite::write_json(results, analysis_path, pretty = TRUE, auto_unbox = TRUE, null = "null")
  csv_data <- results_to_csv(results)
  readr::write_csv(csv_data, csv_path)

  manifest <- list(
    id = run_id,
    engine = engine,
    engineModel = engine_model,
    createdAt = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
    outputDir = normalizePath(output_dir, winslash = "/", mustWork = FALSE),
    analysisJson = normalizePath(analysis_path, winslash = "/", mustWork = FALSE),
    analysisCsv = normalizePath(csv_path, winslash = "/", mustWork = FALSE)
  )
  jsonlite::write_json(manifest, manifest_path, pretty = TRUE, auto_unbox = TRUE, null = "null")

  structure(list(run = manifest, results = csv_data, raw_results = results), class = "grayleafspot_run")
}

#' Load the built-in example grayleafspot run
#'
#' Returns the small example run shipped with the package under
#' `inst/extdata/example/`. Useful for exploring the plotting helpers without
#' needing to run the analysis pipeline.
#'
#' @return A `grayleafspot_run` object.
#' @export
example_grayleafspot_results <- function() {
  path <- example_grayleafspot_dir()
  read_grayleafspot_results(path)
}
