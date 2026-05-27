# Basilisk environment for the SmallUNet segmentation pipeline.
#
# Exact package versions match inst/python/requirements_arm.txt and have been
# validated against models/best_area_w_0.7.pt. The environment is created
# lazily on first pipeline call and cached by basilisk in the user's cache
# directory; no manual setup is required.
#
# Developers who maintain a local rvenv_arm_311 environment can bypass
# basilisk by setting GRAYLEAFSPOTR_PYTHON. Normal users do not need this.

#' @importFrom basilisk BasiliskEnvironment
grayleafspotr_env <- basilisk::BasiliskEnvironment(
  envname  = "grayleafspotr_env_v1",
  pkgname  = "grayleafspotr",
  packages = c(
    "numpy==2.4.4",
    "opencv-python==4.13.0.92",
    "pillow==12.2.0",
    "scipy==1.17.1",
    "scikit-image==0.26.0",
    "torch==2.11.0",
    "torchvision==0.26.0",
    "python-dotenv==1.2.2"
  )
)
