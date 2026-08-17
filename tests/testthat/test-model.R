test_that("grayleafspot_download_model uses the local models/ copy when present", {
  pkg_root <- tempfile("pkgroot-")
  dir.create(file.path(pkg_root, "models"), recursive = TRUE)
  on.exit(unlink(pkg_root, recursive = TRUE), add = TRUE)
  local_path <- file.path(pkg_root, "models", "best_area_w_0.7.pt")
  writeLines("fake-weights", local_path)

  local_mocked_bindings(
    grayleafspot_package_root = function() pkg_root,
    .package = "grayleafspotr"
  )

  result <- grayleafspot_download_model(quiet = TRUE)
  expect_identical(normalizePath(result), normalizePath(local_path))
})

test_that("grayleafspot_download_model adds to BiocFileCache once, then reuses the cache", {
  skip_if_not_installed("BiocFileCache")

  pkg_root <- tempfile("pkgroot-")
  dir.create(pkg_root, recursive = TRUE)
  on.exit(unlink(pkg_root, recursive = TRUE), add = TRUE)
  fake_cache_path <- tempfile("cached-model-")
  writeLines("fake-weights", fake_cache_path)
  on.exit(unlink(fake_cache_path), add = TRUE)

  local_mocked_bindings(
    grayleafspot_package_root = function() pkg_root,
    .package = "grayleafspotr"
  )

  cache_calls <- 0L
  local_mocked_bindings(
    bfcquery = function(x, query, field = c("rname", "rpath", "fpath"), ..., exact = FALSE) {
      list(rid = if (cache_calls == 0L) character(0) else "RID1")
    },
    bfcadd = function(x, rname, fpath, rtype = "web", download = TRUE, ...) {
      cache_calls <<- cache_calls + 1L
      stats::setNames(fake_cache_path, "RID1")
    },
    bfcrpath = function(x, rnames, ..., rids, exact = TRUE) {
      stats::setNames(fake_cache_path, "RID1")
    },
    .package = "BiocFileCache"
  )

  first <- grayleafspot_download_model(quiet = TRUE)
  second <- grayleafspot_download_model(quiet = TRUE)

  expect_identical(unname(first), fake_cache_path)
  expect_identical(unname(second), fake_cache_path)
  expect_equal(cache_calls, 1L)
})
