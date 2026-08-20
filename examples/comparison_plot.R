# =============================================================================
# UTM Zone Visualization - Consolidated Script
# Interactive exploration of transverse Mercator projections
# Using wk/PROJ/geos for coordinate transforms
# =============================================================================

library(wk)
library(PROJ)
library(geos)

# --- Projection definitions ---
lonlat_crs <- "EPSG:4326"

utm_crs <- function(zone, south = TRUE) {
  if (south) {
    sprintf("EPSG:327%02d", zone)
  } else {
    sprintf("EPSG:326%02d", zone)
  }
}

# --- Zone arithmetic ---
zone_central_meridian <- function(zone) -183 + 6 * zone
zone_lon_bounds <- function(zone) {
  cm <- zone_central_meridian(zone)
  c(cm - 3, cm + 3)
}

# --- Grid generation ---
# Returns data frame with xmin, xmax, ymin, ymax, crs
make_utm_grid_100km <- function(zone,
                                easting_range = c(1e5, 9e5),
                                northing_range = c(1e6, 1e7),
                                cell_size = 1e5,
                                south = TRUE) {
  e_breaks <- seq(easting_range[1], easting_range[2], by = cell_size)
  n_breaks <- seq(northing_range[1], northing_range[2], by = cell_size)

  cells <- expand.grid(
    e_idx = seq_along(e_breaks[-length(e_breaks)]),
    n_idx = seq_along(n_breaks[-length(n_breaks)])
  )

  data.frame(
    zone = zone,
    xmin = e_breaks[cells$e_idx],
    xmax = e_breaks[cells$e_idx + 1],
    ymin = n_breaks[cells$n_idx],
    ymax = n_breaks[cells$n_idx + 1],
    crs = utm_crs(zone, south)
  )
}

# --- Transform grid cells to lon/lat ---
# Uses wk/PROJ/geos pipeline: rct -> densify -> transform
transform_grid_to_lonlat <- function(grid, densify_m = 10000) {
  # Create transformation object
  trans <- proj_trans_create(grid$crs[1], lonlat_crs)

  # Build rectangles, densify, transform - all vectorized
  rects <- rct(grid$xmin, grid$ymin, grid$xmax, grid$ymax)
  densified <- geos_densify(as_wkb(rects), densify_m)
  wk_transform(densified, trans)
}

# --- Graticule generation ---
# Returns wk geometry in target CRS
make_graticule <- function(lon_range, lat_range,
                           lon_by = 3, lat_by = 5,
                           to_crs, densify_m = 10000) {

  trans <- proj_trans_create(lonlat_crs, to_crs)

  # Meridians (constant longitude)
  meridian_lons <- seq(lon_range[1], lon_range[2], by = lon_by)
  meridians <- lapply(meridian_lons, function(lon) {
    xy <- cbind(lon, seq(lat_range[1], lat_range[2], length.out = 50))
    wk_linestring(wk::xy(xy[,1], xy[,2]))
  })

  # Parallels (constant latitude)
  parallel_lats <- seq(lat_range[1], lat_range[2], by = lat_by)
  parallels <- lapply(parallel_lats, function(lat) {
    xy <- cbind(seq(lon_range[1], lon_range[2], length.out = 50), lat)
    wk_linestring(wk::xy(xy[,1], xy[,2]))
  })

  # Combine and transform
  all_lines <- c(do.call(c, meridians), do.call(c, parallels))
  wk_transform(geos_densify(as_wkb(all_lines), densify_m), trans)
}

# Simpler version returning lists for more control over styling
make_graticule_separate <- function(lon_range, lat_range,
                                    lon_by = 3, lat_by = 5,
                                    to_crs = NULL, densify_m = 50000) {

  meridian_lons <- seq(lon_range[1], lon_range[2], by = lon_by)
  parallel_lats <- seq(lat_range[1], lat_range[2], by = lat_by)

  meridians <- lapply(meridian_lons, function(lon) {
    xy <- cbind(lon, seq(lat_range[1], lat_range[2], length.out = 80))
    wk_linestring(wk::xy(xy[,1], xy[,2]))
  })
  names(meridians) <- meridian_lons

  parallels <- lapply(parallel_lats, function(lat) {
    xy <- cbind(seq(lon_range[1], lon_range[2], length.out = 80), lat)
    wk_linestring(wk::xy(xy[,1], xy[,2]))
  })
  names(parallels) <- parallel_lats

  if (!is.null(to_crs)) {
    trans <- proj_trans_create(lonlat_crs, to_crs)
    meridians <- lapply(meridians, function(m) {
      wk_transform(geos_densify(as_wkb(m), densify_m), trans)
    })
    parallels <- lapply(parallels, function(p) {
      wk_transform(geos_densify(as_wkb(p), densify_m), trans)
    })
  }

  list(meridians = meridians, parallels = parallels,
       meridian_lons = meridian_lons, parallel_lats = parallel_lats)
}

