slugify <- function(value) {
  value <- tolower(trimws(as.character(value)))
  value <- gsub("[^a-z0-9]+", "_", value)
  value <- gsub("^_+|_+$", "", value)
  value
}

ensure_dir <- function(path) {
  dir.create(path, recursive = TRUE, showWarnings = FALSE)
  normalizePath(path, winslash = "/", mustWork = FALSE)
}

default_run_id <- function() {
  format(Sys.time(), "%Y%m%dT%H%M%SZ", tz = "UTC")
}

guess_day_from_filename <- function(filename) {
  filename <- basename(filename)
  match <- regexec("day([0-9]+)", filename, ignore.case = TRUE)
  value <- regmatches(filename, match)[[1]]
  if (length(value) >= 2) {
    return(as.integer(value[2]))
  }
  match <- regexec("d([0-9]+)", filename, ignore.case = TRUE)
  value <- regmatches(filename, match)[[1]]
  if (length(value) >= 2) {
    return(as.integer(value[2]))
  }
  match <- regexec("([0-9]+)", filename)
  value <- regmatches(filename, match)[[1]]
  if (length(value) >= 2) {
    return(as.integer(value[2]))
  }
  NA_integer_
}

circle_mask <- function(width, height, center_x, center_y, radius_px) {
  xx <- matrix(rep(seq_len(width), each = height), nrow = height, ncol = width)
  yy <- matrix(rep(seq_len(height), times = width), nrow = height, ncol = width)
  (xx - center_x)^2 + (yy - center_y)^2 <= radius_px^2
}

read_grayscale_matrix <- function(path) {
  ext <- tolower(tools::file_ext(path))
  if (ext == "png") {
    img <- png::readPNG(path)
    if (length(dim(img)) == 3) {
      img <- img[, , 1]
    }
    return(as.matrix(img))
  }

  if (ext %in% c("jpg", "jpeg")) {
    if (requireNamespace("magick", quietly = TRUE)) {
      img <- magick::image_read(path)
      gray <- magick::image_convert(img, colorspace = "gray")
      data <- magick::image_data(gray, channels = "gray")
      width <- dim(data)[2]
      height <- dim(data)[3]
      return(matrix(as.integer(data[1, , ]), nrow = height, ncol = width, byrow = TRUE) / 255)
    }
    if (requireNamespace("jpeg", quietly = TRUE)) {
      img <- jpeg::readJPEG(path)
      if (length(dim(img)) == 3) {
        img <- img[, , 1]
      }
      return(as.matrix(img))
    }
  }

  if (ext %in% c("tif", "tiff")) {
    if (requireNamespace("magick", quietly = TRUE)) {
      img <- magick::image_read(path)
      gray <- magick::image_convert(img, colorspace = "gray")
      data <- magick::image_data(gray, channels = "gray")
      width <- dim(data)[2]
      height <- dim(data)[3]
      return(matrix(as.integer(data[1, , ]), nrow = height, ncol = width, byrow = TRUE) / 255)
    }
    if (requireNamespace("tiff", quietly = TRUE)) {
      img <- tiff::readTIFF(path, all = FALSE, native = FALSE)
      if (length(dim(img)) == 3) {
        img <- img[, , 1]
      }
      return(as.matrix(img))
    }
  }

  if (ext %in% c("jpg", "jpeg", "bmp", "tif", "tiff", "webp")) {
    fallback_dir <- tempfile("grayleafspot-image-", tmpdir = getwd())
    dir.create(fallback_dir, recursive = TRUE, showWarnings = FALSE)
    on.exit(unlink(fallback_dir, recursive = TRUE, force = TRUE), add = TRUE)
    sips <- Sys.which("sips")
    if (!nzchar(sips)) {
      stop("Image support requires magick, jpeg, or tiff on this platform.")
    }
    status <- system2(sips, c("-s", "format", "png", path, "--out", fallback_dir), stdout = FALSE, stderr = FALSE)
    converted_candidates <- list.files(fallback_dir, pattern = "[.]png$", full.names = TRUE)
    if (!identical(status, 0L) || !length(converted_candidates)) {
      stop("Failed to convert image to PNG for grayscale reading.")
    }
    converted <- converted_candidates[[1]]
    img <- png::readPNG(converted)
    if (length(dim(img)) == 3) {
      img <- img[, , 1]
    }
    return(as.matrix(img))
  }

  stop("Unsupported image format.")
}

safe_quantile <- function(x, probs, default = 0) {
  x <- x[is.finite(x)]
  if (!length(x)) {
    return(default)
  }
  as.numeric(stats::quantile(x, probs = probs, na.rm = TRUE, names = FALSE))
}

