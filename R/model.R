MODEL_URL <- "https://huggingface.co/rotsl/grayleafspot-segmentation/resolve/main/best_area_w_0.7.pt"
MODEL_FILENAME <- "best_area_w_0.7.pt"

#' Download the SmallUNet segmentation model
#'
#' Fetches `best_area_w_0.7.pt` from HuggingFace and caches it using
#' [BiocFileCache::BiocFileCache()]. On subsequent calls the cached file is
#' returned immediately without re-downloading.
#'
#' The function looks for the model in this order:
#' 1. `models/best_area_w_0.7.pt` relative to the package root (development).
#' 2. The `BiocFileCache` cache keyed under `grayleafspotr`.
#' 3. Downloads from HuggingFace and adds it to the cache.
#'
#' @param force Logical. Re-download even if a cached copy already exists.
#' @param quiet Logical. Suppress progress messages.
#' @return Invisible character string: absolute path to the downloaded model file.
#' @examples
#' \donttest{
#'   grayleafspot_download_model()
#' }
#' @export
grayleafspot_download_model <- function(force = FALSE, quiet = FALSE) {
  pkg_root <- grayleafspot_package_root()
  local_path <- file.path(pkg_root, "models", MODEL_FILENAME)
  if (!force && file.exists(local_path)) {
    if (!quiet) message("Model found at: ", local_path)
    return(invisible(local_path))
  }

  bfc <- grayleafspot_model_bfc()
  rid <- BiocFileCache::bfcquery(bfc, MODEL_FILENAME, field = "rname", exact = TRUE)$rid

  if (length(rid) && force) {
    BiocFileCache::bfcremove(bfc, rid)
    rid <- character(0)
  }

  if (length(rid)) {
    cache_path <- BiocFileCache::bfcrpath(bfc, rids = rid)
    if (!quiet) message("Model found in cache: ", cache_path)
  } else {
    if (!quiet) message("Downloading SmallUNet model to BiocFileCache.\n  Source: ", MODEL_URL)
    cache_path <- BiocFileCache::bfcadd(
      bfc, rname = MODEL_FILENAME, fpath = MODEL_URL, rtype = "web", download = TRUE
    )
  }

  if (!file.exists(cache_path)) {
    stop("Model download failed. Check your internet connection and try again.")
  }
  if (!quiet) message("Download complete.")
  invisible(unname(cache_path))
}

# Internal: the BiocFileCache instance used to cache the SmallUNet model.
grayleafspot_model_bfc <- function() {
  cache_dir <- tools::R_user_dir("grayleafspotr", "cache")
  BiocFileCache::BiocFileCache(cache_dir, ask = FALSE)
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
  bfc <- grayleafspot_model_bfc()
  rid <- BiocFileCache::bfcquery(bfc, MODEL_FILENAME, field = "rname", exact = TRUE)$rid
  if (length(rid)) {
    return(unname(BiocFileCache::bfcrpath(bfc, rids = rid)))
  }
  grayleafspot_download_model(quiet = quiet)
}