# --- Coastline ---
get_coastline <- function() {
  if (requireNamespace("maps", quietly = TRUE)) {
    do.call(cbind, maps::map(plot = FALSE)[1:2])
  } else {
    # Tasmania fallback
    cbind(c(144.5, 145.5, 147, 148.3, 148, 146.5, 144.5),
          c(-40.5, -41, -43.5, -43, -41, -39.5, -40.5))
  }
}

get_coastline_wk <- function(xlim, ylim, to_crs = NULL, densify_m = 50000) {
  if (!requireNamespace("maps", quietly = TRUE)) return(NULL)

  coast <- do.call(cbind, maps::map(plot = FALSE)[1:2])

  # Filter to region
  in_region <- coast[,1] >= xlim[1] & coast[,1] <= xlim[2] &
    coast[,2] >= ylim[1] & coast[,2] <= ylim[2]
  in_region[is.na(in_region)] <- FALSE

  # Extract segments between NAs
  coast[!in_region, ] <- NA
  na_idx <- c(0, which(is.na(coast[,1])), nrow(coast) + 1)

  segments <- list()
  for (i in seq_len(length(na_idx) - 1)) {
    start <- na_idx[i] + 1
    end <- na_idx[i + 1] - 1
    if (end > start + 1) {
      chunk <- coast[start:end, , drop = FALSE]
      chunk <- chunk[complete.cases(chunk), , drop = FALSE]
      if (nrow(chunk) > 2) {
        segments[[length(segments) + 1]] <- wk_linestring(wk::xy(chunk[,1], chunk[,2]))
      }
    }
  }

  if (length(segments) == 0) return(NULL)

  coast_wk <- do.call(c, segments)

  if (!is.null(to_crs)) {
    trans <- proj_trans_create(lonlat_crs, to_crs)
    coast_wk <- tryCatch(
      wk_transform(geos_densify(as_wkb(coast_wk), densify_m), trans),
      error = function(e) NULL
    )
  }

  coast_wk
}

# =============================================================================
# PLOT 1: UTM Zone 55 in Lon/Lat View
# =============================================================================
plot_utm_zone55_lonlat <- function() {
  cat("Generating Zone 55 grid...\n")
  grid_55 <- make_utm_grid_100km(55,
                                 easting_range = c(1e5, 9e5),
                                 northing_range = c(1.2e6, 6.7e6))

  cat("Transforming", nrow(grid_55), "cells to lon/lat...\n")
  cells_ll <- transform_grid_to_lonlat(grid_55, densify_m = 8000)

  par(mar = c(4, 4, 3, 1), bg = "white")
  plot(NULL, xlim = c(138, 156), ylim = c(-78, -30),
       xlab = "Longitude (°E)", ylab = "Latitude",
       main = "UTM Zone 55: Lon/Lat View", asp = 1.8)

  plot(cells_ll, border = "steelblue", lwd = 0.4, add = TRUE)
  lines(get_coastline(), col = "grey20", lwd = 1.5)

  abline(v = 147, col = "firebrick", lwd = 2.5, lty = 2)
  text(147.3, -32, "CM 147°E", col = "firebrick", pos = 4, cex = 0.85, font = 2)

  abline(v = c(144, 150), col = "darkorange", lwd = 1.5, lty = 3)

  text(147, -77, "100km cells stretch in longitude toward poles",
       cex = 0.75, col = "grey30")
}

# =============================================================================
# PLOT 2: UTM Zone 55 in Native UTM Coordinates
# =============================================================================
plot_utm_zone55_native <- function() {
  zone <- 55
  zone_crs <- utm_crs(zone, south = TRUE)

  cat("Building graticule in UTM...\n")
  grat <- make_graticule_separate(
    lon_range = c(129, 165), lat_range = c(-78, -30),
    lon_by = 3, lat_by = 5,
    to_crs = zone_crs, densify_m = 20000
  )

  coast_utm <- get_coastline_wk(c(120, 175), c(-80, -25), to_crs = zone_crs)

  e_breaks <- seq(1e5, 9e5, by = 1e5)
  n_breaks <- seq(1.2e6, 6.7e6, by = 1e5)

  par(mar = c(4, 5, 3, 1), bg = "white")

  xlim <- c(-1e5, 1.05e6)
  ylim <- c(1.0e6, 6.9e6)

  plot(NULL, xlim = xlim, ylim = ylim,
       xlab = "Easting (km)", ylab = "Northing (m)",
       main = "UTM Zone 55: Native Coordinates",
       asp = 1, xaxt = "n", yaxt = "n")

  axis(1, at = seq(0, 1e6, by = 2e5), labels = seq(0, 1000, by = 200))
  axis(2, at = seq(1e6, 7e6, by = 1e6), labels = paste0(seq(1, 7), "M"), las = 1)

  # Graticule
  for (p in grat$parallels) plot(p, col = "grey70", lwd = 0.6, add = TRUE)
  for (m in grat$meridians) plot(m, col = "grey70", lwd = 0.6, add = TRUE)

  # Highlight CM and zone boundaries
  if ("147" %in% names(grat$meridians)) {
    plot(grat$meridians[["147"]], col = "firebrick", lwd = 2.5, lty = 2, add = TRUE)
  }
  if ("144" %in% names(grat$meridians)) {
    plot(grat$meridians[["144"]], col = "darkorange", lwd = 1.5, lty = 3, add = TRUE)
  }
  if ("150" %in% names(grat$meridians)) {
    plot(grat$meridians[["150"]], col = "darkorange", lwd = 1.5, lty = 3, add = TRUE)
  }

  # Grid - bounded
  e_min <- min(e_breaks); e_max <- max(e_breaks)
  n_min <- min(n_breaks); n_max <- max(n_breaks)
  segments(x0 = e_breaks, y0 = n_min, x1 = e_breaks, y1 = n_max,
           col = "steelblue", lwd = 0.6)
  segments(x0 = e_min, y0 = n_breaks, x1 = e_max, y1 = n_breaks,
           col = "steelblue", lwd = 0.6)
  rect(e_min, n_min, e_max, n_max, border = "steelblue", lwd = 1.5)

  if (!is.null(coast_utm)) plot(coast_utm, col = "grey25", lwd = 1.2, add = TRUE)

  text(5e5, 1.4e6, "Perfect 100km squares; graticule curves", cex = 0.75, col = "grey30")
}

