test_that("geographic joins preserve all official tracts and leading zeros", {
  d <- community_data()
  expect_equal(nrow(d), 58L)
  expect_equal(length(unique(d$geoid)), 58L)
  expect_true(all(grepl("^12001[0-9]{6}$", d$geoid)))
  expect_equal(d$death_rate_per_100k[d$geoid == "12001002210"], 942.1)
  expect_equal(d$deaths_2020_2024[d$geoid == "12001000302"], 145L)
  expect_equal(sum(d$small_count), 2L)
  expect_true(all(d$health_period == "2020-2024"))
})

test_that("great-circle selection has a known distance and inclusive boundary", {
  d <- community_data()[1:3, ]
  d$geoid <- c("a", "b", "c")
  d$longitude <- c(0, 1, 2)
  d$latitude <- c(0, 0, 0)
  p <- nearby_communities(0, 0, 112, d)
  expect_identical(p$geoid, c("a", "b"))
  expect_equal(p$distance_km, c(0, 111.1950802), tolerance = 1e-6)
  expect_identical(nearby_communities(0, 0, 0, d)$geoid, "a")
  expect_equal(nrow(nearby_communities(-80, 20, 0, d)), 0L)
})

test_that("invalid coordinates, IDs, counts and mixed periods fail clearly", {
  expect_error(nearby_communities(-181, 30), "longitude")
  expect_error(nearby_communities(-82, NA_real_), "latitude")
  expect_error(nearby_communities(-82, 30, -1), "radius")
  d <- community_data()[1:2, ]
  d$geoid[2] <- d$geoid[1]
  expect_error(nearby_communities(0, 0, communities = d), "unique")
  d <- community_data()[1:2, ]
  d$deaths_2020_2024[1] <- 1.5
  expect_error(nearby_communities(0, 0, communities = d), "integers")
  d <- community_data()[1:2, ]
  d$health_period[2] <- "2015-2019"
  expect_error(nearby_communities(0, 0, communities = d), "period")
})

test_that("small counts and missing rates never silently lower band summaries", {
  d <- community_data()[1:3, ]
  d$longitude <- c(0, 0.01, 0.02)
  d$latitude <- 0
  d$death_rate_per_100k <- c(0, 100, NA_real_)
  d$deaths_2020_2024 <- c(0L, 10L, 10L)
  p <- nearby_communities(0, 0, 10, d)
  s <- compare_communities(p, c(0, 5, 10))
  expect_equal(s$n_tracts, c(3, 0))
  expect_equal(s$n_usable, c(1, 0))
  expect_equal(s$n_excluded, c(2, 0))
  expect_equal(s$median_tract_rate[1], 100)
  expect_true(is.na(s$median_tract_rate[2]))
  expect_error(compare_communities(p, c(0, 1)), "cover")
})

test_that("CSV export preserves query and source and protects existing files", {
  f <- example_facility()
  p <- nearby_communities(f$longitude, f$latitude, 5)
  file <- tempfile(fileext = ".csv")
  export_communities(p, file)
  back <- read.csv(file, colClasses = c(geoid = "character"))
  expect_equal(back$geoid, p$geoid)
  expect_equal(back$distance_km, p$distance_km, tolerance = 1e-10)
  expect_true(all(back$health_period == "2020-2024"))
  expect_true(all(nzchar(back$health_source)))
  expect_error(export_communities(p, file), "exists")
})

test_that("empty geographic selections and plotting complete without fabrication", {
  p <- nearby_communities(0, 0, 10)
  expect_equal(sum(compare_communities(p)$n_tracts), 0)
  file <- tempfile(fileext = ".pdf")
  grDevices::pdf(file)
  on.exit(grDevices::dev.off())
  expect_invisible(plot_communities(p))
  expect_invisible(plot_communities(p, "distance"))
  expect_true(all(county_context()$geography_level == "County; not a tract outcome"))
})
