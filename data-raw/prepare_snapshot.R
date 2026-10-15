# Rebuild the installed snapshot from the included official-source inputs.
# Run from the package directory: Rscript data-raw/prepare_snapshot.R
library(jsonlite)
root <- "data-raw/input"
features <- fromJSON(file.path(root, "census-tracts-2020.json"),
                     simplifyVector = FALSE)$features
health <- read.csv(file.path(root, "alachua-health-2020-2024.csv"),
                   colClasses = c("character", "numeric", "integer"))
# The official UI omits trailing decimal zeros (22.1 means tract 22.10).
health$geoid <- paste0("12001", sprintf("%06d", round(as.numeric(health$tract) * 100)))
stopifnot(nrow(health) == 58L, !anyDuplicated(health$geoid))
communities <- do.call(rbind, lapply(features, function(f) {
  a <- f$attributes
  data.frame(geoid = a$GEOID, tract = a$BASENAME, name = a$NAME,
             longitude = as.numeric(a$INTPTLON), latitude = as.numeric(a$INTPTLAT),
             population_2020 = a$POP100, stringsAsFactors = FALSE)
}))
stopifnot(nrow(communities) == 58L, !anyDuplicated(communities$geoid),
          setequal(communities$geoid, health$geoid))
health <- health[match(communities$geoid, health$geoid), ]
communities$death_rate_per_100k <- health$death_rate_per_100k
communities$deaths_2020_2024 <- health$deaths_2020_2024
communities$small_count <- communities$deaths_2020_2024 < 5L
communities$health_period <- "2020-2024"
communities$boundary_vintage <- "2020"
communities$rate_type <- "Crude; not age-adjusted"
communities$distance_reference <- "2020 Census tract internal point"
communities$health_source <- paste0("https://www.flhealthcharts.gov/ChartsDashboards/",
  "rdPage.aspx?rdReport=ChartsMaps.ChartsMapper")
communities <- communities[order(communities$geoid), ]
rownames(communities) <- NULL
boundaries <- lapply(features, function(f) {
  list(geoid = f$attributes$GEOID,
       rings = lapply(f$geometry$rings, function(r)
         matrix(as.numeric(unlist(r)), ncol = 2L, byrow = TRUE)))
})
geocode <- fromJSON(file.path(root, "facility-geocode.json"))$result$addressMatches
stopifnot(nrow(geocode) == 1L)
facility <- data.frame(
  facility_id = "uf-hipergator-ai", name = "UF HiPerGator AI / East Campus Data Center",
  longitude = geocode$coordinates$x, latitude = geocode$coordinates$y,
  address = geocode$matchedAddress, ai_system_year = 2021L,
  coordinate_method = "Census street-address interpolation; approximate site location",
  ai_source = "https://news.ufl.edu/2025/05/the-fourth-generation-model-of-ufs-hipergator/",
  address_source = "https://explore.jobs.ufl.edu/en-us/job/541158/computer-operator-i",
  snapshot_date = "2026-10-14", stringsAsFactors = FALSE)
county <- data.frame(
  county = "Alachua", county_fips = "12001", period = "2022-2024",
  life_expectancy_years = 78.9, lower_95 = 78.5, upper_95 = 79.2,
  geography_level = "County; not a tract outcome",
  source = paste0("https://www.flhealthcharts.gov/ChartsDashboards/rdPage.aspx?",
                  "rdReport=ChartsMaps.LifeExpectancyReport"))
snapshot <- list(communities = communities, boundaries = boundaries,
                 facility = facility, county_context = county,
                 snapshot_date = "2026-10-14")
dir.create("inst/extdata", recursive = TRUE, showWarnings = FALSE)
saveRDS(snapshot, "inst/extdata/alachua_snapshot.rds", version = 2, compress = "xz")
write.csv(communities, "inst/extdata/alachua_communities.csv", row.names = FALSE)
write.csv(facility, "inst/extdata/example_facility.csv", row.names = FALSE)
write.csv(county, "inst/extdata/county_life_expectancy.csv", row.names = FALSE)
cat("Matched", nrow(communities), "of", nrow(health), "health rows by GEOID.\n")
cat("Small-count tracts:", sum(communities$small_count), "\n")
