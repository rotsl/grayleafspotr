grayleafspot_python_module_dir <- function() {
  module_dir <- system.file("python", package = "grayleafspotr")
  if (nzchar(module_dir)) {
    return(module_dir)
  }
  for (candidate in c(file.path("inst", "python"), file.path("grayleafspotr", "inst", "python"))) {
    if (dir.exists(candidate)) {
      return(normalizePath(candidate, winslash = "/", mustWork = FALSE))
    }
  }
  ""
}

grayleafspot_package_root <- function() {
  module_dir <- grayleafspot_python_module_dir()
  candidates <- unique(Filter(nzchar, c(
    if (nzchar(module_dir)) normalizePath(dirname(module_dir), winslash = "/", mustWork = FALSE) else "",
    if (nzchar(module_dir)) normalizePath(dirname(dirname(module_dir)), winslash = "/", mustWork = FALSE) else "",
    getwd(),
    file.path(getwd(), "grayleafspotr")
  )))
  for (candidate in candidates) {
    if (file.exists(file.path(candidate, "DESCRIPTION"))) {
      return(normalizePath(candidate, winslash = "/", mustWork = FALSE))
    }
  }
  if (nzchar(module_dir)) {
    return(normalizePath(dirname(module_dir), winslash = "/", mustWork = FALSE))
  }
  normalizePath(getwd(), winslash = "/", mustWork = FALSE)
}

grayleafspot_resolve_package_path <- function(path) {
  if (is.null(path) || !nzchar(path)) {
    return(path)
  }
  if (grepl("^([A-Za-z]:[\\\\/]|/|~)", path)) {
    return(normalizePath(path, winslash = "/", mustWork = FALSE))
  }
  normalizePath(file.path(grayleafspot_package_root(), path), winslash = "/", mustWork = FALSE)
}

grayleafspot_python_requirements_path <- function() {
  file.path(grayleafspot_python_module_dir(), "requirements.txt")
}

#' Return the Python executable used by the grayleafspot pipeline
#'
#' Resolves the Python interpreter in this priority order: the `python`
#' argument, the `GRAYLEAFSPOTR_PYTHON` environment variable, the
#' `grayleafspotr.python` option, `rvenv_arm_311/bin/python` relative to the
#' working directory, and finally `python3` / `python` from `PATH`.
#'
#' @param python Optional character. Path to a Python executable.
#' @param engine_model Character. Reserved for future use; currently only
#'   `"localunet"` is supported.
#' @return Character string: absolute path to the resolved Python executable.
#' @export
grayleafspot_python_executable <- function(python = NULL, engine_model = "localunet") {
  candidates <- c(
    python,
    Sys.getenv("GRAYLEAFSPOTR_PYTHON", unset = ""),
    getOption("grayleafspotr.python"),
    file.path("rvenv_arm_311", "bin", "python"),
    file.path("grayleafspotr", "rvenv_arm_311", "bin", "python"),
    Sys.which("python3"),
    Sys.which("python")
  )
  candidates <- candidates[nzchar(candidates)]
  for (candidate in candidates) {
    if (file.exists(candidate) || nzchar(Sys.which(candidate))) {
      if (grepl("^(/|~|[A-Za-z]:[\\\\/])", candidate)) {
        return(path.expand(candidate))
      }
      return(normalizePath(file.path(getwd(), candidate), winslash = "/", mustWork = FALSE))
    }
  }
  stop(
    "No Python executable was found. Set `GRAYLEAFSPOTR_PYTHON`, ",
    "configure `options(grayleafspotr.python = ...)`, or install Python 3."
  )
}

grayleafspot_python_env <- function(module_dir = grayleafspot_python_module_dir()) {
  if (!nzchar(module_dir)) {
    stop("The packaged Python pipeline could not be located.")
  }
  current_pythonpath <- Sys.getenv("PYTHONPATH", unset = "")
  pythonpath <- if (nzchar(current_pythonpath)) {
    paste(module_dir, current_pythonpath, sep = .Platform$path.sep)
  } else {
    module_dir
  }
  c(
    paste0("PYTHONPATH=", pythonpath),
    paste0("MPLCONFIGDIR=", file.path(tempdir(), "grayleafspotr-mpl")),
    "PYTHONUNBUFFERED=1"
  )
}

