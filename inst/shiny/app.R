options(repos = c(
  rotsl = "https://rotsl.r-universe.dev",
  CRAN = "https://cloud.r-project.org"
))
options(shiny.maxRequestSize = max(getOption("shiny.maxRequestSize", 5 * 1024^2),
                                   500 * 1024^2))

library(shiny)
library(bslib)
library(bsicons)
library(grayleafspotr)
library(ggplot2)
library(DT)
if (FALSE) {
  library(jpeg)
  library(tiff)
}

`%||%` <- function(x, y) if (is.null(x) || length(x) == 0) y else x

# ---------------------------------------------------------------------------
# UI
# ---------------------------------------------------------------------------

ui <- page_navbar(
  title = tagList(
    tags$img(src = "logo.png", height = "34px",
             style = "margin-right:6px; vertical-align:middle;"),
    "grayleafspotr"
  ),
  id           = "main_nav",
  selected     = "growth",
  theme        = bs_theme(version = 5, preset = "flatly"),
  window_title = "grayleafspotr",
  footer = div(
    class = "text-center text-muted border-top py-2",
    style = "font-size:0.78rem; background:#f8f9fa;",
    div(
      "Developed by ",
      tags$a("Rohan R",
             href   = "https://rotsl.r-universe.dev/builds",
             target = "_blank",
             rel    = "noopener noreferrer")
    ),
    div("Apache 2.0 License")
  ),

  sidebar = sidebar(
    width = 300,

    accordion(
      open = TRUE,

      # -- Data source ------------------------------------------------
      accordion_panel(
        "Data Source",
        icon = bs_icon("database"),

        radioButtons(
          "data_source", NULL,
          choices = c(
            "Example data"       = "example",
            "Load saved results" = "load",
            "Run new analysis"   = "run"
          )
        ),

        conditionalPanel(
          "input.data_source == 'load'",
          textInput("results_dir", "Results directory",
                    placeholder = "path/to/outputs/run_dir")
        ),

        conditionalPanel(
          "input.data_source == 'run'",
          fileInput(
            "image_uploads", "Upload images",
            multiple = TRUE,
            accept = c(".png", ".jpg", ".jpeg", ".tif", ".tiff")
          ),
          uiOutput("uploaded_files_status"),
          textInput("run_name",   "Run name (optional)",  placeholder = "my_experiment"),
          numericInput("plate_mm", "Plate diameter (mm)", value = 90,
                       min = 10, max = 200, step = 1),
          uiOutput("day_assignment_panel")
        ),

        uiOutput("sidebar_buttons"),
        uiOutput("download_outputs_ui")
      ),

      # -- Status ----------------------------------------------------
      accordion_panel(
        "Status",
        icon = bs_icon("info-circle"),
        uiOutput("status_ui")
      )
    )
  ),

  # -- Growth -----------------------------------------------------------
  nav_panel(
    "Growth",
    value = "growth",
    icon = bs_icon("graph-up"),
    layout_column_wrap(
      width = 1 / 2,
      card(full_screen = TRUE, card_header("Colony Expansion"),
           plotOutput("plot_expansion", height = "340px")),
      card(full_screen = TRUE, card_header("Growth & Edge Roughness"),
           plotOutput("plot_roughness", height = "340px"))
    ),
    card(full_screen = TRUE, card_header("Radial Growth & Area (by plate)"),
         plotOutput("plot_radial_area", height = "420px"))
  ),

  # -- Stress & Morphology ----------------------------------------------
  nav_panel(
    "Stress & Morphology",
    icon = bs_icon("exclamation-triangle"),
    layout_column_wrap(
      width = 1 / 2,
      card(full_screen = TRUE, card_header("Stress Remodeling"),
           plotOutput("plot_stress", height = "380px")),
      card(full_screen = TRUE, card_header("Shape vs Stress"),
           plotOutput("plot_shape_stress", height = "380px"))
    )
  ),

  # -- Texture ----------------------------------------------------------
  nav_panel(
    "Texture & Radial",
    icon = bs_icon("grid-3x3"),
    layout_column_wrap(
      width = 1 / 2,
      card(full_screen = TRUE, card_header("Texture Organization"),
           plotOutput("plot_texture", height = "380px")),
      card(full_screen = TRUE, card_header("Radial Intensity Profile"),
           plotOutput("plot_radial_profile", height = "380px"))
    )
  ),

  # -- Feature Heatmap --------------------------------------------------
  nav_panel(
    "Feature Heatmap",
    icon = bs_icon("bar-chart-steps"),
    card(full_screen = TRUE, card_header("Feature Correlation Heatmap"),
         plotOutput("plot_heatmap", height = "600px"))
  ),

  # -- Overlays ---------------------------------------------------------
  nav_panel("Overlays", icon = bs_icon("images"), uiOutput("overlay_gallery")),

  # -- Data Table -------------------------------------------------------
  nav_panel(
    "Data",
    icon = bs_icon("table"),
    card(card_header("Growth Data"), DTOutput("data_table"))
  )
)

