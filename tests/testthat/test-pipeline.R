test_that("bundled test images exist in inst/extdata/testdata/06FEB", {
  testdata_dir <- system.file("extdata", "testdata", "06FEB", package = "grayleafspotr")
  if (!nzchar(testdata_dir)) {
    testdata_dir <- file.path("inst", "extdata", "testdata", "06FEB")
  }
  expect_true(dir.exists(testdata_dir))
  imgs <- list.files(testdata_dir, pattern = "\\.(jpg|jpeg|png)$", ignore.case = TRUE)
  expect_equal(length(imgs), 3L)
})

test_that("grayleafspot_analyze runs end-to-end on bundled test images", {
  skip_if_not(
    grayleafspot_python_available(engine_model = "localunet"),
    "Python ML dependencies not available"
  )

  testdata_dir <- system.file("extdata", "testdata", "06FEB", package = "grayleafspotr")
  if (!nzchar(testdata_dir)) {
    testdata_dir <- file.path("inst", "extdata", "testdata", "06FEB")
  }
  skip_if_not(dir.exists(testdata_dir), "Test image directory not found")

  model_path <- file.path(grayleafspot_package_root(), "models", "best_area_w_0.7.pt")
  if (!file.exists(model_path)) {
    cache_model <- file.path(tools::R_user_dir("grayleafspotr", "cache"), "best_area_w_0.7.pt")
    skip_if_not(file.exists(cache_model), "SmallUNet model not available (run grayleafspot_download_model())")
  }

  run <- grayleafspot_analyze(
    input_dir = testdata_dir,
    output_dir = tempdir(),
    save_outputs = FALSE,
    verbose = FALSE,
    engine_model = "localunet"
  )

  expect_s3_class(run, "grayleafspot_run")
  expect_equal(nrow(run$results), 3L)
  expect_true(all(run$results$area_mm2 > 0))
  expect_true(all(run$results$qc_status == "pass"))
  expect_setequal(sort(run$results$day), c(4L, 6L, 10L))
})