# =============================================================================
# PLOT 3: Multi-Zone Overlap (Zones 54, 55, 56)
# =============================================================================
plot_utm_multizone <- function() {
  cat("Generating grids for zones 54, 55, 56...\n")

  grid_54 <- make_utm_grid_100km(54, easting_range = c(3e5, 9e5),
                                 northing_range = c(1.2e6, 6.7e6))
  grid_55 <- make_utm_grid_100km(55, easting_range = c(1e5, 9e5),
                                 northing_range = c(1.2e6, 6.7e6))
  grid_56 <- make_utm_grid_100km(56, easting_range = c(1e5, 7e5),
                                 northing_range = c(1.2e6, 6.7e6))

  cat("Transforming zone 54...\n")
  cells_54 <- transform_grid_to_lonlat(grid_54, densify_m = 8000)
  cat("Transforming zone 55...\n")
  cells_55 <- transform_grid_to_lonlat(grid_55, densify_m = 8000)
  cat("Transforming zone 56...\n")
  cells_56 <- transform_grid_to_lonlat(grid_56, densify_m = 8000)

  col_54 <- adjustcolor("seagreen", alpha.f = 0.7)
  col_55 <- adjustcolor("steelblue", alpha.f = 0.7)
  col_56 <- adjustcolor("darkorchid", alpha.f = 0.7)

  par(mar = c(4, 4, 3, 1), bg = "white")

  plot(NULL, xlim = c(132, 162), ylim = c(-78, -30),
       xlab = "Longitude (°E)", ylab = "Latitude",
       main = "UTM Zones 54, 55, 56: Overlap at Polar Latitudes",
       asp = 1.8)

  plot(cells_54, border = col_54, lwd = 0.4, add = TRUE)
  plot(cells_56, border = col_56, lwd = 0.4, add = TRUE)
  plot(cells_55, border = col_55, lwd = 0.5, add = TRUE)

  lines(get_coastline(), col = "grey20", lwd = 1.5)

  abline(v = c(141, 147, 153), col = c("seagreen", "steelblue", "darkorchid"),
         lwd = 2, lty = 2)
  abline(v = c(138, 144, 150, 156), col = "grey50", lwd = 1, lty = 3)

  legend("topright",
         legend = c("Zone 54 (CM 141°E)", "Zone 55 (CM 147°E)", "Zone 56 (CM 153°E)"),
         col = c(col_54, col_55, col_56), lwd = 2, bg = "white", cex = 0.85)

  text(147, -76, "Zones overlap extensively at polar latitudes",
       cex = 0.75, col = "grey30")
}

# =============================================================================
# PLOT 4: UTM Zone 55 Equatorial - Lon/Lat View
# =============================================================================
plot_utm_zone55_equatorial_lonlat <- function() {
  cat("Generating Zone 55 equatorial grid...\n")

  # Southern portion (0 to ~15°S)
  grid_south <- make_utm_grid_100km(55,
                                    easting_range = c(1e5, 9e5),
                                    northing_range = c(8.3e6, 1e7),
                                    south = TRUE)

  # Northern portion (0 to ~15°N)
  grid_north <- make_utm_grid_100km(55,
                                    easting_range = c(1e5, 9e5),
                                    northing_range = c(0, 1.7e6),
                                    south = FALSE)

  cat("Transforming cells...\n")
  cells_south <- transform_grid_to_lonlat(grid_south, densify_m = 10000)
  cells_north <- transform_grid_to_lonlat(grid_north, densify_m = 10000)

  par(mar = c(4, 4, 3, 1), bg = "white")
  plot(NULL, xlim = c(138, 156), ylim = c(-16, 16),
       xlab = "Longitude (°E)", ylab = "Latitude",
       main = "UTM Zone 55 at Equator: Lon/Lat View", asp = 1)

  plot(cells_south, border = "steelblue", lwd = 0.4, add = TRUE)
  plot(cells_north, border = "steelblue", lwd = 0.4, add = TRUE)
  lines(get_coastline(), col = "grey20", lwd = 1.2)

  abline(v = 147, col = "firebrick", lwd = 2.5, lty = 2)
  text(147.3, 14, "CM 147°E", col = "firebrick", pos = 4, cex = 0.85, font = 2)

  abline(v = c(144, 150), col = "darkorange", lwd = 1.5, lty = 3)
  abline(h = 0, col = "grey50", lwd = 1, lty = 2)
  text(155, 0.5, "Equator", col = "grey50", cex = 0.7, pos = 3)

  text(147, -15, "Near-rectangular cells at equator", cex = 0.75, col = "grey30")
}

