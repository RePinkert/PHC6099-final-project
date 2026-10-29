# health_measure(): CDC PLACES ZCTA-level adult health estimates (2025 release).
# Data are queried from data.cdc.gov at run time (dataset qnzd-25i4); nothing is bundled.
# Only BRFSS 2023 measures are returned (candidate-list E1: the 5 BRFSS 2022 measures are excluded).

.places_url <- function(zip5) {
  sprintf("https://data.cdc.gov/resource/qnzd-25i4.csv?locationname=%s&$limit=200",
          utils::URLencode(zip5, reserved = TRUE))
}

.places_fetch <- function(zip5) {
  tryCatch(
    utils::read.csv(.places_url(zip5), colClasses = "character"),
    error = function(e) {
      stop("Could not download CDC PLACES data from data.cdc.gov. Check the internet connection.",
           call. = FALSE)
    }
  )
}

#' Adult health estimates for a ZIP code (CDC PLACES)
#'
#' Returns model-based prevalence estimates of adult health measures (for
#' example diabetes, high blood pressure and current smoking) for the ZIP Code
#' Tabulation Area (ZCTA) that matches a ZIP code, from the CDC PLACES 2025
#' release. Only measures based on 2023 BRFSS data are returned. The values are
#' crude prevalence (percent of adults), not mortality or life expectancy.
#'
#' The data are downloaded from data.cdc.gov each time the function is called,
#' so an internet connection is required. A ZIP code is treated as the ZCTA with
#' the same five digits; the two usually, but not always, cover the same area.
#'
#' @param zip A character or numeric US ZIP code.
#' @param measure Optional character vector of PLACES measure IDs, for example
#'   `"DIABETES"` or `c("DIABETES", "BPHIGH")`. `NULL` (the default) returns
#'   every available measure.
#' @return A data.frame with one row per measure: `zip`, `measure_id`,
#'   `measure`, `category`, `value` (percent), `low_ci` and `high_ci` (95%
#'   confidence limits), `unit`, `value_type`, `brfss_year`,
#'   `total_population`, and the provenance columns `source`, `level`,
#'   `degraded_from`, `mapping_vintage` and `provisional` (always `FALSE`: the
#'   PLACES 2025 release is a published cross-section, not a provisional
#'   vintage).
#'
#'   The number of rows depends on the ZIP: PLACES publishes at most 35
#'   BRFSS-2023 measures per ZCTA and omits the measures suppressed for that
#'   ZCTA (ZIP 32601 has 28). A measure that exists nationally but is
#'   suppressed for the requested ZIP therefore fails with the same
#'   "not available" error as a misspelled measure ID.
#' @export
#'
#' @examples
#' \dontrun{
#' health_measure("32601")
#' health_measure("32601", measure = c("DIABETES", "BPHIGH"))
#' }
health_measure <- function(zip, measure = NULL) {
  z <- .zip5(zip)
  d <- .places_fetch(z)
  need <- c("year", "measureid", "data_value", "data_value_type",
            "low_confidence_limit", "high_confidence_limit", "locationname")
  if (!all(need %in% names(d))) {
    stop("PLACES response schema unexpected (dataset qnzd-25i4 may have changed); refusing to guess.",
         call. = FALSE)
  }
  if (nrow(d) == 0L) {
    stop(sprintf(
      "No CDC PLACES estimates for ZIP %s (it may not be a ZCTA, or its population is too small).", z),
      call. = FALSE)
  }
  d <- d[d$data_value_type == "Crude prevalence", , drop = FALSE]
  d <- d[d$year == "2023", , drop = FALSE]
  if (nrow(d) == 0L) {
    stop(sprintf("No crude BRFSS-2023 PLACES estimates for ZIP %s (published rows are other vintages or value types).", z),
         call. = FALSE)
  }
  if (!is.null(measure)) {
    measure <- toupper(as.character(measure))
    bad <- setdiff(measure, d$measureid)
    if (length(bad) > 0L) {
      stop(sprintf(
        "Measure(s) not available for ZIP %s: %s. Available (BRFSS 2023): %s.",
        z, paste(bad, collapse = ", "), paste(sort(d$measureid), collapse = ", ")),
        call. = FALSE)
    }
    d <- d[d$measureid %in% measure, , drop = FALSE]
  }
  d <- d[order(d$category, d$measureid), , drop = FALSE]
  data.frame(
    zip = z,
    measure_id = d$measureid,
    measure = d$short_question_text,
    category = d$category,
    value = as.numeric(d$data_value),
    low_ci = as.numeric(d$low_confidence_limit),
    high_ci = as.numeric(d$high_confidence_limit),
    unit = "%",
    value_type = d$data_value_type,
    brfss_year = as.integer(d$year),
    total_population = as.integer(d$totalpopulation),
    source = "CDC PLACES 2025 release, ZCTA data (data.cdc.gov qnzd-25i4)",
    level = "zcta",
    degraded_from = "zip",
    mapping_vintage = "2020 ZCTA",
    provisional = FALSE,
    confidence_tier = .confidence_tier(rep("C", nrow(d))),
    stringsAsFactors = FALSE,
    row.names = NULL
  )
}
