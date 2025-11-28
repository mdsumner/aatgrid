# Antarctic Grid System - Standalone Demonstration
# This version demonstrates core concepts without requiring sf package

# ==============================================================================
# GRID SPECIFICATION
# ==============================================================================

GRID_SPEC <- list(
  L1 = list(tile_size = 36000, resolution = 60, pixels = 600),
  L2 = list(tile_size = 6000, resolution = 10, pixels = 600),
  nesting_factor = 6
)

# ==============================================================================
# UTM ZONE DEFINITIONS
# ==============================================================================

define_utm_zones <- function() {
  zone_numbers <- 42:58
  data.frame(
    zone_number = zone_numbers,
    hemisphere = "S",
    epsg = paste0("EPSG:327", zone_numbers),
    origin_x = 166021,
    origin_y = 0,
    central_meridian = -183 + (zone_numbers * 6),
    zone_id = paste0(zone_numbers, "S"),
    stringsAsFactors = FALSE
  )
}

# ==============================================================================
# TILE INDEXING FUNCTIONS
# ==============================================================================

utm_to_tile_index <- function(x, y, level, origin_x = 166021, origin_y = 0) {
  tile_size <- GRID_SPEC[[level]]$tile_size
  col <- floor((x - origin_x) / tile_size)
  row <- floor((y - origin_y) / tile_size)
  data.frame(col = col, row = row)
}

tile_index_to_bbox <- function(col, row, level, origin_x = 166021, origin_y = 0) {
  tile_size <- GRID_SPEC[[level]]$tile_size
  xmin <- origin_x + (col * tile_size)
  ymin <- origin_y + (row * tile_size)
  xmax <- xmin + tile_size
  ymax <- ymin + tile_size
  data.frame(xmin = xmin, ymin = ymin, xmax = xmax, ymax = ymax)
}

make_tile_id <- function(zone_id, level, col, row) {
  paste0(zone_id, "_", level, "_", sprintf("%04d", col), "_", sprintf("%04d", row))
}

get_parent_tile <- function(l2_col, l2_row) {
  nf <- GRID_SPEC$nesting_factor
  data.frame(col = floor(l2_col / nf), row = floor(l2_row / nf))
}

get_child_tiles <- function(l1_col, l1_row) {
  nf <- GRID_SPEC$nesting_factor
  child_cols <- rep(l1_col * nf + 0:(nf-1), each = nf)
  child_rows <- rep(l1_row * nf + 0:(nf-1), times = nf)
  data.frame(col = child_cols, row = child_rows)
}

# Simple lon/lat to UTM conversion (approximate, for demonstration)
lonlat_to_utm <- function(lon, lat, zone_number) {
  lon0 <- -183 + (zone_number * 6)
  k0 <- 0.9996
  a <- 6378137  # WGS84 equatorial radius
  e <- 0.0818191908426  # WGS84 eccentricity
  
  lat_rad <- lat * pi / 180
  lon_rad <- (lon - lon0) * pi / 180
  
  N <- a / sqrt(1 - e^2 * sin(lat_rad)^2)
  T <- tan(lat_rad)^2
  C <- e^2 * cos(lat_rad)^2 / (1 - e^2)
  A <- lon_rad * cos(lat_rad)
  
  M <- a * ((1 - e^2/4 - 3*e^4/64 - 5*e^6/256) * lat_rad -
            (3*e^2/8 + 3*e^4/32 + 45*e^6/1024) * sin(2*lat_rad) +
            (15*e^4/256 + 45*e^6/1024) * sin(4*lat_rad) -
            (35*e^6/3072) * sin(6*lat_rad))
  
  x <- k0 * N * (A + (1 - T + C) * A^3/6 + 
                  (5 - 18*T + T^2 + 72*C - 58*e^2/(1-e^2)) * A^5/120) + 500000
  y <- k0 * (M + N * tan(lat_rad) * (A^2/2 + (5 - T + 9*C + 4*C^2) * A^4/24 +
              (61 - 58*T + T^2 + 600*C - 330*e^2/(1-e^2)) * A^6/720))
  
  # Southern hemisphere adjustment
  y <- y + 10000000
  
  c(x = x, y = y)
}

# ==============================================================================
# DEMONSTRATION
# ==============================================================================

cat("\n")
cat("=================================================\n")
cat("Antarctic Territory Grid System - Demonstration\n")
cat("=================================================\n\n")

# Initialize
zones <- define_utm_zones()

