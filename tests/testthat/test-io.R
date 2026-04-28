test_that("results can be written and read back", {
  tmp <- tempfile("grayleafspot-test-")
  dir.create(tmp)
  run <- example_grayleafspot_results()
  saved <- write_grayleafspot_results(
    results = list(
      list(
        id = "demo-1",
        filename = "demo_day1.png",
        day = 1,
        pixelToMm = 0.1,
        morphology = list(
          areaMm2 = 12,
          equivalentRadiusMm = 1.95,
          diameterMm = 3.9,
          perimeterMm = 8,
          circularity = 0.8,
          eccentricity = 0.2,
          edgeRoughness = 0.1
        ),
        texture = list(
          contrast = 0.2,
          correlation = 0.1,
          energy = 0.3,
          homogeneity = 0.4,
          entropy = 1.2,
          centerToEdgeDelta = 0.05,
          densityIndex = 0.8,
          radialZonation = list(core = 0.1, middle = 0.2, outer = 0.3)
        ),
        cracks = list(
          count = 0,
          totalLengthMm = 0,
          coveragePct = 0,
          proportionalCoveragePct = 0,
          internalBandSummary = "none"
        ),
        kinematics = list(
          radialVelocity = 0,
          areaGrowthRate = 0,
          relativeGrowthRate = 0,
          radialAcceleration = 0
        ),
        qcStatus = "pass",
        qcNotes = "ok",
        rawAnalysis = list(radial_profile = list(radiusFraction = c(0, 1), meanIntensity = c(0.2, 0.8)))
      )
    ),
    output_dir = tmp
  )
  expect_true(file.exists(file.path(tmp, "analysis.json")))
  expect_true(file.exists(file.path(tmp, "analysis.csv")))
  expect_true(file.exists(file.path(tmp, "manifest.json")))
  reread <- read_grayleafspot_results(tmp)
  expect_s3_class(reread, "grayleafspot_run")
  expect_true(nrow(reread$results) == 1)
})