# =============================================================================
# PLOT 5: UTM Zone 55 Equatorial - Native Coordinates
# =============================================================================
plot_utm_zone55_equatorial_native <- function() {
  zone <- 55
  zone_crs <- utm_crs(zone, south = TRUE)

  cat("Building equatorial graticule in UTM...\n")
  grat <- make_graticule_separate(
    lon_range = c(135, 159), lat_range = c(-15, 0),
    lon_by = 3, lat_by = 5,
    to_crs = zone_crs, densify_m = 20000
  )

  coast_utm <- get_coastline_wk(c(130, 165), c(-20, 5), to_crs = zone_crs)

  e_breaks <- seq(1e5, 9e5, by = 1e5)
  n_breaks <- seq(8.3e6, 1e7, by = 1e5)

  par(mar = c(4, 5, 3, 1), bg = "white")

  xlim <- c(-1e5, 1.05e6)
  ylim <- c(8.2e6, 1.01e7)
  plot(NULL, xlim = xlim, ylim = ylim,
       xlab = "Easting (km)", ylab = "Northing (m)",
       main = "UTM Zone 55 at Equator: Native (S. Hemisphere)",
       asp = 1, xaxt = "n", yaxt = "n", xaxs = "i", yaxs = "i")

  axis(1, at = seq(0, 1e6, by = 2e5), labels = seq(0, 1000, by = 200))
  axis(2, at = seq(8.2e6, 10e6, by = 0.4e6),
       labels = sprintf("%.1fM", seq(8.2, 10, by = 0.4)), las = 1)

  # Graticule
  for (p in grat$parallels) plot(p, col = "grey70", lwd = 0.6, add = TRUE)
  for (m in grat$meridians) plot(m, col = "grey70", lwd = 0.6, add = TRUE)

  # Highlight CM and boundaries
  if ("147" %in% names(grat$meridians)) {
    plot(grat$meridians[["147"]], col = "firebrick", lwd = 2.5, lty = 2, add = TRUE)
  }
  if ("144" %in% names(grat$meridians)) {
    plot(grat$meridians[["144"]], col = "darkorange", lwd = 1.5, lty = 3, add = TRUE)
  }
  if ("150" %in% names(grat$meridians)) {
    plot(grat$meridians[["150"]], col = "darkorange", lwd = 1.5, lty = 3, add = TRUE)
  }

  # Equator line (0° = 10M northing in south hemisphere convention)
  if ("0" %in% names(grat$parallels)) {
    plot(grat$parallels[["0"]], col = "grey40", lwd = 1.5, lty = 2, add = TRUE)
    text(9e5, 1e7, "Equator (10M)", col = "grey40", cex = 0.7, pos = 1)
  }

  # Grid - bounded
  e_min <- min(e_breaks); e_max <- max(e_breaks)
  n_min <- min(n_breaks); n_max <- max(n_breaks)
  segments(x0 = e_breaks, y0 = n_min, x1 = e_breaks, y1 = n_max,
           col = "steelblue", lwd = 0.5)
  segments(x0 = e_min, y0 = n_breaks, x1 = e_max, y1 = n_breaks,
           col = "steelblue", lwd = 0.5)
  rect(e_min, n_min, e_max, n_max, border = "steelblue", lwd = 1.5)

  if (!is.null(coast_utm)) plot(coast_utm, col = "grey25", lwd = 1.2, add = TRUE)

  text(5e5, 8.35e6, "Graticule nearly straight near equator", cex = 0.75, col = "grey30")
}