# ---------------------------------------------------------------------------
# Server
# ---------------------------------------------------------------------------

server <- function(input, output, session) {

  run_data         <- reactiveVal(NULL)   # raw loaded run
  corrected_run    <- reactiveVal(NULL)   # run with patched day + recomputed kinematics
  scan_dates_store <- reactiveVal(NULL)   # named character vector: filename -> "YYYY-MM-DD"
  scan_files_store <- reactiveVal(character()) # image filenames detected before analysis
  table_trigger    <- reactiveVal(0L)     # bump to force date-table re-render
  days_applied     <- reactiveVal(FALSE)  # TRUE only after Apply Days is clicked
  applied_signature <- reactiveVal(NULL)
  applied_days_store <- reactiveVal(NULL) # named integer vector: filename -> day
  session_id <- gsub("[^A-Za-z0-9_-]", "-", session$token %||% paste0(Sys.getpid(), "-", as.integer(Sys.time())))
  session_root <- file.path(tempdir(), paste0("grayleafspotr-", session_id))
  session_input_dir <- file.path(session_root, "images")
  session_output_dir <- file.path(session_root, "outputs")
  overlay_resource_prefix <- paste0("gls-overlays-", session_id)
  uploaded_image_names <- reactiveVal(character())

  session$onSessionEnded(function() {
    if (overlay_resource_prefix %in% names(shiny::resourcePaths())) {
      shiny::removeResourcePath(overlay_resource_prefix)
    }
    unlink(session_root, recursive = TRUE, force = TRUE)
  })

  # ---- helpers --------------------------------------------------------

  resolve_run_dir <- function(run) {
    dir <- run$run$outputDir %||% run$run$output_dir
    if (is.null(dir) || !nzchar(dir)) return(NULL)
    if (grepl("^(/|~|[A-Za-z]:)", dir)) return(normalizePath(dir, mustWork = FALSE))
    clean    <- sub("^inst/", "", dir)
    resolved <- system.file(clean, package = "grayleafspotr")
    if (nzchar(resolved)) return(resolved)
    normalizePath(dir, mustWork = FALSE)
  }

  resolve_overlay_dir <- function(run) {
    od <- run$run$overlay_dir
    if (!is.null(od) && nzchar(od) && dir.exists(od)) return(od)
    run_dir <- resolve_run_dir(run)
    if (is.null(run_dir)) return(NULL)
    file.path(run_dir, "overlays")
  }

  list_image_files <- function(dir) {
    if (!nzchar(dir) || !dir.exists(dir)) return(character())
    pattern <- "\\.(png|jpg|jpeg|tif|tiff)$"
    paths <- list.files(dir, recursive = TRUE, full.names = TRUE, ignore.case = TRUE)
    paths <- paths[grepl(pattern, paths, ignore.case = TRUE)]
    sort(paths)
  }

  scan_image_dates <- function(dir) {
    paths <- list_image_files(dir)
    if (!length(paths)) {
      return(list(files = character(), dates = NULL))
    }
    files <- basename(paths)
    dates <- vapply(paths, function(path) {
      info <- tryCatch(file.info(path), error = function(e) NULL)
      if (!is.null(info) && !is.na(info$mtime)) as.character(as.Date(info$mtime))
      else                                      as.character(Sys.Date())
    }, character(1))
    names(dates) <- files
    list(files = files, dates = dates)
  }

  unique_upload_names <- function(names) {
    ext <- tools::file_ext(names)
    stem <- tools::file_path_sans_ext(basename(names))
    out <- character(length(names))
    seen <- character()
    for (i in seq_along(names)) {
      candidate <- if (nzchar(ext[[i]])) paste0(stem[[i]], ".", ext[[i]]) else stem[[i]]
      n <- 2L
      while (candidate %in% seen) {
        candidate <- if (nzchar(ext[[i]])) {
          paste0(stem[[i]], "_", n, ".", ext[[i]])
        } else {
          paste0(stem[[i]], "_", n)
        }
        n <- n + 1L
      }
      out[[i]] <- candidate
      seen <- c(seen, candidate)
    }
    out
  }

  reset_day_assignment <- function(scanned) {
    scan_files_store(scanned$files)
    scan_dates_store(scanned$dates)
    applied_signature(NULL)
    applied_days_store(NULL)
    days_applied(FALSE)
    table_trigger(table_trigger() + 1L)
  }

  run_r_fallback_analysis <- function(input_dir, output_dir, run_name, plate_diameter_mm) {
    image_paths <- list_image_files(input_dir)
    if (!length(image_paths)) {
      stop("No uploaded image files were found for analysis.")
    }
    analyze_image <- getFromNamespace("analyze_grayleafspot_image", "grayleafspotr")
    compute_kinematics <- getFromNamespace("compute_kinematics", "grayleafspotr")
    run_id <- paste(
      format(Sys.time(), "%Y%m%d-%H%M%S"),
      if (nzchar(run_name)) gsub("[^A-Za-z0-9_-]+", "-", run_name) else "run",
      sep = "-"
    )
    run_dir <- file.path(output_dir, run_id)
    dir.create(run_dir, recursive = TRUE, showWarnings = FALSE)
    results <- lapply(image_paths, analyze_image, plate_diameter_mm = plate_diameter_mm)
    results <- compute_kinematics(results)
    grayleafspotr::write_grayleafspot_results(
      results,
      output_dir = run_dir,
      engine = "r-fallback",
      engine_model = "legacy-r-heuristic",
      run_name = run_id
    )
  }

  run_analysis <- function(input_dir, output_dir, run_name, plate_diameter_mm) {
    tryCatch(
      grayleafspotr::grayleafspot_analyze(
        input_dir         = input_dir,
        output_dir        = output_dir,
        run_name          = run_name,
        plate_diameter_mm = plate_diameter_mm,
        verbose           = FALSE
      ),
      error = function(e) {
        msg <- conditionMessage(e)
        if (!grepl("Python ML dependencies|No Python executable|GRAYLEAFSPOTR_PYTHON", msg)) {
          stop(e)
        }
        showNotification(
          "Python ML dependencies are unavailable on this server; using the R fallback analyzer.",
          type = "warning",
          duration = 10
        )
        run_r_fallback_analysis(input_dir, output_dir, run_name, plate_diameter_mm)
      }
    )
  }

  match_days_to_results <- function(result_filenames, days_by_filename) {
    if (is.null(days_by_filename) || !length(days_by_filename)) {
      return(rep(NA_integer_, length(result_filenames)))
    }
    days <- unname(days_by_filename[result_filenames])
    missing <- is.na(days)
    if (any(missing)) {
      days[missing] <- unname(days_by_filename[basename(result_filenames[missing])])
    }
    if (any(is.na(days)) && length(days_by_filename) == length(result_filenames)) {
      days[is.na(days)] <- unname(days_by_filename)[is.na(days)]
    }
    as.integer(days)
  }

  patch_run_days <- function(run, days_by_filename) {
    if (is.null(run$results) || !nrow(run$results)) return(run)
    days <- match_days_to_results(run$results$filename, days_by_filename)
    if (any(is.na(days))) return(run)
    run$results$day <- days
    run$results <- recompute_kinematics(run$results)
    run$raw_results <- patch_raw_results_days(run$raw_results, days_by_filename)
    run
  }

  patch_raw_results_days <- function(raw_results, days_by_filename) {
    if (is.null(raw_results) || !length(raw_results)) return(raw_results)
    raw_filenames <- vapply(raw_results, function(result) {
      result$filename %||% ""
    }, character(1))
    days <- match_days_to_results(raw_filenames, days_by_filename)
    if (any(is.na(days))) return(raw_results)

    for (i in seq_along(raw_results)) {
      raw_results[[i]]$day <- days[[i]]
    }
    recompute_raw_kinematics(raw_results)
  }

  recompute_raw_kinematics <- function(raw_results) {
    if (length(raw_results) < 2) return(raw_results)
    raw_days <- vapply(raw_results, function(result) {
      result$day %||% NA_real_
    }, numeric(1))
    raw_filenames <- vapply(raw_results, function(result) {
      result$filename %||% ""
    }, character(1))
    ordered_idx <- order(raw_days, raw_filenames)
    ordered <- raw_results[ordered_idx]
    day <- vapply(ordered, function(result) {
      result$day %||% NA_real_
    }, numeric(1))
    radius <- vapply(ordered, function(result) {
      result$morphology$equivalentRadiusMm %||% NA_real_
    }, numeric(1))
    area <- vapply(ordered, function(result) {
      result$morphology$areaMm2 %||% NA_real_
    }, numeric(1))

    gap <- pmax(diff(day), 1)
    rv <- c(NA_real_, diff(radius) / gap)
    ag <- c(NA_real_, diff(area) / gap)
    rg <- c(NA_real_, diff(log1p(area)) / gap)
    ra <- c(NA_real_, diff(rv) / gap)

    for (i in seq_along(ordered)) {
      ordered[[i]]$kinematics$radialVelocity <- rv[[i]]
      ordered[[i]]$kinematics$areaGrowthRate <- ag[[i]]
      ordered[[i]]$kinematics$relativeGrowthRate <- rg[[i]]
      ordered[[i]]$kinematics$radialAcceleration <- ra[[i]]
    }
    ordered
  }

  persist_run_results <- function(run) {
    run_dir <- resolve_run_dir(run)
    if (is.null(run_dir) || !dir.exists(run_dir)) return(FALSE)
    session_outputs <- normalizePath(session_output_dir, winslash = "/", mustWork = FALSE)
    run_dir_norm <- normalizePath(run_dir, winslash = "/", mustWork = FALSE)
    if (!startsWith(run_dir_norm, paste0(session_outputs, "/"))) return(FALSE)

    csv_path <- run$run$analysisCsv %||% run$run$analysis_csv %||% file.path(run_dir, "analysis.csv")
    json_path <- run$run$analysisJson %||% run$run$analysis_json %||% file.path(run_dir, "analysis.json")
    csv_path <- normalizePath(csv_path, winslash = "/", mustWork = FALSE)
    json_path <- normalizePath(json_path, winslash = "/", mustWork = FALSE)

    readr::write_csv(run$results, csv_path)
    if (!is.null(run$raw_results) && length(run$raw_results)) {
      jsonlite::write_json(run$raw_results, json_path, pretty = TRUE,
                           auto_unbox = TRUE, null = "null")
    }
    TRUE
  }

  current_day_assignment_signature <- reactive({
    fns <- scan_files_store()
    if (is.null(fns) || !length(fns)) return(NULL)
    dates <- vapply(seq_along(fns), function(i) {
      value <- input[[paste0("img_date_", i)]]
      if (is.null(value)) "" else as.character(as.Date(value))
    }, character(1))
    paste(c(as.character(input$experiment_date %||% ""), fns, dates), collapse = "\r")
  })

  # Re-compute kinematic columns from the flat results tibble after days change.
  # Assumes a single time-series (one plate). Rows are sorted by day in place.
  recompute_kinematics <- function(df) {
    if (nrow(df) < 2) return(df)
    if ("filename" %in% names(df)) {
      df <- df[order(df$day, df$filename), ]
    } else {
      df <- df[order(df$day), ]
    }
    d   <- df$day
    r   <- df$radius_mm   %||% df$radius   %||% rep(NA_real_, nrow(df))
    a   <- df$area_mm2    %||% df$area     %||% rep(NA_real_, nrow(df))
    gap <- pmax(diff(d), 1L)
    rv  <- c(NA_real_, diff(r)         / gap)
    ag  <- c(NA_real_, diff(a)         / gap)
    rg  <- c(NA_real_, diff(log1p(a))  / gap)
    ra  <- c(NA_real_, diff(rv)        / gap)
    if ("radial_velocity_mm_per_day"   %in% names(df)) df$radial_velocity_mm_per_day   <- rv
    if ("area_growth_rate_mm2_per_day" %in% names(df)) df$area_growth_rate_mm2_per_day <- ag
    if ("relative_growth_rate_per_day" %in% names(df)) df$relative_growth_rate_per_day <- rg
    if ("radial_acceleration"          %in% names(df)) df$radial_acceleration           <- ra
    df
  }

  # ---- sidebar buttons (disabled until Apply Days after first load) --------

  output$sidebar_buttons <- renderUI({
    run_mode <- identical(input$data_source, "run")
    button_label <- if (run_mode) "Run" else "Load"
    sig <- current_day_assignment_signature()
    blocked <- run_mode && (
      is.null(sig) ||
        !isTRUE(days_applied()) ||
        !identical(sig, applied_signature())
    )

    load_btn <- if (blocked) {
      tooltip(
        # tooltip() requires a non-disabled wrapper to fire on hover
        tags$span(
          actionButton("load_btn", button_label,
                       class    = "btn-secondary w-100 mt-2",
                       icon     = bs_icon("play-fill"),
                       disabled = "disabled"),
          style = "display:block; width:100%;"
        ),
        "Apply imaging dates before running the analysis",
        placement = "right"
      )
    } else {
      actionButton("load_btn", button_label,
                   class = "btn-primary w-100 mt-2",
                   icon  = bs_icon("play-fill"))
    }

    layout_column_wrap(
      width = 1 / 2, fill = FALSE,
      load_btn,
      actionButton("clear_btn", "Clear",
                   class = "btn-outline-secondary w-100 mt-2",
                   icon  = bs_icon("x-circle"))
    )
  })

  # ---- load / clear ---------------------------------------------------

  observeEvent(input$clear_btn, {
    run_data(NULL); corrected_run(NULL); scan_dates_store(NULL); scan_files_store(character())
    uploaded_image_names(character())
    applied_signature(NULL); applied_days_store(NULL)
    days_applied(FALSE)
    unlink(session_input_dir, recursive = TRUE, force = TRUE)
    unlink(session_output_dir, recursive = TRUE, force = TRUE)
  })

  observeEvent(input$load_btn, {
    if (identical(input$data_source, "run")) {
      sig <- current_day_assignment_signature()
      if (is.null(sig) || !isTRUE(days_applied()) || !identical(sig, applied_signature())) {
        showNotification("Apply imaging dates before running the analysis.", type = "warning")
        return()
      }
    }
    withProgress(message = "Loading data...", value = 0.5, {
      tryCatch({
        result <- switch(
          input$data_source,
          "example" = grayleafspotr::example_grayleafspot_results(),
          "load" = {
            req(nchar(trimws(input$results_dir)) > 0)
            grayleafspotr::read_grayleafspot_results(trimws(input$results_dir))
          },
          "run" = {
            req(length(uploaded_image_names()) > 0)
            run_nm <- if (nchar(trimws(input$run_name)) > 0) trimws(input$run_name) else "run"
            setProgress(message = "Running analysis (this may take a few minutes)...")
            run_analysis(
              input_dir         = session_input_dir,
              output_dir        = session_output_dir,
              run_name          = run_nm,
              plate_diameter_mm = input$plate_mm
            )
          }
        )
        if (identical(input$data_source, "run")) {
          result <- patch_run_days(result, applied_days_store())
          persist_run_results(result)
        }
        run_data(result)
        corrected_run(result)
        if (identical(input$data_source, "run")) {
          days_applied(TRUE)
          showNotification("Analysis complete with the applied imaging dates.",
                           type = "message", duration = 6)
        } else {
          days_applied(FALSE)
          showNotification("Data loaded successfully.", type = "message", duration = 6)
        }
      }, error = function(e) {
        showNotification(paste("Error:", conditionMessage(e)), type = "error", duration = 15)
      })
    })
  })

  output$uploaded_files_status <- renderUI({
    req(identical(input$data_source, "run"))
    n <- length(uploaded_image_names())
    if (n == 0) {
      return(p(bs_icon("info-circle"), " Upload images to assign dates and run analysis.",
               class = "text-muted small mb-2"))
    }
    p(bs_icon("check-circle-fill", class = "text-success"),
      paste(n, "image file(s) uploaded for this session."),
      class = "small text-success mb-2")
  })

  output$download_outputs_ui <- renderUI({
    req(identical(input$data_source, "run"))
    req(corrected_run())
    run_dir <- resolve_run_dir(corrected_run())
    req(!is.null(run_dir), dir.exists(run_dir))
    downloadButton("download_outputs_zip", "Download full outputs",
                   class = "btn-outline-primary w-100 mt-2")
  })

  output$download_outputs_zip <- downloadHandler(
    filename = function() {
      run_id <- corrected_run()$run$id %||% "grayleafspotr"
      paste0(run_id, "-outputs.zip")
    },
    content = function(file) {
      req(corrected_run())
      run_dir <- resolve_run_dir(corrected_run())
      req(!is.null(run_dir), dir.exists(run_dir))
      old_wd <- getwd()
      on.exit(setwd(old_wd), add = TRUE)
      setwd(dirname(run_dir))
      utils::zip(zipfile = file, files = basename(run_dir), flags = "-r9X")
    },
    contentType = "application/zip"
  )

  # When run data changes, refresh the editable date table from the active source.
  observeEvent(run_data(), {
    req(run_data())
    if (!identical(isolate(input$data_source), "run")) {
      fns <- run_data()$results$filename
      dates <- rep(as.character(Sys.Date()), length(fns))
      names(dates) <- fns
      scan_files_store(fns)
      scan_dates_store(dates)
    }
    table_trigger(table_trigger() + 1L)
  }, ignoreNULL = TRUE)

  # ---- status panel ---------------------------------------------------

  output$status_ui <- renderUI({
    if (is.null(run_data())) {
      p(bs_icon("circle", class = "text-secondary"), " No data loaded",
        class = "text-muted small mb-0")
    } else {
      data    <- grayleafspotr::as_grayleafspot_growth_data(run_data())
      n_img   <- nrow(data)
      n_plate <- if ("plate" %in% names(data)) length(unique(data$plate)) else n_img
      days_ok <- !all(is.na(data$day) | data$day == 0)
      tagList(
        p(
          bs_icon("check-circle-fill", class = "text-success"),
          tags$strong(paste(n_img, "images")),
          if (n_plate > 0) paste0("across ", n_plate, " plate(s)") else NULL,
          class = "small mb-1"
        ),
        if (!days_ok && identical(input$data_source, "run"))
          p(bs_icon("exclamation-triangle-fill", class = "text-warning"),
            " Day codes not detected — assign imaging dates before running.",
            class = "small text-warning mb-1"),
        if (!is.null(run_data()$run$id))
          p(bs_icon("tag", class = "text-muted"),
            tags$code(run_data()$run$id, style = "font-size:0.75rem"),
            class = "small text-muted mb-0")
      )
    }
  })

  # ---- day assignment panel -------------------------------------------

  output$day_assignment_panel <- renderUI({
    req(identical(input$data_source, "run"))
    tagList(
      tags$hr(class = "my-3"),
      div(
        class = "fw-semibold small mb-2",
        tagList(bs_icon("calendar2-range"), " Assign Days from Imaging Dates")
      ),
      p("Set the Experiment Start Date and imaging date for each image.",
        class = "text-muted small mb-2"),

      dateInput("experiment_date", "Experiment Start Date", value = Sys.Date()),

      uiOutput("imaging_dates_table"),

      div(
        class = "mt-2",
        actionButton("apply_dates_btn", "Apply Days to Graphs",
                     class = "btn-success w-100",
                     icon  = bs_icon("check-lg")),
        div(
          class = "mt-2",
          uiOutput("apply_days_status")
        )
      )
    )
  })

  observeEvent(input$image_uploads, {
    if (!identical(input$data_source, "run")) return()
    uploads <- input$image_uploads
    if (is.null(uploads) || !nrow(uploads)) {
      uploaded_image_names(character())
      reset_day_assignment(list(files = character(), dates = NULL))
      return()
    }

    unlink(session_input_dir, recursive = TRUE, force = TRUE)
    dir.create(session_input_dir, recursive = TRUE, showWarnings = FALSE)
    dir.create(session_output_dir, recursive = TRUE, showWarnings = FALSE)

    upload_names <- unique_upload_names(uploads$name)
    ok <- file.copy(uploads$datapath, file.path(session_input_dir, upload_names),
                    overwrite = TRUE)
    if (!all(ok)) {
      showNotification("Some uploaded images could not be copied for analysis.",
                       type = "warning", duration = 8)
    }

    uploaded_image_names(upload_names[ok])
    reset_day_assignment(scan_image_dates(session_input_dir))
  }, ignoreInit = FALSE)

  observeEvent(input$data_source, {
    if (!identical(input$data_source, "run")) return()
    reset_day_assignment(scan_image_dates(session_input_dir))
  }, ignoreInit = TRUE)

  # Render the editable date table; only re-renders when table_trigger changes
  output$imaging_dates_table <- renderUI({
    table_trigger()         # reactive dependency — isolate everything else below
    req(identical(input$data_source, "run"))

    fns    <- scan_files_store()
    cached <- isolate(scan_dates_store())
    exp_d  <- isolate(input$experiment_date) %||% Sys.Date()

    if (!length(fns)) {
      msg <- "Upload images to load imaging dates."
      return(p(bs_icon("info-circle"), msg, class = "text-muted small mb-0"))
    }

    # Determine default imaging date for each image
    default_for <- function(fn, i) {
      if (!is.null(cached) && fn %in% names(cached)) return(as.Date(cached[[fn]]))
      existing <- if (!is.null(run_data())) run_data()$results$day[i] else NA_integer_
      if (!is.null(existing) && !is.na(existing) && existing > 0)
        return(as.Date(exp_d) + as.integer(existing))
      Sys.Date()
    }

    # Register a live "Day" preview output for each row (using local() to capture i)
    for (i in seq_along(fns)) {
      local({
        ii <- i
        output[[paste0("day_preview_", ii)]] <- renderText({
          d_img <- input[[paste0("img_date_", ii)]]
          d_exp <- input$experiment_date
          if (is.null(d_img) || is.null(d_exp)) return("\u2013")
          day <- as.integer(as.Date(d_img) - as.Date(d_exp))
          if (day < 0) paste0(day, " \u26a0") else as.character(day)
        })
      })
    }

    header <- tags$thead(tags$tr(
      tags$th("Filename",     class = "text-muted fw-normal small", style = "width:45%"),
      tags$th("Imaging Date", class = "text-muted fw-normal small", style = "width:35%"),
      tags$th("Day",          class = "text-muted fw-normal small", style = "width:20%")
    ))

    rows <- lapply(seq_along(fns), function(i) {
      tags$tr(
        tags$td(
          tags$code(fns[i], style = "font-size:0.8rem; word-break:break-all;"),
          style = "vertical-align:middle; padding:4px 6px;"
        ),
        tags$td(
          dateInput(paste0("img_date_", i), NULL,
                    value = default_for(fns[i], i), width = "100%"),
          style = "padding:2px 4px;"
        ),
        tags$td(
          textOutput(paste0("day_preview_", i), inline = TRUE),
          style = "vertical-align:middle; padding:4px 6px; font-weight:600;"
        )
      )
    })

    tags$table(class = "table table-sm table-borderless mb-0",
               header, tags$tbody(rows))
  })

  output$apply_days_status <- renderUI({
    sig <- current_day_assignment_signature()
    if (!isTRUE(days_applied()) || is.null(sig) || !identical(sig, applied_signature())) {
      return(span("Apply the dates before running.", class = "small text-muted align-middle"))
    }
    days <- applied_days_store()
    span(
      bs_icon("check-circle-fill", class = "text-success"),
      paste("Days applied:", paste(sort(unname(days)), collapse = ", ")),
      class = "small text-success align-middle"
    )
  })

  # Apply button: read all date inputs and store days for the next analysis run
  observeEvent(input$apply_dates_btn, {
    req(identical(input$data_source, "run"))
    fns   <- scan_files_store()
    req(length(fns) > 0)
    exp_d <- as.Date(input$experiment_date)

    dates <- vapply(seq_along(fns), function(i) {
      d_img <- input[[paste0("img_date_", i)]]
      if (is.null(d_img)) as.character(Sys.Date()) else as.character(as.Date(d_img))
    }, character(1))
    names(dates) <- fns
    days <- vapply(seq_along(fns), function(i) {
      as.integer(as.Date(dates[[i]]) - exp_d)
    }, integer(1))
    names(days) <- fns
    scan_dates_store(dates)
    applied_days_store(days)
    applied_signature(current_day_assignment_signature())
    days_applied(TRUE)

    if (!is.null(run_data()) && identical(input$data_source, "run")) {
      patched <- patch_run_days(run_data(), days)
      persist_run_results(patched)
      run_data(patched)
      corrected_run(patched)
    }
  })

  # ---- overlays -------------------------------------------------------

  observe({
    req(run_data())
    od <- resolve_overlay_dir(run_data())
    if (!is.null(od) && dir.exists(od)) addResourcePath(overlay_resource_prefix, od)
  })

  output$overlay_gallery <- renderUI({
    req(run_data())
    od <- resolve_overlay_dir(run_data())

    if (is.null(od) || !dir.exists(od)) {
      return(card(card_body(
        p(bs_icon("info-circle"), tags$strong(" No overlays available"), class = "mb-1"),
        p("Overlays are generated when running a new analysis.",
          class = "text-muted small mb-0")
      )))
    }

    files <- sort(list.files(od, pattern = "\\.png$", ignore.case = TRUE))
    if (length(files) == 0)
      return(card(p(bs_icon("folder-x", class = "text-warning"),
                    " Overlays directory is empty.", class = "text-muted p-3")))

    day_label <- function(fname) {
      m <- regmatches(fname, regexpr("(?i)(d(?:ay[_-]?)?)(\\d+)", fname, perl = TRUE))
      if (length(m) && nzchar(m))
        paste0("Day ", as.integer(regmatches(m, regexpr("\\d+", m))))
      else
        tools::file_path_sans_ext(fname)
    }

    cards <- lapply(files, function(f) {
      card(
        full_screen = TRUE,
        card_header(class = "d-flex align-items-center gap-2", bs_icon("image"), day_label(f)),
        tags$img(src   = paste0(overlay_resource_prefix, "/", f),
                 alt   = tools::file_path_sans_ext(f),
                 style = "width:100%; height:auto; display:block; border-radius:0 0 4px 4px;")
      )
    })
    do.call(layout_column_wrap, c(list(width = "320px"), cards))
  })

  # ---- plots & data table (all use corrected_run) ---------------------

  make_plot <- function(plot_fn) {
    renderPlot({
      req(corrected_run())
      suppressWarnings(plot_fn(corrected_run()))
    })
  }

  output$plot_expansion      <- make_plot(grayleafspotr::plot_colony_expansion)
  output$plot_roughness      <- make_plot(grayleafspotr::plot_growth_roughness)
  output$plot_stress         <- make_plot(grayleafspotr::plot_stress_remodeling)
  output$plot_texture        <- make_plot(grayleafspotr::plot_texture_organization)
  output$plot_shape_stress   <- make_plot(grayleafspotr::plot_shape_vs_stress)
  output$plot_radial_area    <- make_plot(grayleafspotr::plot_radial_growth_area)
  output$plot_heatmap        <- make_plot(grayleafspotr::plot_feature_heatmap)
  output$plot_radial_profile <- make_plot(grayleafspotr::plot_radial_profile)

  output$data_table <- renderDT({
    req(corrected_run())
    df <- grayleafspotr::as_grayleafspot_growth_data(corrected_run())
    datatable(df, rownames = FALSE, filter = "top", extensions = "Buttons",
              options = list(scrollX = TRUE, pageLength = 20, dom = "Bfrtip",
                             buttons = list("csv", "excel", "copy")))
  })
}

# ---------------------------------------------------------------------------
shinyApp(ui, server)