cat("Grid System Overview\n")
cat("--------------------\n")
cat(sprintf("UTM Zones: %d-%d (Southern Hemisphere)\n", 
            min(zones$zone_number), max(zones$zone_number)))
cat(sprintf("Coverage: ~44°E to ~160°E longitude\n\n"))

cat("Grid Parameters:\n")
cat(sprintf("  Level 1 (L1): %d × %d m tiles at %d m/px (%d × %d pixels)\n",
            GRID_SPEC$L1$tile_size, GRID_SPEC$L1$tile_size,
            GRID_SPEC$L1$resolution, GRID_SPEC$L1$pixels, GRID_SPEC$L1$pixels))
cat(sprintf("  Level 2 (L2): %d × %d m tiles at %d m/px (%d × %d pixels)\n",
            GRID_SPEC$L2$tile_size, GRID_SPEC$L2$tile_size,
            GRID_SPEC$L2$resolution, GRID_SPEC$L2$pixels, GRID_SPEC$L2$pixels))
cat(sprintf("  Nesting: %d × %d = %d L2 tiles per L1 tile\n\n",
            GRID_SPEC$nesting_factor, GRID_SPEC$nesting_factor,
            GRID_SPEC$nesting_factor^2))

# Example 1: Heard Island
cat("Example 1: Heard Island Region\n")
cat("-------------------------------\n")
heard_lon <- 73.5
heard_lat <- -53.0
heard_zone <- 43

cat(sprintf("Location: %.2f°E, %.2f°S\n", heard_lon, heard_lat))
cat(sprintf("UTM Zone: %dS (EPSG:327%d)\n\n", heard_zone, heard_zone))

# Convert to UTM
utm_coords <- lonlat_to_utm(heard_lon, heard_lat, heard_zone)
cat(sprintf("UTM Coordinates: %.0f E, %.0f N\n", utm_coords["x"], utm_coords["y"]))

# Get tile indices
zone_info <- zones[zones$zone_number == heard_zone, ]
l1_idx <- utm_to_tile_index(utm_coords["x"], utm_coords["y"], "L1",
                             zone_info$origin_x, zone_info$origin_y)
l2_idx <- utm_to_tile_index(utm_coords["x"], utm_coords["y"], "L2",
                             zone_info$origin_x, zone_info$origin_y)

cat(sprintf("\nTile Indices:\n"))
cat(sprintf("  L1: col=%d, row=%d\n", l1_idx$col, l1_idx$row))
cat(sprintf("  L2: col=%d, row=%d\n", l2_idx$col, l2_idx$row))

# Create tile IDs
l1_id <- make_tile_id(zone_info$zone_id, "L1", l1_idx$col, l1_idx$row)
l2_id <- make_tile_id(zone_info$zone_id, "L2", l2_idx$col, l2_idx$row)

cat(sprintf("\nTile IDs:\n"))
cat(sprintf("  L1: %s\n", l1_id))
cat(sprintf("  L2: %s\n", l2_id))

# Get bounding boxes
l1_bbox <- tile_index_to_bbox(l1_idx$col, l1_idx$row, "L1",
                               zone_info$origin_x, zone_info$origin_y)
l2_bbox <- tile_index_to_bbox(l2_idx$col, l2_idx$row, "L2",
                               zone_info$origin_x, zone_info$origin_y)

cat(sprintf("\nL1 Tile Bounds (UTM):\n"))
cat(sprintf("  X: %.0f to %.0f (%.0f km width)\n", 
            l1_bbox$xmin, l1_bbox$xmax, (l1_bbox$xmax - l1_bbox$xmin)/1000))
cat(sprintf("  Y: %.0f to %.0f (%.0f km height)\n",
            l1_bbox$ymin, l1_bbox$ymax, (l1_bbox$ymax - l1_bbox$ymin)/1000))

cat(sprintf("\nL2 Tile Bounds (UTM):\n"))
cat(sprintf("  X: %.0f to %.0f (%.0f km width)\n",
            l2_bbox$xmin, l2_bbox$xmax, (l2_bbox$xmax - l2_bbox$xmin)/1000))
cat(sprintf("  Y: %.0f to %.0f (%.0f km height)\n",
            l2_bbox$ymin, l2_bbox$ymax, (l2_bbox$ymax - l2_bbox$ymin)/1000))

# Example 2: Nesting relationships
cat("\n\nExample 2: Tile Nesting Relationships\n")
cat("--------------------------------------\n")

parent <- get_parent_tile(l2_idx$col, l2_idx$row)
parent_id <- make_tile_id(zone_info$zone_id, "L1", parent$col, parent$row)