# =============================================================================
# PLOT 6: UTM Zone 55 Polar Detail - Native Coordinates (60-70°S)
# =============================================================================
plot_utm_zone55_polar_native <- function() {
  zone <- 55
  zone_crs <- utm_crs(zone, south = TRUE)

  cat("Building polar graticule in UTM...\n")
  grat <- make_graticule_separate(
    lon_range = c(135, 159), lat_range = c(-80, -40),
    lon_by = 3, lat_by = 5,
    to_crs = zone_crs, densify_m = 20000
  )

  coast_utm <- get_coastline_wk(c(110, 180), c(-75, -55), to_crs = zone_crs)

  e_breaks <- seq(1e5, 9e5, by = 1e5)
  n_breaks <- seq(2.1e6, 3.4e6, by = 1e5)

  par(mar = c(4, 5, 3, 1), bg = "white")
  xlim <- c(-1e5, 1.05e6)
  ylim <- c(8.2e6, 1.01e7) -6.2e6

  plot(NULL, xlim = xlim, ylim = ylim,
       xlab = "Easting (km)", ylab = "Northing (m)",
       main = "UTM Zone 55 at Equator: Native (S. Hemisphere)",
       asp = 1, xaxt = "n", yaxt = "n", xaxs = "i", yaxs = "i")

  # axis(1, at = seq(-1.5e6, 2.5e6, by = 1e6),
  #      labels = c("-1500", "-500", "500", "1500", "2500"))
  axis(1, at = seq(0, 1e6, by = 2e5), labels = seq(0, 1000, by = 200))
  axis(2, at = seq(2e6, 3.5e6, by = 0.5e6),
       labels = sprintf("%.1fM", seq(2, 3.5, by = 0.5)), las = 1)


  # Graticule
  for (p in grat$parallels) plot(p, col = "grey70", lwd = 0.6, add = TRUE)
  for (m in grat$meridians) plot(m, col = "grey70", lwd = 0.6, add = TRUE)

  # Label parallels
  for (lat in names(grat$parallels)) {
    coords <- wk_coords(grat$parallels[[lat]])
    last_pt <- tail(coords, 1)
    if (!is.na(last_pt$x) && last_pt$x < xlim[2] && last_pt$x > xlim[1]) {
      text(last_pt$x, last_pt$y, paste0(lat, "°"), col = "grey50", cex = 0.6, pos = 4)
    }
  }

  # Highlight CM and zone boundaries
  if ("147" %in% names(grat$meridians)) {
    plot(grat$meridians[["147"]], col = "firebrick", lwd = 2.5, lty = 2, add = TRUE)
    coords <- wk_coords(grat$meridians[["147"]])
    text(coords$x[1], ylim[2] - 0.05e6, "147°E", col = "firebrick", cex = 0.8, font = 2, pos = 1)
  }
  if ("144" %in% names(grat$meridians)) {
    plot(grat$meridians[["144"]], col = "darkorange", lwd = 1.5, lty = 3, add = TRUE)
  }
  if ("150" %in% names(grat$meridians)) {
    plot(grat$meridians[["150"]], col = "darkorange", lwd = 1.5, lty = 3, add = TRUE)
  }

  # Grid - bounded
  e_min <- min(e_breaks); e_max <- max(e_breaks)
  n_min <- min(n_breaks); n_max <- max(n_breaks)
  segments(x0 = e_breaks, y0 = n_min, x1 = e_breaks, y1 = n_max,
           col = "steelblue", lwd = 0.6)
  segments(x0 = e_min, y0 = n_breaks, x1 = e_max, y1 = n_breaks,
           col = "steelblue", lwd = 0.6)
  rect(e_min, n_min, e_max, n_max, border = "steelblue", lwd = 1.5)

  if (!is.null(coast_utm)) plot(coast_utm, col = "grey25", lwd = 1.2, add = TRUE)

  # Scale reference
  arrows(1.5e6, 3.35e6, 1.6e6, 3.35e6, col = "steelblue", lwd = 2, length = 0.1)
  text(1.55e6, 3.38e6, "100 km", col = "steelblue", cex = 0.8)

  text(5e5, 2.15e6,
       "Graticule curves dramatically at polar latitudes\nZone boundaries (orange) diverge widely",
       cex = 0.7, col = "grey30")
}

