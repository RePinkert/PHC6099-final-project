check_scalar <- function(x, name, lower, upper) {
  if (!is.numeric(x) || length(x) != 1L || !is.finite(x) ||
      x < lower || x > upper) {
    stop(name, " must be one finite number in [", lower, ", ", upper, "].",
         call. = FALSE)
  }
}

check_communities <- function(x) {
  required <- c("geoid", "longitude", "latitude", "death_rate_per_100k",
                "deaths_2020_2024", "health_period")
  if (!is.data.frame(x) || !all(required %in% names(x))) {
    stop("communities must contain: ", paste(required, collapse = ", "), call. = FALSE)
  }
  if (!is.character(x$geoid) || anyNA(x$geoid) || any(!nzchar(x$geoid)) ||
      anyDuplicated(x$geoid)) stop("geoid must be unique nonempty character IDs.", call. = FALSE)
  for (field in c("longitude", "latitude", "death_rate_per_100k", "deaths_2020_2024")) {
    if (!is.numeric(x[[field]])) stop(field, " must be numeric.", call. = FALSE)
  }
  if (any(!is.finite(x$longitude)) || any(abs(x$longitude) > 180) ||
      any(!is.finite(x$latitude)) || any(abs(x$latitude) > 90)) {
    stop("Community coordinates must be finite WGS84 longitude/latitude.", call. = FALSE)
  }
  if (any(!is.na(x$death_rate_per_100k) &
          (!is.finite(x$death_rate_per_100k) | x$death_rate_per_100k < 0)) ||
      any(!is.na(x$deaths_2020_2024) &
          (!is.finite(x$deaths_2020_2024) | x$deaths_2020_2024 < 0 |
           x$deaths_2020_2024 != floor(x$deaths_2020_2024)))) {
    stop("Health rates must be nonnegative; death counts must be nonnegative integers.",
         call. = FALSE)
  }
  periods <- unique(as.character(x$health_period))
  if (nrow(x) && (anyNA(periods) || any(!nzchar(periods)) || length(periods) != 1L)) {
    stop("Use one nonmissing health_period per query; do not pool different periods.",
         call. = FALSE)
  }
  invisible(x)
}

haversine_km <- function(lon1, lat1, lon2, lat2) {
  rad <- pi / 180
  a <- sin((lat2 - lat1) * rad / 2)^2 +
    cos(lat1 * rad) * cos(lat2 * rad) * sin((lon2 - lon1) * rad / 2)^2
  6371.0088 * 2 * atan2(sqrt(pmin(1, pmax(0, a))), sqrt(pmax(0, 1 - a)))
}

#' Find communities near a query location
#'
#' Selects tracts by great-circle distance to their Census internal points.
#' This is a point-based approximation, not polygon intersection, residents'
#' personal distance, pollution exposure, or a health-effect estimate.
#' The bundled data cover Alachua County only. Supply a compatible data frame
#' to use other locations; no nationwide data are fetched automatically.
#' @param longitude,latitude One WGS84 longitude and latitude in decimal degrees.
#' @param radius_km Nonnegative finite search radius in kilometres.
#' @param communities Compatible tract data; defaults to the bundled snapshot.
#' @return A data frame ordered by distance, with selection and source metadata.
#' @export
#' @examples
#' f <- example_facility()
#' nearby_communities(f$longitude, f$latitude, radius_km = 5)
nearby_communities <- function(longitude, latitude, radius_km = 10,
                               communities = community_data()) {
  check_scalar(longitude, "longitude", -180, 180)
  check_scalar(latitude, "latitude", -90, 90)
  check_scalar(radius_km, "radius_km", 0, .Machine$double.xmax)
  check_communities(communities)
  d <- haversine_km(longitude, latitude, communities$longitude, communities$latitude)
  communities$distance_km <- d
  communities$small_count <- is.na(communities$deaths_2020_2024) |
    communities$deaths_2020_2024 < 5
  communities$query_longitude <- rep(longitude, nrow(communities))
  communities$query_latitude <- rep(latitude, nrow(communities))
  communities$query_radius_km <- rep(radius_km, nrow(communities))
  result <- communities[d <= radius_km, , drop = FALSE]
  result <- result[order(result$distance_km, result$geoid), , drop = FALSE]
  rownames(result) <- NULL
  attr(result, "query") <- list(longitude = longitude, latitude = latitude,
                                 radius_km = radius_km, coverage = "Supplied community data only")
  result
}

#' Summarise tract distributions across distance bands
#'
#' Summaries are unweighted distributions of tract rates. They are not pooled
#' population mortality rates, individual risk estimates or causal comparisons.
#' @param profile Output of [nearby_communities()].
#' @param breaks_km Increasing distance-band edges, starting at zero. The final
#'   edge must cover every selected tract. Distances are not exposure thresholds.
#' @param exclude_small_count Exclude rates with fewer than five deaths or
#'   missing death counts from numeric summaries; retain their count in output.
#' @return A data frame with numbers of selected, excluded and usable tracts,
#'   and median, minimum and maximum crude tract rates in each distance band.
#' @export
#' @examples
#' f <- example_facility()
#' p <- nearby_communities(f$longitude, f$latitude)
#' compare_communities(p)
compare_communities <- function(profile, breaks_km = c(0, 3, 5, 10, Inf),
                                exclude_small_count = TRUE) {
  check_communities(profile)
  if (!is.numeric(profile$distance_km) || any(!is.finite(profile$distance_km)) ||
      any(profile$distance_km < 0)) stop("profile needs valid distance_km values.", call. = FALSE)
  if (!is.numeric(breaks_km) || length(breaks_km) < 2L || anyNA(breaks_km) ||
      breaks_km[1] != 0 || any(diff(breaks_km) <= 0) ||
      any(profile$distance_km > utils::tail(breaks_km, 1L))) {
    stop("breaks_km must increase from zero and cover every selected tract.", call. = FALSE)
  }
  if (!is.logical(exclude_small_count) || length(exclude_small_count) != 1L ||
      is.na(exclude_small_count)) stop("exclude_small_count must be TRUE or FALSE.", call. = FALSE)
  bands <- cut(profile$distance_km, breaks_km, include.lowest = TRUE, right = TRUE)
  usable <- is.finite(profile$death_rate_per_100k)
  if (exclude_small_count) usable <- usable & !is.na(profile$deaths_2020_2024) &
    profile$deaths_2020_2024 >= 5
  out <- lapply(levels(bands), function(b) {
    keep <- bands == b
    rates <- profile$death_rate_per_100k[keep & usable]
    data.frame(distance_band_km = b, n_tracts = sum(keep),
      n_usable = length(rates), n_excluded = sum(keep & !usable),
      median_tract_rate = if (length(rates)) stats::median(rates) else NA_real_,
      min_tract_rate = if (length(rates)) min(rates) else NA_real_,
      max_tract_rate = if (length(rates)) max(rates) else NA_real_)
  })
  do.call(rbind, out)
}
