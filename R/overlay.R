# Internal: resolve a single per-image raw result record from `run`.
#
# `run` may be a `grayleafspot_run` object (records live in `$raw_results`),
# a plain list of such records, or a single record itself (identified by
# having a `rawAnalysis` element).
grayleafspot_overlay_record <- function(run, id) {
  if (is.list(run) && !is.null(run$rawAnalysis)) {
    return(run)
  }
  records <- if (inherits(run, "grayleafspot_run")) run$raw_results else run
  if (!length(records)) {
    stop("`run` has no raw per-image records to overlay (`raw_results` is empty).")
  }
  if (is.null(id)) {
    return(records[[1]])
  }
  match_idx <- vapply(records, function(r) {
    isTRUE(identical(r$id, id)) || isTRUE(identical(r$filename, id))
  }, logical(1))
  if (!any(match_idx)) {
    stop("No record found with id/filename matching '", id, "'.")
  }
  records[[which(match_idx)[1]]]
}

# Internal: rescale a list of {x, y} points (normalized 0-1000, as stored in
# `rawAnalysis$colony_polygon` / `rawAnalysis$cracks`) to pixel coordinates.
grayleafspot_overlay_points_to_px <- function(points, width_px, height_px) {
  x_norm <- vapply(points, function(p) as.numeric(p$x), numeric(1))
  y_norm <- vapply(points, function(p) as.numeric(p$y), numeric(1))
  list(x = x_norm / 1000 * width_px, y = y_norm / 1000 * height_px)
}

# Internal: draw a (optionally closed) polyline on an EBImage Image by
# rasterizing each segment via linear interpolation and setting pixel values
# directly - avoids adding a polygon-rasterization dependency (raster/sp) for
# what is otherwise a thin outline, consistent with the manual raster/vector
# geometry already used in mask_to_polygon()/connected_components().
grayleafspot_draw_polyline <- function(img, x_px, y_px, col, closed = TRUE) {
  if (length(x_px) < 2) {
    return(img)
  }
  if (closed) {
    x_px <- c(x_px, x_px[1])
    y_px <- c(y_px, y_px[1])
  }
  width_px <- dim(img)[1]
  height_px <- dim(img)[2]
  rgb <- as.numeric(grDevices::col2rgb(col)) / 255
  for (i in seq_len(length(x_px) - 1)) {
    seg_len <- sqrt((x_px[i + 1] - x_px[i])^2 + (y_px[i + 1] - y_px[i])^2)
    n <- max(2L, ceiling(seg_len))
    xs <- pmin(pmax(round(seq(x_px[i], x_px[i + 1], length.out = n)), 1), width_px)
    ys <- pmin(pmax(round(seq(y_px[i], y_px[i + 1], length.out = n)), 1), height_px)
    for (ch in seq_along(rgb)) {
      img[cbind(xs, ys, ch)] <- rgb[ch]
    }
  }
  img
}

#' Overlay detected regions of interest on a plate image
#'
#' Draws the detected dish boundary, colony outline, and any detected crack
#' segments on top of the original plate photograph, using
#' [EBImage::readImage()] and EBImage's drawing primitives. This lets you
#' visually verify that automated segmentation and crack detection were
#' computed as expected, rather than trusting the summary statistics alone.
#'
#' @param run A `grayleafspot_run` object (see [grayleafspot_analyze()],
#'   [read_grayleafspot_results()]), a plain list of per-image raw result
#'   records, or a single record (a list with a `rawAnalysis` element, as
#'   produced internally by the analysis engines).
#' @param id Optional character. `id` or `filename` of the image to overlay,
#'   matched against the records in `run`. Defaults to the first record.
#' @param image_path Optional character. Explicit path to the source image.
#'   Falls back to the record's stored `imageUrl`, which is only a resolvable
#'   local file path for runs produced by the pure-R fallback engine; for
#'   runs produced by the Python/basilisk pipeline, pass this explicitly
#'   (e.g. a file inside the original `input_dir`).
#' @param show_dish,show_colony,show_cracks Logical. Which overlays to draw.
#' @param dish_col,colony_col,crack_col Character. Colors for each overlay,
#'   passed to [grDevices::col2rgb()].
#' @return An [EBImage::Image] with the requested overlays drawn on it.
#'   Display with `EBImage::display()` or save with `EBImage::writeImage()`.
#' @examples
#' img_dir <- system.file("extdata", "testdata", "06FEB", package = "grayleafspotr")
#' image_file <- list.files(img_dir, full.names = TRUE)[1]
#' record <- grayleafspotr:::analyze_grayleafspot_image(image_file)
#' overlay <- plot_grayleafspot_overlay(record)
#' @export
plot_grayleafspot_overlay <- function(run, id = NULL, image_path = NULL,
                                       show_dish = TRUE, show_colony = TRUE, show_cracks = TRUE,
                                       dish_col = "yellow", colony_col = "red", crack_col = "cyan") {
  record <- grayleafspot_overlay_record(run, id)
  raw <- record$rawAnalysis %||% list()

  path <- image_path %||% record$imageUrl
  if (is.null(path) || !nzchar(path) || !file.exists(path)) {
    stop(
      "Could not locate the source image for this record. Pass `image_path` ",
      "explicitly (pipeline runs produced by the Python engine do not store ",
      "a locally resolvable image path)."
    )
  }

  img <- EBImage::readImage(path)
  if (EBImage::colorMode(img) != EBImage::Color) {
    img <- EBImage::toRGB(img)
  }
  width_px <- dim(img)[1]
  height_px <- dim(img)[2]

  if (show_dish && !is.null(raw$dish_center) && !is.null(raw$dish_radius)) {
    cx <- as.numeric(raw$dish_center$x) / 1000 * width_px
    cy <- as.numeric(raw$dish_center$y) / 1000 * height_px
    r <- as.numeric(raw$dish_radius) / 1000 * width_px
    img <- EBImage::drawCircle(img, x = cx, y = cy, radius = r, col = dish_col, fill = FALSE)
  }

  if (show_colony && length(raw$colony_polygon)) {
    pts <- grayleafspot_overlay_points_to_px(raw$colony_polygon, width_px, height_px)
    img <- grayleafspot_draw_polyline(img, pts$x, pts$y, col = colony_col, closed = TRUE)
  }

  if (show_cracks && length(raw$cracks)) {
    for (segment in raw$cracks) {
      pts <- grayleafspot_overlay_points_to_px(segment, width_px, height_px)
      img <- grayleafspot_draw_polyline(img, pts$x, pts$y, col = crack_col, closed = FALSE)
    }
  }

  img
}
