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
