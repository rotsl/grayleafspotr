MODEL_URL <- "https://huggingface.co/rotsl/grayleafspot-segmentation/resolve/main/best_area_w_0.7.pt"
MODEL_FILENAME <- "best_area_w_0.7.pt"

#' Download the SmallUNet segmentation model
#'
#' Fetches `best_area_w_0.7.pt` from HuggingFace and caches it on disk. On
#' subsequent calls the cached file is returned immediately without re-downloading.
#'
#' The function looks for the model in this order:
#' 1. `models/best_area_w_0.7.pt` relative to the package root (development).
#' 2. The per-user R cache directory (`tools::R_user_dir("grayleafspotr", "cache")`).
#' 3. Downloads from HuggingFace and saves to the user cache directory.
#'
#' @param force Logical. Re-download even if a cached copy already exists.
#' @param quiet Logical. Suppress progress messages.
#' @return Invisible character string: absolute path to the downloaded model file.
#' @export
grayleafspot_download_model <- function(force = FALSE, quiet = FALSE) {
  pkg_root <- grayleafspot_package_root()
  local_path <- file.path(pkg_root, "models", MODEL_FILENAME)
  if (!force && file.exists(local_path)) {
    if (!quiet) message("Model found at: ", local_path)
    return(invisible(local_path))
  }

  cache_dir <- tools::R_user_dir("grayleafspotr", "cache")
  cache_path <- file.path(cache_dir, MODEL_FILENAME)
  if (!force && file.exists(cache_path)) {
    if (!quiet) message("Model found in cache: ", cache_path)
    return(invisible(cache_path))
  }

  dir.create(cache_dir, recursive = TRUE, showWarnings = FALSE)
  if (!quiet) message("Downloading SmallUNet model to: ", cache_path, "\n  Source: ", MODEL_URL)
  utils::download.file(MODEL_URL, destfile = cache_path, mode = "wb", quiet = quiet)
  if (!file.exists(cache_path)) {
    stop("Model download failed. Check your internet connection and try again.")
  }
  if (!quiet) message("Download complete.")
  invisible(cache_path)
}

#' Return the path to the SmallUNet model, downloading it if necessary
#'
#' Used internally by the analysis pipeline. If the model is not found locally,
#' `grayleafspot_download_model()` is called automatically.
#'
#' @param quiet Logical. Suppress download progress messages.
#' @return Character string: absolute path to `best_area_w_0.7.pt`.
#' @keywords internal
grayleafspot_model_path <- function(quiet = FALSE) {
  pkg_root <- grayleafspot_package_root()
  local_path <- file.path(pkg_root, "models", MODEL_FILENAME)
  if (file.exists(local_path)) {
    return(local_path)
  }
  cache_dir <- tools::R_user_dir("grayleafspotr", "cache")
  cache_path <- file.path(cache_dir, MODEL_FILENAME)
  if (file.exists(cache_path)) {
    return(cache_path)
  }
  grayleafspot_download_model(quiet = quiet)
}