# =============================================================================
# PLOT 7: Global Mercator at Equator - Lon/Lat View
# 100km grid in Web Mercator, same lon range as plot 4
# =============================================================================
plot_mercator_equatorial_lonlat <- function() {
  cat("Generating Mercator equatorial grid...\n")

  merc_crs <- "EPSG:3857"  # Web Mercator
  trans_to_merc <- proj_trans_create(lonlat_crs, merc_crs)
  trans_to_ll <- proj_trans_create(merc_crs, lonlat_crs)

  # Get Mercator bounds for equatorial region (~138-156°E, -16 to 16°)
  corners_ll <- wk::xy(c(138, 156, 138, 156), c(-16, -16, 16, 16))
  corners_merc <- wk_transform(corners_ll, trans_to_merc)
  merc_coords <- wk_coords(corners_merc)

  x_range <- c(floor(min(merc_coords$x) / 1e5) * 1e5,
               ceiling(max(merc_coords$x) / 1e5) * 1e5)
  y_range <- c(floor(min(merc_coords$y) / 1e5) * 1e5,
               ceiling(max(merc_coords$y) / 1e5) * 1e5)

  # Build 100km grid in Mercator
  x_breaks <- seq(x_range[1], x_range[2], by = 1e5)
  y_breaks <- seq(y_range[1], y_range[2], by = 1e5)

  cells <- expand.grid(
    x_idx = seq_along(x_breaks[-length(x_breaks)]),
    y_idx = seq_along(y_breaks[-length(y_breaks)])
  )

  grid <- data.frame(
    xmin = x_breaks[cells$x_idx],
    xmax = x_breaks[cells$x_idx + 1],
    ymin = y_breaks[cells$y_idx],
    ymax = y_breaks[cells$y_idx + 1]
  )

  cat("Grid has", nrow(grid), "cells, Mercator y-range:", y_range, "\n")

  # Transform to lon/lat
  rects <- rct(grid$xmin, grid$ymin, grid$xmax, grid$ymax)
  cells_ll <- wk_transform(geos_densify(as_wkb(rects), 10000), trans_to_ll)

  par(mar = c(4, 4, 3, 1), bg = "white")
  plot(NULL, xlim = c(136, 158), ylim = c(-18, 18),
       xlab = "Longitude (°E)", ylab = "Latitude",
       main = "Global Mercator at Equator: Lon/Lat View", asp = 1)

  plot(cells_ll, border = "steelblue", lwd = 0.4, add = TRUE)
  lines(get_coastline(), col = "grey20", lwd = 1.2)

  abline(h = 0, col = "firebrick", lwd = 2.5, lty = 2)
  text(157, 1, "Equator", col = "firebrick", cex = 0.8, font = 2, pos = 3)

  text(147, -17, "100km Mercator cells - nearly square at equator",
       cex = 0.75, col = "grey30")

  # Return extent for reuse in polar plots
  invisible(list(x_range = x_range, y_range = y_range,
                 y_size = diff(y_range)))
}

# =============================================================================
# PLOT 8: Global Mercator at Equator - Native Coordinates
# =============================================================================
plot_mercator_equatorial_native <- function() {
  cat("Building Mercator equatorial view...\n")

  merc_crs <- "EPSG:3857"
  trans_to_merc <- proj_trans_create(lonlat_crs, merc_crs)

  # Same extent as plot 7
  corners_ll <- wk::xy(c(138, 156, 138, 156), c(-16, -16, 16, 16))
  corners_merc <- wk_transform(corners_ll, trans_to_merc)
  merc_coords <- wk_coords(corners_merc)

  x_range <- c(floor(min(merc_coords$x) / 1e5) * 1e5,
               ceiling(max(merc_coords$x) / 1e5) * 1e5)
  y_range <- c(floor(min(merc_coords$y) / 1e5) * 1e5,
               ceiling(max(merc_coords$y) / 1e5) * 1e5)

  x_breaks <- seq(x_range[1], x_range[2], by = 1e5)
  y_breaks <- seq(y_range[1], y_range[2], by = 1e5)

  # Graticule
  grat <- make_graticule_separate(
    lon_range = c(136, 158), lat_range = c(-18, 18),
    lon_by = 3, lat_by = 5,
    to_crs = merc_crs, densify_m = 20000
  )

  coast_merc <- get_coastline_wk(c(134, 160), c(-20, 20), to_crs = merc_crs)

  par(mar = c(4, 5, 3, 1), bg = "white")

  xlim <- c(x_range[1] - 1e5, x_range[2] + 1e5)
  ylim <- c(y_range[1] - 1e5, y_range[2] + 1e5)

  plot(NULL, xlim = xlim, ylim = ylim,
       xlab = "Mercator X (m)", ylab = "Mercator Y (m)",
       main = "Global Mercator at Equator: Native Coordinates",
       asp = 1, xaxt = "n", yaxt = "n")

  # Axes
  axis(1, at = pretty(xlim, 4), labels = sprintf("%.1fM", pretty(xlim, 4) / 1e6))
  axis(2, at = pretty(ylim, 4), labels = sprintf("%.1fM", pretty(ylim, 4) / 1e6), las = 1)

  # Graticule
  for (p in grat$parallels) plot(p, col = "grey70", lwd = 0.6, add = TRUE)
  for (m in grat$meridians) plot(m, col = "grey70", lwd = 0.6, add = TRUE)

  # Equator
  if ("0" %in% names(grat$parallels)) {
    plot(grat$parallels[["0"]], col = "firebrick", lwd = 2.5, lty = 2, add = TRUE)
  }

  # Grid - bounded
  x_min <- min(x_breaks); x_max <- max(x_breaks)
  y_min <- min(y_breaks); y_max <- max(y_breaks)
  segments(x0 = x_breaks, y0 = y_min, x1 = x_breaks, y1 = y_max,
           col = "steelblue", lwd = 0.5)
  segments(x0 = x_min, y0 = y_breaks, x1 = x_max, y1 = y_breaks,
           col = "steelblue", lwd = 0.5)
  rect(x_min, y_min, x_max, y_max, border = "steelblue", lwd = 1.5)

  if (!is.null(coast_merc)) plot(coast_merc, col = "grey25", lwd = 1.2, add = TRUE)

  text(mean(xlim), ylim[1] + 0.5e5,
       "Graticule is straight (standard cylindrical)", cex = 0.75, col = "grey30")

  invisible(list(x_range = x_range, y_range = y_range))
}

