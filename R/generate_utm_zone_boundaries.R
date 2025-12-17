library(terra)

#' Generate UTM zone boundary lines
#'
#' @param zone_numbers Vector of UTM zone numbers (default: 42:58 for AAT)
#' @param lat_range Vector c(min_lat, max_lat) in degrees (default: c(-85, -40))
#' @param n_points Number of points along each line (default: 100)
#' @return SpatVector of lines in EPSG:4326
generate_utm_zone_boundaries <- function(zone_numbers,
                                         lat_range = c(-85, -40),
                                         n_points = 100) {

  if (missing(zone_numbers)) {
    zone_numbers <- define_utm_zones()$zone_number

  }
  # Calculate longitude boundaries for each zone
  # UTM zone boundaries are at -180 + (zone_number - 1) * 6
  longitudes <- -180 + (zone_numbers - 1) * 6

  # Create latitude sequence
  lats <- seq(lat_range[1], lat_range[2], length.out = n_points)

  # Create lines for each boundary
  lines_list <- lapply(longitudes, function(lon) {
    # Create matrix of coordinates (lon, lat pairs)
    coords <- cbind(rep(lon, n_points), lats)

    # Create line geometry
    vect(coords, type = "lines", crs = "EPSG:4326")
  })

  # Combine all lines into single SpatVector
  boundaries <- do.call(rbind, lines_list)

  # Add attributes
  values(boundaries) <- data.frame(
    zone_west = zone_numbers,
    zone_east = zone_numbers + 1,
    longitude = longitudes,
    label = paste0(zone_numbers, "/", zone_numbers + 1)
  )

  return(boundaries)
}

# Example usage:
if (FALSE) {
  # Generate boundaries for AAT zones
  zone_lines <- generate_utm_zone_boundaries()

  # View the result
  print(zone_lines)
  print(values(zone_lines))

  # Save to file
  writeVector(zone_lines, "utm_zone_boundaries.gpkg", overwrite = TRUE)

  # Plot (simple)
  plot(zone_lines)

  # Generate for specific zones with custom lat range
  antarctic_lines <- generate_utm_zone_boundaries(
    zone_numbers = 42:58,
    lat_range = c(-70, -50),
    n_points = 200
  )
}
