# grayleafspotr News

## grayleafspotr 0.99.5

### Bug fixes

* Fixed `Pipeline ran but JSON parsing failed` on Windows. The pipeline's
  stdout on success is a single very long JSON line (`colony_polygon` alone
  can run to tens of thousands of points per image); `system2()`'s
  intern-style `stdout = TRUE` capture has a per-line buffer limit on
  Windows that silently splits such long lines at arbitrary byte offsets,
  and rejoining the pieces with `"\n"` corrupted the JSON mid-token. Both
  stdout and stderr are now redirected to files and read back whole, which
  avoids the line-splitting entirely.

## grayleafspotr 0.99.4

### Bug fixes

* Fixed the Python pipeline failing on Windows (`Python pipeline failed
  (exit status 2)`). `system2()`'s `env` argument is only honored on Windows
  for a small set of commands (`R`, `make`) that parse `VAR=value` strings
  from their own argv; for arbitrary executables such as `python` it was
  silently ignored there, and those strings were instead passed through as
  positional arguments, which Python then tried to open as a script file.
  `PYTHONPATH`/`MPLCONFIGDIR`/`PYTHONUNBUFFERED` are now set on the R
  process itself (restored on exit) so the child process inherits them
  identically on every platform.
* `system2()` calls to the Python pipeline now capture `stderr` together
  with `stdout` so pipeline failures include the actual Python traceback
  instead of just an exit status.

### Documentation fixes

* Corrected the causal organism described throughout the package
  (`DESCRIPTION`, both vignettes) from *Cercospora zeae-maydis* /
  *Cercospora zeicola* on maize to *Magnaporthe oryzae* — "grayleafspotr" is
  a package name, not a claim about the maize pathogen complex.
* Added a References section to the `grayleafspotr-workflow` vignette
  linking to related datasets and software by the same author.

## grayleafspotr 0.99.3

### Breaking changes

* Removed the bundled Shiny app (`launch_grayleafspotr()`, `inst/shiny/`) and
  its deployment infrastructure (`Dockerfile`, `render.yaml`,
  `.dockerignore`). It was unused legacy functionality; all package
  functionality remains available through the R API.

### New features

* Added `plot_grayleafspot_overlay()`, which uses `EBImage` to draw the
  detected dish boundary, colony outline, and crack segments on the source
  plate photograph, for visual QC of the segmentation pipeline.

### Bioconductor review fixes

* `Depends` bumped to `R (>= 4.6.0)` to match the current Bioconductor devel
  R pairing; added `BiocType: Software`.
* Added ORCID to `Authors@R` and an `inst/CITATION` file.
* `grayleafspot_download_model()` now caches via `BiocFileCache` instead of
  `tools::R_user_dir()` + `download.file()`.
* Narrowed two blanket `suppressWarnings()` calls to specifically-matched
  warnings; renamed an internal function exceeding the 30-character lintr
  limit; replaced a fixed `-1:1` range with an explicit vector; documented
  the previously-undocumented internal `example_grayleafspot_dir()`.
* Vignettes switched to `BiocStyle::html_document`, all chunks labeled,
  `sessionInfo()` added to `getting-started.Rmd`, and the previously-disabled
  "analyze your own images" / "reload saved results" chunks now run for real
  against the bundled 06FEB test images (gated so environments without a
  working Python/basilisk setup degrade gracefully).
* README reorganised: Bioconductor installation instructions moved to the
  top, developer/Python-environment setup consolidated under a "Development"
  section, and the manual virtual environment setup instructions changed to
  use a directory outside the package tree.

## grayleafspotr 0.99.2

### Bug fixes

* Replaced `\donttest{}` wrappers with plain runnable code in four man pages
  (`launch_grayleafspotr`, `write_grayleafspot_results`,
  `grayleafspot_python_available`, `grayleafspot_python_executable`) so that
  BiocCheck counts them toward the required 80% runnable-examples threshold.
  `launch_grayleafspotr` uses an `if (interactive())` guard;
  `grayleafspot_python_executable` uses `tryCatch()` to handle environments
  where Python is absent without aborting the check.

