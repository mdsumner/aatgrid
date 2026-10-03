#' Generate UTM zone boundary lines
#'
#' One meridian line per zone, at that zone's western edge
#' (`-180 + (zone_number - 1) * 6`), as a SpatVector in `EPSG:4326`.
#' Useful as map context when showing which zone a region falls in.
#'
#' @param zone_numbers Vector of UTM zone numbers (default: every zone
#'   in [define_utm_zones()])
#' @param lat_range Vector c(min_lat, max_lat) in degrees (default: c(-85, -40))
#' @param n_points Number of vertices along each line (default: 100)
#' @return SpatVector of lines in EPSG:4326 with attributes zone_west,
#'   zone_east, longitude, label
#' @export
#' @examples
#' b <- generate_utm_zone_boundaries(42:58, lat_range = c(-70, -50))
#' terra::values(b)
generate_utm_zone_boundaries <- function(zone_numbers,
                                         lat_range = c(-85, -40),
                                         n_points = 100) {

  if (missing(zone_numbers)) {
    zone_numbers <- define_utm_zones()$zone_number
  }
  if (any(zone_numbers < 1 | zone_numbers > 60)) {
    stop("zone_numbers must lie in 1:60")
  }
  if (n_points < 2) stop("n_points must be at least 2")

  # UTM zone boundaries are at -180 + (zone_number - 1) * 6
  longitudes <- -180 + (zone_numbers - 1) * 6

  lats <- seq(lat_range[1], lat_range[2], length.out = n_points)

  lines_list <- lapply(longitudes, function(lon) {
    coords <- cbind(rep(lon, n_points), lats)
    terra::vect(coords, type = "lines", crs = "EPSG:4326")
  })

  boundaries <- do.call(rbind, lines_list)

  terra::values(boundaries) <- data.frame(
    zone_west = zone_numbers,
    zone_east = ifelse(zone_numbers == 60, 1, zone_numbers + 1),
    longitude = longitudes,
    label = paste0(zone_numbers, "/", ifelse(zone_numbers == 60, 1, zone_numbers + 1))
  )

  boundaries
}
