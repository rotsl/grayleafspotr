testdata_dir <- system.file("extdata", "testdata", "06FEB", package = "grayleafspotr")
if (!nzchar(testdata_dir)) {
  testdata_dir <- file.path("inst", "extdata", "testdata", "06FEB")
}

overlay_records <- if (dir.exists(testdata_dir)) {
  image_files <- list.files(testdata_dir, full.names = TRUE)
  lapply(image_files, analyze_grayleafspot_image)
} else {
  list()
}

test_that("plot_grayleafspot_overlay draws on a single analyzed record", {
  skip_if_not_installed("EBImage")
  skip_if_not(length(overlay_records) > 0, "Test image directory not found")

  record <- overlay_records[[1]]
  original <- EBImage::readImage(record$imageUrl)
  overlay <- plot_grayleafspot_overlay(record)

  expect_s4_class(overlay, "Image")
  expect_equal(dim(overlay), dim(original))
  expect_false(identical(as.numeric(overlay), as.numeric(EBImage::toRGB(original))))
})

test_that("plot_grayleafspot_overlay resolves a record by id from a raw_results list", {
  skip_if_not_installed("EBImage")
  skip_if_not(length(overlay_records) > 1, "Test image directory not found")

  target <- overlay_records[[2]]
  overlay <- plot_grayleafspot_overlay(overlay_records, id = target$id)
  expect_s4_class(overlay, "Image")
})

test_that("plot_grayleafspot_overlay errors clearly when the image can't be located", {
  record <- list(id = "x", filename = "x.jpg", rawAnalysis = list())
  expect_error(plot_grayleafspot_overlay(record), "Could not locate the source image")
})
