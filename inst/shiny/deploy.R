options(repos = c(
  rotsl = "https://rotsl.r-universe.dev",
  CRAN = "https://cloud.r-project.org"
))
options(rsconnect.http.trace = FALSE)

required_packages <- c("grayleafspotr", "jpeg", "tiff")
missing_packages <- required_packages[!vapply(required_packages, requireNamespace,
                                              quietly = TRUE, FUN.VALUE = logical(1))]
if (length(missing_packages)) {
  install.packages(missing_packages)
}

args <- commandArgs(trailingOnly = FALSE)
file_arg <- grep("^--file=", args, value = TRUE)
this_file <- if (length(file_arg)) {
  normalizePath(sub("^--file=", "", file_arg[[1]]), mustWork = TRUE)
} else if (!is.null(sys.frame(1)$ofile)) {
  normalizePath(sys.frame(1)$ofile, mustWork = TRUE)
} else {
  normalizePath("deploy.R", mustWork = TRUE)
}
app_dir <- dirname(this_file)

rsconnect::deployApp(
  appDir = app_dir,
  appName = "grayleafspotr",
  account = "rotsl",
  server = "shinyapps.io",
  logLevel = "normal"
)