shannon_entropy <- function(x, bins = 32) {
  x <- x[is.finite(x)]
  if (!length(x)) {
    return(0)
  }
  breaks <- seq(0, 1, length.out = bins + 1)
  histo <- graphics::hist(x, breaks = breaks, plot = FALSE, include.lowest = TRUE, right = FALSE)
  p <- histo$counts / sum(histo$counts)
  p <- p[p > 0]
  if (!length(p)) {
    return(0)
  }
  -sum(p * log2(p))
}

normalize_grayleafspot_results <- function(data) {
  data <- tibble::as_tibble(data)
  aliases <- list(
    area = "area_mm2",
    radius = "radius_mm",
    diameter = "diameter_mm",
    perimeter = "perimeter_mm",
    entropy = "texture_entropy",
    center_edge_delta = "center_to_edge_intensity_delta",
    crack_coverage_pct = "crack_coverage_pct",
    radial_velocity_mm_per_day = "radial_velocity_mm_per_day",
    area_growth_rate_mm2_per_day = "area_growth_rate_mm2_per_day",
    relative_growth_rate_per_day = "relative_growth_rate_per_day"
  )
  for (alias in names(aliases)) {
    source <- aliases[[alias]]
    if (alias %in% names(data)) {
      next
    }
    if (source %in% names(data)) {
      data[[alias]] <- data[[source]]
    }
  }
  if ("texture_entropy" %in% names(data) && !"entropy" %in% names(data)) {
    data$entropy <- data$texture_entropy
  }
  if ("center_to_edge_intensity_delta" %in% names(data) && !"center_edge_delta" %in% names(data)) {
    data$center_edge_delta <- data$center_to_edge_intensity_delta
  }
  if ("area_mm2" %in% names(data) && !"area" %in% names(data)) {
    data$area <- data$area_mm2
  }
  if ("radius_mm" %in% names(data) && !"radius" %in% names(data)) {
    data$radius <- data$radius_mm
  }
  if ("diameter_mm" %in% names(data) && !"diameter" %in% names(data)) {
    data$diameter <- data$diameter_mm
  }
  if ("perimeter_mm" %in% names(data) && !"perimeter" %in% names(data)) {
    data$perimeter <- data$perimeter_mm
  }
  data
}

mask_to_polygon <- function(mask, scale_to = 1000) {
  if (!any(mask)) {
    return(list())
  }
  z <- ifelse(mask, 1, 0)
  old_limit <- getOption("max.contour.segments")
  on.exit(options(max.contour.segments = old_limit), add = TRUE)
  options(max.contour.segments = max(50000, as.integer(old_limit %||% 25000)))
  contours <- suppressWarnings(
    grDevices::contourLines(
      x = seq_len(ncol(z)),
      y = seq_len(nrow(z)),
      z = z,
      levels = 0.5
    )
  )
  if (!length(contours)) {
    return(list())
  }
  lengths <- vapply(contours, function(item) length(item$x), numeric(1))
  contour <- contours[[which.max(lengths)]]
  x <- contour$x
  y <- contour$y
  cbind(
    x = (x / max(ncol(mask), 1)) * scale_to,
    y = (y / max(nrow(mask), 1)) * scale_to
  )
}

connected_components <- function(mask, min_size = 1) {
  mask <- as.matrix(mask)
  visited <- matrix(FALSE, nrow(mask), ncol(mask))
  dims <- dim(mask)
  components <- list()
  directions <- expand.grid(dx = -1:1, dy = -1:1)
  directions <- directions[!(directions$dx == 0 & directions$dy == 0), , drop = FALSE]

  for (row in seq_len(dims[1])) {
    for (col in seq_len(dims[2])) {
      if (!mask[row, col] || visited[row, col]) {
        next
      }
      queue_row <- integer()
      queue_col <- integer()
      head <- 1L
      queue_row <- c(queue_row, row)
      queue_col <- c(queue_col, col)
      visited[row, col] <- TRUE
      coords <- matrix(numeric(), ncol = 2)
      while (head <= length(queue_row)) {
        r <- queue_row[head]
        c <- queue_col[head]
        head <- head + 1L
        coords <- rbind(coords, c(r, c))
        for (i in seq_len(nrow(directions))) {
          nr <- r + directions$dy[i]
          nc <- c + directions$dx[i]
          if (nr < 1 || nc < 1 || nr > dims[1] || nc > dims[2]) {
            next
          }
          if (!mask[nr, nc] || visited[nr, nc]) {
            next
          }
          visited[nr, nc] <- TRUE
          queue_row <- c(queue_row, nr)
          queue_col <- c(queue_col, nc)
        }
      }
      if (nrow(coords) >= min_size) {
        components[[length(components) + 1L]] <- coords
      }
    }
  }
  components
}

