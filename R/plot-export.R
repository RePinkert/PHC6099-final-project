#' Plot selected communities
#'
#' Bundled tract boundaries are drawn only for the bundled Alachua snapshot.
#' Unknown GEOIDs are shown as points. Grey regions are context or small-count
#' tracts, not low-risk areas. Colour represents crude death rates.
#' @param profile Output from [nearby_communities()].
#' @param view Either a geographic map or a distance-versus-rate plot.
#' @return The profile, invisibly; called for its plotting side effect.
#' @export
#' @examples
#' f <- example_facility()
#' p <- nearby_communities(f$longitude, f$latitude)
#' plot_communities(p)
#' plot_communities(p, "distance")
plot_communities <- function(profile, view = c("map", "distance")) {
  view <- match.arg(view)
  check_communities(profile)
  query <- attr(profile, "query")
  if (is.null(query)) stop("Use a profile returned by nearby_communities().", call. = FALSE)
  old <- graphics::par(no.readonly = TRUE)
  on.exit(graphics::par(old))
  graphics::par(mar = c(5, 4.6, 3.5, 1.2), mgp = c(2.7, 0.8, 0))
  ok <- is.finite(profile$death_rate_per_100k) & !is.na(profile$deaths_2020_2024) &
    profile$deaths_2020_2024 >= 5
  if (view == "distance") {
    xmax <- max(c(profile$distance_km, 1))
    ymax <- max(c(profile$death_rate_per_100k[ok], 1)) * 1.1
    graphics::plot(NA, xlim = c(0, xmax * 1.05), ylim = c(0, ymax),
      xlab = "Distance to tract internal point (km)",
      ylab = "Crude death rate per 100,000", main = "Community context by distance")
    graphics::grid(col = "#e8edf2")
    graphics::points(profile$distance_km[ok], profile$death_rate_per_100k[ok],
                     pch = 21, bg = "#167d8d", col = "white", cex = 1.4)
    graphics::mtext("2020-2024 | small-count tracts omitted | descriptive only", side = 1,
                    line = 4, cex = 0.7, col = "#526473")
    return(invisible(profile))
  }
  radius <- max(1, query$radius_km)
  if (abs(query$latitude) >= 85 || radius > 500) {
    stop("The local map supports latitudes below 85 degrees and radii up to 500 km.",
         call. = FALSE)
  }
  dx <- radius * 1.12 / (111.195 * cos(query$latitude * pi / 180))
  dy <- radius * 1.12 / 111.195
  graphics::plot(NA, xlim = query$longitude + c(-dx, dx),
    ylim = query$latitude + c(-dy, dy), asp = 1 / cos(query$latitude * pi / 180),
    xlab = "Longitude", ylab = "Latitude", main = "Communities near the query location")
  graphics::grid(col = "#eef1f4")
  bounds <- read_snapshot()$boundaries
  draw_shape <- function(shape, fill, border) {
    xx <- unlist(lapply(shape$rings, function(r) c(r[, 1], NA_real_)))
    yy <- unlist(lapply(shape$rings, function(r) c(r[, 2], NA_real_)))
    # polypath accepts internal ring separators but rejects a trailing separator.
    xx <- xx[-length(xx)]
    yy <- yy[-length(yy)]
    graphics::polypath(xx, yy, col = fill, border = border, rule = "evenodd", lwd = 0.5)
  }
  for (b in bounds) draw_shape(b, "#f0f3f5", "#cbd5dc")
  palette <- grDevices::hcl.colors(5, "Blues 3", rev = TRUE)
  value_breaks <- c(0, 500, 1000, 1500, 2000, Inf)
  bins <- cut(profile$death_rate_per_100k, value_breaks, include.lowest = TRUE)
  colours <- rep("#c5cbd0", nrow(profile))
  colours[ok] <- palette[as.integer(bins[ok])]
  for (i in seq_len(nrow(profile))) {
    found <- which(vapply(bounds, function(b) identical(b$geoid, profile$geoid[i]), logical(1)))
    if (length(found)) draw_shape(bounds[[found[1L]]], colours[i], "white")
    else graphics::points(profile$longitude[i], profile$latitude[i],
                           pch = 21, bg = colours[i], cex = 1.2)
  }
  bearings <- seq(0, 2 * pi, length.out = 241)
  phi <- query$latitude * pi / 180
  delta <- query$radius_km / 6371.0088
  lat2 <- asin(sin(phi) * cos(delta) + cos(phi) * sin(delta) * cos(bearings))
  lon2 <- query$longitude * pi / 180 + atan2(sin(bearings) * sin(delta) * cos(phi),
                                          cos(delta) - sin(phi) * sin(lat2))
  graphics::lines(lon2 * 180 / pi, lat2 * 180 / pi, lty = 2, col = "#263747", lwd = 1.4)
  graphics::points(query$longitude, query$latitude, pch = 8, cex = 1.6,
                   col = "#a14d19", lwd = 2)
  graphics::legend("bottomleft", title = "Crude rate / 100,000", cex = 0.6,
    legend = c("0-500", "500-1,000", "1,000-1,500", "1,500-2,000", ">2,000", "Small count / unavailable"),
    fill = c(palette, "#c5cbd0"), border = NA, bg = "white", box.col = "#d6dfe4")
  graphics::mtext("Dashed circle: search radius | star: approximate query location | descriptive only",
                  side = 1, line = 4, cex = 0.64, col = "#526473")
  invisible(profile)
}

#' Export selected communities to CSV
#'
#' Source, period and query metadata remain in columns. No row names are written.
#' @param profile Output from [nearby_communities()].
#' @param path Destination CSV path.
#' @param overwrite Allow replacement of an existing file; defaults to FALSE.
#' @return The destination path invisibly.
#' @export
#' @examples
#' f <- example_facility()
#' p <- nearby_communities(f$longitude, f$latitude, radius_km = 5)
#' export_communities(p, tempfile(fileext = ".csv"))
export_communities <- function(profile, path, overwrite = FALSE) {
  check_communities(profile)
  if (is.null(attr(profile, "query"))) stop("Use a nearby_communities() profile.", call. = FALSE)
  if (!is.character(path) || length(path) != 1L || is.na(path) || !nzchar(path)) {
    stop("path must be a nonempty file path.", call. = FALSE)
  }
  if (!is.logical(overwrite) || length(overwrite) != 1L || is.na(overwrite)) {
    stop("overwrite must be TRUE or FALSE.", call. = FALSE)
  }
  if (file.exists(path) && !overwrite) stop("File exists; set overwrite = TRUE to replace it.", call. = FALSE)
  utils::write.csv(profile, path, row.names = FALSE, na = "")
  invisible(path)
}
