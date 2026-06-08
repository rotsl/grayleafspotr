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

#' Return the Python executable used by the grayleafspot pipeline
#'
#' This function is intended for **advanced use only**. Normal users do not need
#' to call it — the pipeline resolves its Python environment automatically via
#' `basilisk`.
#'
#' Resolves the Python interpreter in this priority order: the `python`
#' argument, the `GRAYLEAFSPOTR_PYTHON` environment variable, the
#' `grayleafspotr.python` option, and finally `python3` / `python` from `PATH`.
#'
#' @param python Optional character. Path to a Python executable.
#' @param engine_model Character. Reserved for future use; currently only
#'   `"localunet"` is supported.
#' @return Character string: absolute path to the resolved Python executable.
#' @examples
#' \donttest{
#'   grayleafspot_python_executable()
#' }
#' @export
grayleafspot_python_executable <- function(python = NULL, engine_model = "localunet") {
  candidates <- c(
    python,
    Sys.getenv("GRAYLEAFSPOTR_PYTHON", unset = ""),
    getOption("grayleafspotr.python"),
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
    "No Python executable was found. Set `GRAYLEAFSPOTR_PYTHON` or install Python 3."
  )
}

#' Check whether the Python ML dependencies are available
#'
#' When the default basilisk-managed environment is in use, this function
#' returns `TRUE` as long as `basilisk` is installed (the environment is
#' set up lazily on first pipeline run).  When an explicit Python interpreter
#' is configured via `GRAYLEAFSPOTR_PYTHON` or the `python` argument, the
#' function probes that interpreter directly.
#'
#' @param python Optional character. Path to a specific Python executable.
#'   If `NULL` and `GRAYLEAFSPOTR_PYTHON` is not set, the basilisk-managed
#'   environment is assumed available.
#' @param engine_model Character. Currently only `"localunet"` is supported.
#' @return Logical `TRUE` if the pipeline can run, `FALSE` otherwise.
#' @examples
#' \donttest{
#'   grayleafspot_python_available()
#' }
#' @export
grayleafspot_python_available <- function(python = NULL, engine_model = "localunet") {
  explicit_python <- python %||% Sys.getenv("GRAYLEAFSPOTR_PYTHON", unset = "")
  if (!nzchar(explicit_python)) {
    return(requireNamespace("basilisk", quietly = TRUE))
  }

  python_bin <- tryCatch(
    grayleafspot_python_executable(explicit_python, engine_model),
    error = function(e) NA_character_
  )
  if (is.na(python_bin) || !nzchar(python_bin)) {
    return(FALSE)
  }
  modules <- c("numpy", "cv2", "scipy", "skimage", "PIL", "torch")
  probe <- tempfile("grayleafspotr-python-probe-", fileext = ".py")
  on.exit(unlink(probe), add = TRUE)
  writeLines(
    c(
      "import importlib, sys",
      sprintf("modules = [%s]", paste0("'", modules, "'", collapse = ", ")),
      "missing = [m for m in modules if not __import__('importlib').util.find_spec(m)]",
      "sys.exit(0 if not missing else 1)"
    ),
    probe
  )
  result <- suppressWarnings(
    system2(python_bin, args = probe, stdout = FALSE, stderr = FALSE)
  )
  status <- attr(result, "status")
  identical(if (is.null(status)) result else status, 0L)
}

# Internal: build the args vector for the pipeline CLI call.
grayleafspot_build_args <- function(input_dir, output_dir, filenames,
                                    plate_diameter_mm, run_name, engine_model,
                                    model_path) {
  args <- c(
    "-m", "pipeline.cli",
    "--input-dir",          normalizePath(input_dir,  winslash = "/", mustWork = FALSE),
    "--output-dir",         normalizePath(output_dir, winslash = "/", mustWork = FALSE),
    "--plate-diameter-mm",  as.character(plate_diameter_mm),
    "--engine-model",       engine_model,
    "--model-path",         normalizePath(model_path, winslash = "/", mustWork = FALSE)
  )
  if (!is.null(run_name) && nzchar(run_name)) {
    args <- c(args, "--run-name", run_name)
  }
  if (length(filenames)) {
    for (f in filenames) args <- c(args, "--filename", f)
  }
  c(args, "--json")
}