cat(sprintf("L2 tile %s\n", l2_id))
cat(sprintf("  → Parent L1 tile: %s\n", parent_id))

if (parent$col == l1_idx$col && parent$row == l1_idx$row) {
  cat("  ✓ Correctly nested in containing L1 tile\n")
}

children <- get_child_tiles(l1_idx$col, l1_idx$row)
cat(sprintf("\nL1 tile %s\n", l1_id))
cat(sprintf("  → Contains %d child L2 tiles\n", nrow(children)))
cat(sprintf("  → Column range: %d to %d\n", min(children$col), max(children$col)))
cat(sprintf("  → Row range: %d to %d\n", min(children$row), max(children$row)))

cat("\n  First few child tile IDs:\n")
for (i in 1:min(6, nrow(children))) {
  child_id <- make_tile_id(zone_info$zone_id, "L2", 
                           children$col[i], children$row[i])
  cat(sprintf("    %s\n", child_id))
}

# Example 3: Coverage calculations
cat("\n\nExample 3: Coverage Analysis\n")
cat("----------------------------\n")

# Simulate a small region (5 L1 tiles)
n_l1_tiles <- 5
n_l2_tiles <- n_l1_tiles * GRID_SPEC$nesting_factor^2

cat(sprintf("Hypothetical region: %d L1 tiles\n", n_l1_tiles))
cat(sprintf("\nSpatial coverage:\n"))
cat(sprintf("  L1 grid: %.1f km² (%d tiles × %.0f km)\n",
            n_l1_tiles * (GRID_SPEC$L1$tile_size/1000)^2,
            n_l1_tiles, GRID_SPEC$L1$tile_size/1000))
cat(sprintf("  L2 grid: %.1f km² (%d tiles × %.0f km)\n",
            n_l2_tiles * (GRID_SPEC$L2$tile_size/1000)^2,
            n_l2_tiles, GRID_SPEC$L2$tile_size/1000))

cat(sprintf("\nPixel counts (if all tiles rendered):\n"))
cat(sprintf("  L1: %s pixels (%.1f megapixels)\n",
            format(n_l1_tiles * GRID_SPEC$L1$pixels^2, big.mark=","),
            n_l1_tiles * GRID_SPEC$L1$pixels^2 / 1e6))
cat(sprintf("  L2: %s pixels (%.1f megapixels)\n",
            format(n_l2_tiles * GRID_SPEC$L2$pixels^2, big.mark=","),
            n_l2_tiles * GRID_SPEC$L2$pixels^2 / 1e6))

# Example 4: Multi-zone coverage
cat("\n\nExample 4: Multi-Zone Scenarios\n")
cat("--------------------------------\n")

locations <- list(
  list(name = "Heard Island", lon = 73.5, lat = -53.0),
  list(name = "Macquarie Island", lon = 158.85, lat = -54.6),
  list(name = "Davis Station", lon = 77.97, lat = -68.58)
)

cat("Key AAT locations and their UTM zones:\n\n")
for (loc in locations) {
  zone_num <- floor((loc$lon + 180) / 6) + 1
  zone_info <- zones[zones$zone_number == zone_num, ]
  utm <- lonlat_to_utm(loc$lon, loc$lat, zone_num)
  l1_idx <- utm_to_tile_index(utm["x"], utm["y"], "L1",
                               zone_info$origin_x, zone_info$origin_y)
  tile_id <- make_tile_id(zone_info$zone_id, "L1", l1_idx$col, l1_idx$row)
  
  cat(sprintf("  %s (%.2f°E, %.2f°S)\n", loc$name, loc$lon, loc$lat))
  cat(sprintf("    Zone: %s\n", zone_info$zone_id))
  cat(sprintf("    L1 tile: %s\n\n", tile_id))
}

# Summary
cat("\nSystem Summary\n")
cat("==============\n")
cat("The grid system provides:\n")
cat("  ✓ Consistent tiling across all UTM zones\n")
cat("  ✓ Clean nesting between resolution levels\n")
cat("  ✓ Unique tile identifiers\n")
cat("  ✓ Simple coordinate ↔ tile index conversion\n")
cat("  ✓ Parent-child tile relationships\n")
cat("  ✓ Alignment with Sentinel-2 grid origins\n\n")

cat("Ready for integration with:\n")
cat("  • Imagery processing pipelines\n")
cat("  • Spatial databases\n")
cat("  • Web mapping applications\n")
cat("  • Scientific analysis workflows\n\n")