# =============================================================================
# PLOT 9: Global Mercator at Antarctica - Lon/Lat View
# Same Mercator extent (in meters) shifted to polar latitudes
# =============================================================================
plot_mercator_polar_lonlat <- function() {
  cat("Generating Mercator polar grid...\n")

  merc_crs <- "EPSG:3857"
  trans_to_merc <- proj_trans_create(lonlat_crs, merc_crs)
  trans_to_ll <- proj_trans_create(merc_crs, lonlat_crs)

  # Get the equatorial extent size first
  corners_ll_eq <- wk::xy(c(138, 156, 138, 156), c(-16, -16, 16, 16))
  corners_merc_eq <- wk_transform(corners_ll_eq, trans_to_merc)
  merc_coords_eq <- wk_coords(corners_merc_eq)

  x_range <- c(floor(min(merc_coords_eq$x) / 1e5) * 1e5,
               ceiling(max(merc_coords_eq$x) / 1e5) * 1e5)
  y_size <- ceiling(max(merc_coords_eq$y) / 1e5) * 1e5 -
    floor(min(merc_coords_eq$y) / 1e5) * 1e5

  # Shift to Antarctica - center around ~65°S
  # 65°S in Web Mercator is approximately -9.7e6
  polar_center_ll <- wk::xy(147, -65)
  polar_center_merc <- wk_transform(polar_center_ll, trans_to_merc)
  polar_y <- wk_coords(polar_center_merc)$y

  y_range_polar <- c(polar_y - y_size/2, polar_y + y_size/2)
  y_range_polar <- c(floor(y_range_polar[1] / 1e5) * 1e5,
                     ceiling(y_range_polar[2] / 1e5) * 1e5)

  cat("Polar Mercator y-range:", y_range_polar, "\n")

  # Build 100km grid
  x_breaks <- seq(x_range[1], x_range[2], by = 1e5)
  y_breaks <- seq(y_range_polar[1], y_range_polar[2], by = 1e5)

  cells <- expand.grid(
    x_idx = seq_along(x_breaks[-length(x_breaks)]),
    y_idx = seq_along(y_breaks[-length(y_breaks)])
  )

  grid <- data.frame(
    xmin = x_breaks[cells$x_idx],
    xmax = x_breaks[cells$x_idx + 1],
    ymin = y_breaks[cells$y_idx],
    ymax = y_breaks[cells$y_idx + 1]
  )

  cat("Grid has", nrow(grid), "cells\n")

  # Transform to lon/lat
  rects <- rct(grid$xmin, grid$ymin, grid$xmax, grid$ymax)
  cells_ll <- wk_transform(geos_densify(as_wkb(rects), 10000), trans_to_ll)

  # Get actual lat range for plotting
  all_coords <- wk_coords(cells_ll)
  lat_range <- range(all_coords$y, na.rm = TRUE)

  par(mar = c(4, 4, 3, 1), bg = "white")
  plot(NULL, xlim = c(136, 158), ylim = lat_range + c(-1, 1),
       xlab = "Longitude (°E)", ylab = "Latitude",
       main = "Global Mercator at Antarctica: Lon/Lat View", asp = 1.8)

  plot(cells_ll, border = "steelblue", lwd = 0.4, add = TRUE)
  lines(get_coastline(), col = "grey20", lwd = 1.2)

  text(147, min(lat_range) + 1,
       "Same Mercator extent as equator\nCovers less ground distance, spans similar longitude",
       cex = 0.7, col = "grey30")
}

