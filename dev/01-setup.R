if (!requireNamespace("devtools", quietly = TRUE)) {
  stop("Install devtools first.")
}
if (!requireNamespace("usethis", quietly = TRUE)) {
  stop("Install usethis first.")
}

usethis::use_roxygen_md()
if (!dir.exists("tests/testthat")) {
  usethis::use_testthat(edition = 3)
}
if (!file.exists("vignettes/getting-started.Rmd")) {
  usethis::use_vignette("getting-started")
}
