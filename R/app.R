#' Launch the grayleafspotr Shiny app
#'
#' Opens an interactive dashboard for running analyses, loading saved results,
#' and exploring all visualizations provided by the package.
#'
#' @param ... Arguments passed to [shiny::runApp()], e.g. `port`, `launch.browser`.
#'
#' @return Called for its side effect. Starts a Shiny app.
#'
#' @examples
#' \dontrun{
#' launch_grayleafspotr()
#' }
#'
#' @export
launch_grayleafspotr <- function(...) {
  app_dir <- system.file("shiny", package = "grayleafspotr")
  if (!nzchar(app_dir)) {
    stop("Could not find the Shiny app directory inside the grayleafspotr package.")
  }
  shiny::runApp(app_dir, ...)
}