# Internal: run pipeline using a specific python_bin directly (override path).
grayleafspot_python_run_direct <- function(python_bin, args_vec, module_dir) {
  output <- system2(
    python_bin,
    args   = args_vec,
    env    = grayleafspot_python_env(module_dir),
    stdout = TRUE,
    stderr = FALSE
  )
  status <- attr(output, "status")
  if (!is.null(status) && !identical(status, 0L)) {
    stop("Python pipeline failed (exit status ", status, ").\n",
         paste(output, collapse = "\n"))
  }
  paste(output, collapse = "\n")
}

# Internal: run pipeline through the basilisk-managed environment.
grayleafspot_python_run_basilisk <- function(args_vec, module_dir) {
  basilisk::basiliskRun(
    env = grayleafspotr_env,
    fun = function(args_vec, module_dir) {
      python_bin <- reticulate::py_config()$python
      env_vars <- c(
        paste0("PYTHONPATH=",   module_dir),
        paste0("MPLCONFIGDIR=", file.path(tempdir(), "grayleafspotr-mpl")),
        "PYTHONUNBUFFERED=1"
      )
      output <- system2(python_bin, args = args_vec,
                        env = env_vars, stdout = TRUE, stderr = FALSE)
      status <- attr(output, "status")
      if (!is.null(status) && !identical(status, 0L)) {
        stop("Python pipeline failed (exit status ", status, ").\n",
             paste(output, collapse = "\n"))
      }
      paste(output, collapse = "\n")
    },
    args_vec   = args_vec,
    module_dir = module_dir
  )
}

# Internal: top-level dispatcher — direct or basilisk.
grayleafspot_python_run <- function(
    input_dir,
    output_dir,
    filenames         = NULL,
    plate_diameter_mm = 90,
    run_name          = NULL,
    python            = NULL,
    engine_model      = "localunet") {

  module_dir <- grayleafspot_python_module_dir()
  if (!nzchar(module_dir)) {
    stop("The packaged Python pipeline could not be located.")
  }

  model_path <- grayleafspot_model_path(quiet = TRUE)
  args_vec <- grayleafspot_build_args(
    input_dir, output_dir, filenames, plate_diameter_mm, run_name, engine_model, model_path
  )

  explicit_python <- python %||% Sys.getenv("GRAYLEAFSPOTR_PYTHON", unset = "")
  if (!nzchar(explicit_python)) explicit_python <- NULL

  json_str <- if (!is.null(explicit_python)) {
    grayleafspot_python_run_direct(explicit_python, args_vec, module_dir)
  } else {
    grayleafspot_python_run_basilisk(args_vec, module_dir)
  }

  parsed <- tryCatch(
    jsonlite::fromJSON(json_str, simplifyVector = TRUE),
    error = function(e) stop("Pipeline ran but JSON parsing failed.\nRaw output:\n", json_str)
  )
  if (is.null(parsed$run$output_dir)) {
    stop("Python analysis pipeline did not return a run directory.")
  }
  parsed
}

