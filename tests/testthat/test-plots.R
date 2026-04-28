test_that("plot functions return ggplot objects", {
  run <- example_grayleafspot_results()
  expect_s3_class(plot_colony_expansion(run), "ggplot")
  expect_s3_class(plot_growth_roughness(run), "ggplot")
  expect_s3_class(plot_stress_remodeling(run), "ggplot")
  expect_s3_class(plot_texture_organization(run), "ggplot")
  expect_s3_class(plot_shape_vs_stress(run), "ggplot")
  expect_s3_class(plot_feature_heatmap(run), "ggplot")
})