# =============================================================================
# PLOT 10: Global Mercator at Antarctica - Native Coordinates
# =============================================================================
plot_mercator_polar_native <- function() {
  cat("Building Mercator polar view...\n")

  merc_crs <- "EPSG:3857"
  trans_to_merc <- proj_trans_create(lonlat_crs, merc_crs)

  # Same extent calculation as plot 9
  corners_ll_eq <- wk::xy(c(138, 156, 138, 156), c(-16, -16, 16, 16))
  corners_merc_eq <- wk_transform(corners_ll_eq, trans_to_merc)
  merc_coords_eq <- wk_coords(corners_merc_eq)

  x_range <- c(floor(min(merc_coords_eq$x) / 1e5) * 1e5,
               ceiling(max(merc_coords_eq$x) / 1e5) * 1e5)
  y_size <- ceiling(max(merc_coords_eq$y) / 1e5) * 1e5 -
    floor(min(merc_coords_eq$y) / 1e5) * 1e5

  polar_center_ll <- wk::xy(147, -65)
  polar_center_merc <- wk_transform(polar_center_ll, trans_to_merc)
  polar_y <- wk_coords(polar_center_merc)$y

  y_range_polar <- c(polar_y - y_size/2, polar_y + y_size/2)
  y_range_polar <- c(floor(y_range_polar[1] / 1e5) * 1e5,
                     ceiling(y_range_polar[2] / 1e5) * 1e5)

  x_breaks <- seq(x_range[1], x_range[2], by = 1e5)
  y_breaks <- seq(y_range_polar[1], y_range_polar[2], by = 1e5)

  # Graticule - need wider lat range
  grat <- make_graticule_separate(
    lon_range = c(134, 160), lat_range = c(-72, -58),
    lon_by = 3, lat_by = 2,
    to_crs = merc_crs, densify_m = 20000
  )

  coast_merc <- get_coastline_wk(c(130, 165), c(-75, -55), to_crs = merc_crs)

  par(mar = c(4, 5, 3, 1), bg = "white")

  xlim <- c(x_range[1] - 1e5, x_range[2] + 1e5)
  ylim <- c(y_range_polar[1] - 1e5, y_range_polar[2] + 1e5)

  plot(NULL, xlim = xlim, ylim = ylim,
       xlab = "Mercator X (m)", ylab = "Mercator Y (m)",
       main = "Global Mercator at Antarctica: Native Coordinates",
       asp = 1, xaxt = "n", yaxt = "n")

  # Axes
  axis(1, at = pretty(xlim, 4), labels = sprintf("%.1fM", pretty(xlim, 4) / 1e6))
  axis(2, at = pretty(ylim, 4), labels = sprintf("%.1fM", pretty(ylim, 4) / 1e6), las = 1)

  # Graticule
  for (p in grat$parallels) plot(p, col = "grey70", lwd = 0.6, add = TRUE)
  for (m in grat$meridians) plot(m, col = "grey70", lwd = 0.6, add = TRUE)

  # Label some parallels
  for (lat in names(grat$parallels)) {
    coords <- wk_coords(grat$parallels[[lat]])
    last_pt <- tail(coords, 1)
    if (!is.na(last_pt$x) && last_pt$x < xlim[2] && last_pt$x > xlim[1]) {
      text(last_pt$x, last_pt$y, paste0(lat, "°"), col = "grey50", cex = 0.6, pos = 4)
    }
  }

  # Grid - bounded
  x_min <- min(x_breaks); x_max <- max(x_breaks)
  y_min <- min(y_breaks); y_max <- max(y_breaks)
  segments(x0 = x_breaks, y0 = y_min, x1 = x_breaks, y1 = y_max,
           col = "steelblue", lwd = 0.5)
  segments(x0 = x_min, y0 = y_breaks, x1 = x_max, y1 = y_breaks,
           col = "steelblue", lwd = 0.5)
  rect(x_min, y_min, x_max, y_max, border = "steelblue", lwd = 1.5)

  if (!is.null(coast_merc)) plot(coast_merc, col = "grey25", lwd = 1.2, add = TRUE)

  # Scale reference
  arrows(x_max + 0.3e5, y_max - 0.2e6, x_max + 0.3e5 + 1e5, y_max - 0.2e6,
         col = "steelblue", lwd = 2, length = 0.1)
  text(x_max + 0.3e5 + 0.5e5, y_max - 0.1e6, "100 km\n(Mercator)", col = "steelblue", cex = 0.7)

  text(mean(xlim), ylim[1] + 0.3e6,
       "Graticule still straight, but parallels compressed\n100km Mercator ≠ 100km ground distance here",
       cex = 0.7, col = "grey30")
}

# =============================================================================
# RUN ALL PLOTS
# =============================================================================

cat("
=== UTM Zone Visualization ===
Uses: wk, PROJ, geos

UTM Zone 55 plots:
 plot_utm_zone55_lonlat()            - Zone 55 lon/lat (Tasmania to Antarctica)
 plot_utm_zone55_native()            - Zone 55 native UTM (full range)
 plot_utm_multizone()                - Zones 54-56 overlap
 plot_utm_zone55_equatorial_lonlat() - Zone 55 at equator, lon/lat
 plot_utm_zone55_equatorial_native() - Zone 55 at equator, native UTM
 plot_utm_zone55_polar_native()      - Zone 55 at 60-70°S, native UTM

Global Mercator comparison:
 plot_mercator_equatorial_lonlat()   - Mercator at equator, lon/lat
 plot_mercator_equatorial_native()   - Mercator at equator, native
 plot_mercator_polar_lonlat()        - Same extent at Antarctica, lon/lat
 plot_mercator_polar_native()        - Same extent at Antarctica, native

Composite: plot_all(), plot_mercator_comparison()
")

plot_all <- function() {
  op <- par(no.readonly = TRUE)
  on.exit(par(op))

  par(mfrow = c(2, 3))

  plot_utm_zone55_lonlat()
  plot_utm_zone55_native()
  plot_utm_multizone()
  plot_utm_zone55_equatorial_lonlat()
  plot_utm_zone55_equatorial_native()
  plot_utm_zone55_polar_native()

  par(mfrow = c(1, 1))
}

plot_mercator_comparison <- function() {
  op <- par(no.readonly = TRUE)
  on.exit(par(op))

  par(mfrow = c(2, 2))

  plot_mercator_equatorial_lonlat()
  plot_mercator_equatorial_native()
  plot_mercator_polar_lonlat()
  plot_mercator_polar_native()

  par(mfrow = c(1, 1))
}