#' Analyze plate images with the SmallUNet pipeline
#'
#' Calls the bundled Python pipeline, performs dish detection and SmallUNet
#' segmentation on each image, and returns a `grayleafspot_run` object with
#' tidy results and template plots.
#'
#' Python dependencies are managed automatically through `basilisk`. No manual
#' Python environment setup is required for normal use. The first call will
#' download and configure the required packages (this may take a few minutes on
#' a fresh installation). Subsequent calls use the cached environment.
#'
#' Developers who maintain a local Python environment can bypass basilisk by
#' setting the `GRAYLEAFSPOTR_PYTHON` environment variable to the path of
#' their Python interpreter; this is not required for normal users.
#'
#' @param input_dir Character. Path to the folder containing plate images
#'   (JPEG, PNG, BMP, TIFF, or WEBP). Images must include a day token in their
#'   filename (e.g. `*_d04_*` for day 4).
#' @param output_dir Character. Base output directory. A timestamped sub-folder
#'   is created for each run. Defaults to `"outputs"`.
#' @param filenames Optional character vector. Names of specific image files
#'   inside `input_dir` to analyze. If `NULL`, all supported images are
#'   processed.
#' @param plate_diameter_mm Numeric. Known petri dish diameter in mm (default
#'   90).
#' @param run_name Optional character. Human-readable suffix appended to the
#'   timestamped run folder name.
#' @param save_outputs Logical. If `FALSE`, outputs are written to a temporary
#'   directory and deleted after the results are returned.
#' @param verbose Logical. Print the saved run path to the console.
#' @param python Optional character. Advanced override: path to a specific
#'   Python executable. Overrides `GRAYLEAFSPOTR_PYTHON` and basilisk.
#' @param engine_model Character. Must be `"localunet"`.
#' @return A `grayleafspot_run` S3 object with elements `$run` (manifest
#'   metadata), `$results` (per-image data frame), and `$raw_results`.
#' @seealso [grayleafspot_run()] for a simpler entry point returning raw JSON.
#' @examples
#' \donttest{
#'   img_dir <- system.file("extdata", "testdata", "06FEB", package = "grayleafspotr")
#'   run <- grayleafspot_analyze(img_dir, output_dir = tempdir())
#' }
#' @export
grayleafspot_analyze <- function(
  input_dir,
  output_dir        = "outputs",
  filenames         = NULL,
  plate_diameter_mm = 90,
  run_name          = NULL,
  save_outputs      = TRUE,
  verbose           = TRUE,
  python            = NULL,
  engine_model      = "localunet") {

  input_dir <- normalizePath(input_dir, winslash = "/", mustWork = FALSE)
  if (!dir.exists(input_dir)) {
    stop("`input_dir` does not exist.")
  }
  if (!save_outputs) {
    output_dir <- file.path(tempdir(), paste0("grayleafspotr-", default_run_id()))
  }
  output_dir <- ensure_dir(output_dir)

  parsed <- grayleafspot_python_run(
    input_dir         = input_dir,
    output_dir        = output_dir,
    filenames         = filenames,
    plate_diameter_mm = plate_diameter_mm,
    run_name          = run_name,
    python            = python,
    engine_model      = engine_model
  )

  run_dir <- dirname(
    parsed$run$analysisJson %||% parsed$run$analysis_json %||%
    parsed$run$outputDir   %||% parsed$run$output_dir
  )
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
#' A streamlined wrapper around the SmallUNet pipeline.  Python dependencies
#' are resolved automatically via `basilisk` — no manual environment setup is
#' required.
#'
#' ## Workflow
#'
#' ```r
#' library(grayleafspotr)
#'
#' res <- grayleafspot_run(
#'   input_dir  = "path/to/images",
#'   output_dir = "outputs",
#'   run_name   = "trial_01"
#' )
#' res$results   # per-image feature table
#' ```
#'
#' ## Advanced: developer Python override
#'
#' Set `GRAYLEAFSPOTR_PYTHON` in `~/.Rprofile` to use a specific interpreter
#' (e.g. a local `rvenv_arm_311`). This is **not needed** for normal use.
#'
#' ```r
#' # ~/.Rprofile — developer only
#' Sys.setenv(GRAYLEAFSPOTR_PYTHON = "/path/to/rvenv_arm_311/bin/python")
#' ```
#'
#' @param input_dir Character. Path to the folder containing plate images.
#' @param output_dir Character. Directory to write outputs into (created if
#'   absent).
#' @param run_name Character. Human-readable label for the run (default
#'   `"run"`).
#' @param engine_model Character. Must be `"localunet"`.
#' @param plate_diameter_mm Numeric. Known petri dish diameter in mm (default
#'   90).
#' @return A named list parsed from the pipeline JSON output, containing
#'   `$results` (per-image feature records) and `$run` (manifest metadata).
#' @seealso [grayleafspot_analyze()] for the full-featured interface returning
#'   a `grayleafspot_run` S3 object with plotting helpers.
#' @examples
#' \donttest{
#'   img_dir <- system.file("extdata", "testdata", "06FEB", package = "grayleafspotr")
#'   result <- grayleafspot_run(img_dir, tempdir())
#' }
#' @export
grayleafspot_run <- function(
    input_dir,
    output_dir,
    run_name          = "run",
    engine_model      = "localunet",
    plate_diameter_mm = 90) {

  if (!dir.exists(input_dir)) {
    stop("Input directory does not exist: ", input_dir)
  }
  if (!dir.exists(output_dir)) {
    dir.create(output_dir, recursive = TRUE)
  }

  grayleafspot_python_run(
    input_dir         = input_dir,
    output_dir        = output_dir,
    run_name          = run_name,
    plate_diameter_mm = plate_diameter_mm,
    engine_model      = engine_model
  )
}