#' Check whether the Python ML dependencies are available
#'
#' Probes the resolved Python interpreter to confirm that the six modules
#' required by the SmallUNet pipeline (numpy, cv2, scipy, skimage, PIL, torch)
#' can be imported.
#'
#' @param python Optional character. Path to a specific Python executable.
#' @param engine_model Character. Currently only `"localunet"` is supported.
#' @return Logical `TRUE` if all required modules are importable, `FALSE`
#'   otherwise.
#' @export
grayleafspot_python_available <- function(python = NULL, engine_model = "localunet") {
  python_bin <- tryCatch(grayleafspot_python_executable(python, engine_model), error = function(e) NA_character_)
  if (is.na(python_bin) || !nzchar(python_bin)) {
    return(FALSE)
  }
  modules <- c("numpy", "cv2", "scipy", "skimage", "PIL", "torch")
  probe <- tempfile("grayleafspotr-python-probe-", fileext = ".py")
  on.exit(unlink(probe), add = TRUE)
  writeLines(
    c(
      "import importlib",
      "import sys",
      "modules = [",
      paste0("    '", modules, "',"),
      "]",
      "missing = []",
      "for module in modules:",
      "    try:",
      "        importlib.import_module(module)",
      "    except Exception:",
      "        missing.append(module)",
      "sys.exit(0 if not missing else 1)"
    ),
    probe
  )
  result <- suppressWarnings(
    system2(
      python_bin,
      args = probe,
      stdout = FALSE,
      stderr = FALSE
    )
  )
  status <- attr(result, "status")
  if (is.null(status)) {
    return(identical(result, 0L))
  }
  identical(status, 0L)
}

grayleafspot_python_run <- function(
    input_dir,
    output_dir,
    filenames = NULL,
    plate_diameter_mm = 90,
    run_name = NULL,
    python = NULL,
    engine_model = "localunet") {
  engine <- "local"
  python_bin <- grayleafspot_python_executable(python, engine_model)
  module_dir <- grayleafspot_python_module_dir()
  if (!nzchar(module_dir)) {
    stop("The packaged Python pipeline could not be located.")
  }
  package_root <- grayleafspot_package_root()
  if (!grayleafspot_python_available(python_bin, engine_model)) {
    stop(
      "The Python ML dependencies are not available. Install the packages in ",
      "`inst/python/requirements_arm.txt` into `rvenv_arm_311` and point ",
      "`GRAYLEAFSPOTR_PYTHON` at `rvenv_arm_311/bin/python`."
    )
  }

  args <- c(
    "-m", "pipeline.cli",
    "--input-dir", normalizePath(input_dir, winslash = "/", mustWork = FALSE),
    "--output-dir", normalizePath(output_dir, winslash = "/", mustWork = FALSE),
    "--plate-diameter-mm", as.character(plate_diameter_mm),
    "--engine-model", engine_model
  )
  if (!is.null(run_name) && nzchar(run_name)) {
    args <- c(args, "--run-name", run_name)
  }
  if (length(filenames)) {
    for (filename in filenames) {
      args <- c(args, "--filename", filename)
    }
  }
  args <- c(args, "--json")

  old_wd <- getwd()
  setwd(package_root)
  on.exit(setwd(old_wd), add = TRUE)
  output <- system2(
    python_bin,
    args = args,
    env = grayleafspot_python_env(module_dir),
    stdout = TRUE,
    stderr = FALSE
  )
  status <- attr(output, "status")
  if (!is.null(status) && !identical(status, 0L)) {
    stop(
      "Python analysis pipeline failed with exit status ",
      status,
      ". Output:\n",
      paste(output, collapse = "\n")
    )
  }
  parsed <- jsonlite::fromJSON(paste(output, collapse = "\n"), simplifyVector = TRUE)
  if (is.null(parsed$run$output_dir)) {
    stop("Python analysis pipeline did not return a run directory.")
  }
  parsed
}

#' Analyze plate images with the SmallUNet pipeline
#'
#' Calls the bundled Python pipeline (`inst/python/pipeline/analysislocal.py`)
#' via `rvenv_arm_311`, performs dish detection and SmallUNet segmentation on
#' each image, and returns a `grayleafspot_run` object with tidy results.
#'
#' @param input_dir Character. Path to the folder containing plate images.
#' @param output_dir Character. Base output directory. A timestamped sub-folder
#'   is created for each run.
#' @param filenames Optional character vector. Names of specific image files
#'   inside `input_dir` to analyze.  If `NULL`, all images in `input_dir` are
#'   processed.
#' @param plate_diameter_mm Numeric. Known petri dish diameter in mm (default
#'   90).
#' @param run_name Optional character. Human-readable suffix appended to the
#'   timestamped run folder name.
#' @param save_outputs Logical. If `FALSE`, outputs are written to a temporary
#'   directory and deleted after the results are returned.
#' @param verbose Logical. Print the saved run path to the console.
#' @param python Optional character. Override the Python executable (see
#'   [grayleafspot_python_executable()]).
#' @param engine_model Character. Must be `"localunet"`.
#' @return A `grayleafspot_run` object with elements `$run`, `$results`, and
#'   `$raw_results`.
#' @export
grayleafspot_analyze <- function(
  input_dir,
  output_dir = "outputs",
  filenames = NULL,
  plate_diameter_mm = 90,
  run_name = NULL,
  save_outputs = TRUE,
  verbose = TRUE,
  python = NULL,
  engine_model = "localunet") {
  input_dir <- normalizePath(input_dir, winslash = "/", mustWork = FALSE)
  if (!save_outputs) {
    output_dir <- file.path(tempdir(), paste0("grayleafspotr-", default_run_id()))
  }
  output_dir <- ensure_dir(output_dir)
  if (!dir.exists(input_dir)) {
    stop("`input_dir` does not exist.")
  }

  parsed <- grayleafspot_python_run(
    input_dir = input_dir,
    output_dir = output_dir,
    filenames = filenames,
    plate_diameter_mm = plate_diameter_mm,
    run_name = run_name,
    python = python,
    engine_model = engine_model
  )

  run_dir <- dirname(parsed$run$analysisJson %||% parsed$run$analysis_json %||% parsed$run$outputDir %||% parsed$run$output_dir)
  if (!nzchar(run_dir) || !dir.exists(run_dir)) {
    stop("Python analysis completed but the run directory could not be found.")
  }

  run <- read_grayleafspot_results(run_dir)
  if (verbose) {
    message("Saved run to: ", run$run$outputDir %||% run$run$output_dir %||% run_dir)
  }
  if (!save_outputs) {
    unlink(dirname(run_dir), recursive = TRUE, force = TRUE)
  }
  run
}

