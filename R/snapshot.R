read_snapshot <- function() {
  path <- system.file("extdata", "alachua_snapshot.rds", package = "lifewatt")
  if (!nzchar(path)) stop("Install lifewatt before loading the snapshot.", call. = FALSE)
  readRDS(path)
}

#' Load the Alachua County community health snapshot
#'
#' Loads 58 tracts matched by 11-digit GEOID. Health values are official
#' 2020-2024 all-cause death rates per 100,000 population. They are crude
#' rates, not age-adjusted rates or life expectancy. Population is a separate
#' 2020 Census context field and is not used to recalculate health rates.
#' @return A data frame with tract identifiers, internal-point coordinates,
#'   population, death rates, death counts, small-count flags and provenance.
#' @export
#' @examples
#' head(community_data())
community_data <- function() read_snapshot()$communities

#' Load the demonstration AI computing facility
#'
#' The facility identity and AI system year are documented by UF. Coordinates
#' are Census street-address interpolations, not a surveyed building footprint.
#' @return A one-row data frame with location, provenance and uncertainty.
#' @export
#' @examples
#' example_facility()
example_facility <- function() read_snapshot()$facility

#' Load county-level life expectancy background
#'
#' This county outcome must not be assigned to individual tracts or interpreted
#' as the life expectancy of residents inside a distance buffer.
#' @return A one-row data frame for Alachua County, 2022-2024.
#' @export
#' @examples
#' county_context()
county_context <- function() read_snapshot()$county_context