component_to_segment <- function(coords, width, height, scale_to = 1000) {
  if (!nrow(coords)) {
    return(list())
  }
  coords <- unique(coords)
  x <- coords[, 2]
  y <- coords[, 1]
  if (length(unique(x)) < 2 && length(unique(y)) < 2) {
    point <- list(x = (x[1] / max(width, 1)) * scale_to, y = (y[1] / max(height, 1)) * scale_to)
    return(list(point, point))
  }
  cov_mat <- stats::cov(cbind(x, y))
  eig <- eigen(cov_mat, symmetric = TRUE)
  axis <- eig$vectors[, 1]
  proj <- as.vector(cbind(x - mean(x), y - mean(y)) %*% axis)
  idx <- range(proj, na.rm = TRUE)
  endpoints <- rbind(
    c(mean(x), mean(y)) + idx[1] * axis,
    c(mean(x), mean(y)) + idx[2] * axis
  )
  split(
    data.frame(
      x = (endpoints[, 1] / max(width, 1)) * scale_to,
      y = (endpoints[, 2] / max(height, 1)) * scale_to
    ),
    seq_len(nrow(endpoints))
  )
}

summarise_internal_band <- function(core, middle, outer, crack_coverage_pct) {
  delta_outer_core <- outer - core
  delta_middle_core <- middle - core
  if (crack_coverage_pct > 10 && delta_outer_core > 0) {
    "Crack burden is elevated with a lighter outer band than the core."
  } else if (delta_outer_core < -0.05) {
    "Outer band is darker than the core, suggesting peripheral remodeling."
  } else if (delta_middle_core > 0.05) {
    "Middle band is brighter than the core, suggesting a radial transition."
  } else {
    "Radial bands are subtle and broadly uniform."
  }
}

estimate_perimeter_px <- function(mask) {
  if (!any(mask)) {
    return(0)
  }
  up <- rbind(FALSE, mask[-nrow(mask), , drop = FALSE])
  down <- rbind(mask[-1, , drop = FALSE], FALSE)
  left <- cbind(FALSE, mask[, -ncol(mask), drop = FALSE])
  right <- cbind(mask[, -1, drop = FALSE], FALSE)
  edge <- mask & (!up | !down | !left | !right)
  sum(edge)
}

eccentricity_from_mask <- function(mask) {
  coords <- which(mask, arr.ind = TRUE)
  if (!nrow(coords)) {
    return(0)
  }
  y <- coords[, 1]
  x <- coords[, 2]
  cov_mat <- stats::cov(cbind(x, y))
  eig <- eigen(cov_mat, symmetric = TRUE, only.values = TRUE)$values
  eig <- sort(pmax(eig, 0), decreasing = TRUE)
  if (length(eig) < 2 || eig[1] <= 0) {
    return(0)
  }
  sqrt(1 - eig[2] / eig[1])
}

radial_profile_summary <- function(gray, center_x, center_y, radius_px, bins = 30) {
  height <- nrow(gray)
  width <- ncol(gray)
  xx <- matrix(rep(seq_len(width), each = height), nrow = height, ncol = width)
  yy <- matrix(rep(seq_len(height), times = width), nrow = height, ncol = width)
  dist <- sqrt((xx - center_x)^2 + (yy - center_y)^2)
  scaled <- pmin(dist / radius_px, 1)
  breaks <- seq(0, 1, length.out = bins + 1)
  means <- vapply(seq_len(bins), function(i) {
    idx <- scaled >= breaks[i] & scaled < breaks[i + 1]
    if (!any(idx)) {
      return(NA_real_)
    }
    mean(gray[idx], na.rm = TRUE)
  }, numeric(1))
  mids <- (breaks[-1] + breaks[-length(breaks)]) / 2
  list(
    radiusFraction = mids,
    radiusMm = mids,
    meanIntensity = means
  )
}

annulus_mean <- function(gray, center_x, center_y, radius_px, lower_frac, upper_frac) {
  height <- nrow(gray)
  width <- ncol(gray)
  xx <- matrix(rep(seq_len(width), each = height), nrow = height, ncol = width)
  yy <- matrix(rep(seq_len(height), times = width), nrow = height, ncol = width)
  dist <- sqrt((xx - center_x)^2 + (yy - center_y)^2)
  idx <- dist >= radius_px * lower_frac & dist < radius_px * upper_frac
  if (!any(idx)) {
    return(0)
  }
  mean(gray[idx], na.rm = TRUE)
}