#' Run the gray leaf spot pipeline — simplified entry point
#'
#' A streamlined wrapper around the SmallUNet pipeline designed for everyday
#' use.  Unlike [grayleafspot_analyze()], this function:
#'
#' * reads the Python interpreter from `GRAYLEAFSPOTR_PYTHON` (fail-fast with
#'   a clear message if it is not set),
#' * creates `output_dir` automatically if it does not exist,
#' * returns the raw parsed JSON payload so you can work with results directly.
#'
#' ## One-time Python setup
#'
#' Set the environment variable once per session, or add it to `~/.Rprofile`
#' so it is loaded automatically every time R starts:
#'
#' ```r
#' # In ~/.Rprofile  (open with file.edit("~/.Rprofile"))
#' Sys.setenv(GRAYLEAFSPOTR_PYTHON = "/path/to/rvenv_arm_311/bin/python")
#' ```
#'
#' @param input_dir Character. Path to the folder containing plate images.
#' @param output_dir Character. Directory to write outputs into (created if
#'   absent).
#' @param run_name Character. Human-readable label appended to the timestamped
#'   run folder name (default `"run"`).
#' @param engine_model Character. Must be `"localunet"` (the only supported
#'   pipeline).
#' @param plate_diameter_mm Numeric. Known petri dish diameter in mm (default
#'   90).
#' @return A named list parsed directly from the pipeline JSON output,
#'   containing `$results` (per-image records) and `$run` (manifest metadata).
#' @seealso [grayleafspot_analyze()] for the full-featured interface that
#'   returns a `grayleafspot_run` S3 object with tidy plotting helpers.
#' @export
grayleafspot_run <- function(input_dir,
                             output_dir,
                             run_name      = "run",
                             engine_model  = "localunet",
                             plate_diameter_mm = 90) {
  if (!requireNamespace("grayleafspotr", quietly = TRUE)) {
    stop("Package 'grayleafspotr' is not installed.")
  }

  python_bin <- Sys.getenv("GRAYLEAFSPOTR_PYTHON")
  if (!nzchar(python_bin)) {
    stop(
      "GRAYLEAFSPOTR_PYTHON is not set.\n",
      "Add the following line to ~/.Rprofile (open with file.edit(\"~/.Rprofile\")):\n",
      "  Sys.setenv(GRAYLEAFSPOTR_PYTHON = \"/path/to/rvenv_arm_311/bin/python\")"
    )
  }
  if (!file.exists(python_bin)) {
    stop("Configured Python path does not exist: ", python_bin)
  }

  if (!dir.exists(input_dir)) {
    stop("Input directory does not exist: ", input_dir)
  }
  if (!dir.exists(output_dir)) {
    dir.create(output_dir, recursive = TRUE)
  }

  pkg_python_dir <- system.file("python", package = "grayleafspotr")
  if (!nzchar(pkg_python_dir)) {
    stop("Could not locate the grayleafspotr Python module directory.")
  }

  raw <- system2(
    python_bin,
    args = c(
      "-m", "pipeline.cli",
      "--input-dir",          normalizePath(input_dir,  winslash = "/", mustWork = FALSE),
      "--output-dir",         normalizePath(output_dir, winslash = "/", mustWork = FALSE),
      "--plate-diameter-mm",  as.character(plate_diameter_mm),
      "--engine-model",       engine_model,
      "--run-name",           run_name,
      "--json"
    ),
    env = c(
      paste0("PYTHONPATH=",    pkg_python_dir),
      paste0("MPLCONFIGDIR=",  file.path(tempdir(), "grayleafspotr-mpl")),
      "PYTHONUNBUFFERED=1"
    ),
    stdout = TRUE,
    stderr = FALSE
  )

  status <- attr(raw, "status")
  if (!is.null(status) && !identical(status, 0L)) {
    stop("Pipeline failed with exit status ", status, ".\nOutput:\n",
         paste(raw, collapse = "\n"))
  }

  tryCatch(
    jsonlite::fromJSON(paste(raw, collapse = "\n"), simplifyVector = TRUE),
    error = function(e) {
      stop("Pipeline ran but JSON parsing failed.\nRaw output:\n",
           paste(raw, collapse = "\n"))
    }
  )
}
