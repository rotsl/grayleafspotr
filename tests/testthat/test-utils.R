test_that("slugify produces safe ids", {
  expect_identical(slugify("Gray Leaf Spot!"), "gray_leaf_spot")
})

test_that("example data loads", {
  run <- example_grayleafspot_results()
  expect_s3_class(run, "grayleafspot_run")
  expect_true(nrow(run$results) >= 1)
})