## grayleafspotr 0.99.1

### Bug fixes

* Added runnable `@examples` to all 18 exported man pages to satisfy the
  Bioconductor BiocCheck requirement (>= 80% of pages must have examples).
  Functions requiring Python or a network connection use `\donttest{}`;
  pure-R functions use the bundled `example_grayleafspot_results()` data.
* Changed `\dontrun{}` to `\donttest{}` in `launch_grayleafspotr()` man page
  (BiocCheck does not count `\dontrun{}` as a runnable example).

## grayleafspotr 0.99.0

### Bug fixes

* Corrected column name `crack_coverage` to `crack_coverage_pct` in vignette
  result subsets to match the actual output column from `read_grayleafspot_results()`
  (#1).
* Added `launch_grayleafspotr()` to the pkgdown reference index to resolve a
  build error when exported topics were absent from `_pkgdown.yml`.

Initial release.

### Analysis pipeline

* SmallUNet segmentation pipeline (`inst/python/pipeline/analysislocal.py`)
  running inside `rvenv_arm_311` (ARM64 Python 3.11).
* Sole model is `models/best_area_w_0.7.pt`; downloaded automatically from
  HuggingFace via `grayleafspot_download_model()` when not present locally.
* Dish geometry calibrated from grayscale image edges using an assumed 90 mm
  petri dish diameter (configurable via `plate_diameter_mm`).
* Classical crack detection on an internal-band mask; crack polylines drawn
  as yellow overlays on top of the red colony mask.
* Colony expansion reported in mm and mm² from pixel-to-mm calibration.
* Kinematics (radial velocity, area growth rate, relative growth rate) computed
  across the ordered time series.

### R interface

* `grayleafspot_analyze()` — run the pipeline on a folder of plate images.
* `grayleafspot_python_available()` / `grayleafspot_python_executable()` —
  check and resolve the Python interpreter for `rvenv_arm_311`.
* `grayleafspot_download_model()` — fetch `best_area_w_0.7.pt` from HuggingFace
  and cache to `tools::R_user_dir("grayleafspotr", "cache")`.
* `read_grayleafspot_results()` / `write_grayleafspot_results()` — load and
  save run directories (JSON + CSV + manifest).
* `as_grayleafspot_growth_data()` — coerce a run to a tidy tibble.
* `example_grayleafspot_results()` — load the built-in example run without
  running the pipeline.

### Plotting

* `plot_colony_expansion()` — equivalent radius over time.
* `plot_growth_roughness()` — relative growth rate and edge roughness.
* `plot_stress_remodeling()` — crack coverage and crack count.
* `plot_texture_organization()` — Shannon entropy and center-to-edge delta.
* `plot_shape_vs_stress()` — eccentricity vs crack coverage scatter.
* `plot_radial_growth_area()` — colony area and radial growth by plate (faceted);
  connects points across time even when each plate appears only once.
* `plot_feature_heatmap()` — Pearson correlation heatmap of numeric features.
* `plot_radial_profile()` — radial intensity profile; auto-discovers the most
  recent `analysis.json` under `outputs/` when given a plain data frame.

### Package assets

* Three bundled plate images in `inst/extdata/testdata/06FEB/` for offline
  testing and vignette examples (original photographs, Apache License 2.0).
* Example run in `inst/extdata/example/` (JSON, CSV, manifest).
* Full Roxygen2 documentation for all 17 exported functions (`man/`).
* Integration tests in `tests/testthat/test-pipeline.R`; skip gracefully when
  Python or the model is not available.
* `inst/COPYRIGHTS` enumerating copyright and license for every non-R asset.
* `NOTICE` file in the package root (Apache 2.0 requirement).
