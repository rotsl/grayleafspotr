#' Path to the bundled example run directory
#'
#' Resolves the installed location of the small example run shipped under
#' `inst/extdata/example/` (falling back to the in-source path during
#' development, before the package has been installed).
#'
#' @return A single character path.
#' @keywords internal
example_grayleafspot_dir <- function() {
  installed_path <- system.file("extdata", "example", package = "grayleafspotr")
  if (nzchar(installed_path)) {
    return(installed_path)
  }
  source_path <- file.path("grayleafspotr", "inst", "extdata", "example")
  if (dir.exists(source_path)) {
    return(source_path)
  }
  file.path("inst", "extdata", "example")
}
