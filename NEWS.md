# grayleafspotr News

## grayleafspotr 0.99.0

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
