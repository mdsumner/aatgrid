# Antarctic Territory Grid System
# Based on UTM zones with Sentinel-2 grid alignment
# Coverage: Australian Antarctic Territory (44°E to 160°E, terrestrial focus)

library(sf)
library(dplyr)

# ==============================================================================
# GRID SPECIFICATION
# ==============================================================================

# Define the grid system parameters
GRID_SPEC <- list(
  # Level 1: Coarse grid
  L1 = list(
    tile_size = 36000,      # meters (36 km)
    resolution = 60,        # meters per pixel
    pixels = 600            # 600 x 600 pixels
  ),
  
  # Level 2: Fine grid  
  L2 = list(
    tile_size = 6000,       # meters (6 km)
    resolution = 10,        # meters per pixel
    pixels = 600            # 600 x 600 pixels
  ),
  
  # Nesting relationship
  nesting_factor = 6        # 6x6 L2 tiles per L1 tile
)

# ==============================================================================
# UTM ZONE DEFINITIONS
# ==============================================================================

# Define UTM zones covering Australian Antarctic Territory
# Zone numbers 42-58 cover roughly 44°E to 160°E
# All southern hemisphere (S suffix)

# Sentinel-2 uses specific origins for each UTM zone
# For UTM southern hemisphere: origin is typically at (x=166021, y=0)
# This offset accounts for the UTM false easting adjustment

define_utm_zones <- function() {
  # Zones covering AAT longitude range (44°E to 160°E)
  zone_numbers <- 42:58  # Conservative range to ensure full coverage
  
  zones <- data.frame(
    zone_number = zone_numbers,
    hemisphere = "S",
    epsg = paste0("EPSG:327", zone_numbers),
    # Sentinel-2 grid origin (standard for UTM southern hemisphere)
    origin_x = 166021,
    origin_y = 0,
    # Central meridian for each zone
    central_meridian = -183 + (zone_numbers * 6),
    stringsAsFactors = FALSE
  )
  
  # Add zone ID (e.g., "42S", "43S", ...)
  zones$zone_id <- paste0(zones$zone_number, zones$hemisphere)
  
  return(zones)
}

# ==============================================================================
# TILE INDEXING FUNCTIONS
# ==============================================================================

#' Convert UTM coordinates to tile indices
#' 
#' @param x UTM easting coordinate(s)
#' @param y UTM northing coordinate(s)
#' @param level Grid level ("L1" or "L2")
#' @param origin_x Grid origin easting (default: Sentinel-2 origin)
#' @param origin_y Grid origin northing (default: 0)
#' @return data.frame with col and row indices
utm_to_tile_index <- function(x, y, level, origin_x = 166021, origin_y = 0) {
  tile_size <- GRID_SPEC[[level]]$tile_size
  
  # Calculate tile indices (floor division from origin)
  col <- floor((x - origin_x) / tile_size)
  row <- floor((y - origin_y) / tile_size)
  
  data.frame(col = col, row = row)
}

#' Convert tile indices to UTM bounding box
#' 
#' @param col Tile column index
#' @param row Tile row index
#' @param level Grid level ("L1" or "L2")
#' @param origin_x Grid origin easting
#' @param origin_y Grid origin northing
#' @return data.frame with xmin, ymin, xmax, ymax
tile_index_to_bbox <- function(col, row, level, origin_x = 166021, origin_y = 0) {
  tile_size <- GRID_SPEC[[level]]$tile_size
  
  xmin <- origin_x + (col * tile_size)
  ymin <- origin_y + (row * tile_size)
  xmax <- xmin + tile_size
  ymax <- ymin + tile_size
  
  data.frame(xmin = xmin, ymin = ymin, xmax = xmax, ymax = ymax)
}

#' Generate tile ID string
#' 
#' @param zone_id Zone identifier (e.g., "55S")
#' @param level Grid level ("L1" or "L2")
#' @param col Tile column index
#' @param row Tile row index
#' @return character tile ID (e.g., "55S_L1_0123_0456")
make_tile_id <- function(zone_id, level, col, row) {
  # Format with leading zeros for readability and sorting
  paste0(zone_id, "_", level, "_", 
         sprintf("%04d", col), "_", 
         sprintf("%04d", row))
}

#' Parse tile ID string
#' 
#' @param tile_id Tile identifier string
#' @return list with zone_id, level, col, row
parse_tile_id <- function(tile_id) {
  parts <- strsplit(tile_id, "_")[[1]]
  list(
    zone_id = parts[1],
    level = parts[2],
    col = as.integer(parts[3]),
    row = as.integer(parts[4])
  )
}

#' Get parent tile (L2 -> L1)
#' 
#' @param l2_col L2 tile column index
#' @param l2_row L2 tile row index
#' @return data.frame with parent L1 col and row
get_parent_tile <- function(l2_col, l2_row) {
  nf <- GRID_SPEC$nesting_factor
  data.frame(
    col = floor(l2_col / nf),
    row = floor(l2_row / nf)
  )
}

#' Get child tiles (L1 -> L2)
#' 
#' @param l1_col L1 tile column index
#' @param l1_row L1 tile row index
#' @return data.frame with all child L2 col and row indices
get_child_tiles <- function(l1_col, l1_row) {
  nf <- GRID_SPEC$nesting_factor
  
  # Generate all 6x6 child tiles
  child_cols <- rep(l1_col * nf + 0:(nf-1), each = nf)
  child_rows <- rep(l1_row * nf + 0:(nf-1), times = nf)
  
  data.frame(col = child_cols, row = child_rows)
}

# ==============================================================================
# SPATIAL FUNCTIONS
# ==============================================================================

#' Create sf polygon for a tile
#' 
#' @param zone_id Zone identifier
#' @param level Grid level
#' @param col Tile column
#' @param row Tile row
#' @param zones UTM zone definitions
#' @return sf object with tile polygon
create_tile_polygon <- function(zone_id, level, col, row, zones) {
  zone_info <- zones[zones$zone_id == zone_id, ]
  
  bbox <- tile_index_to_bbox(col, row, level, 
                              zone_info$origin_x, 
                              zone_info$origin_y)
  
  # Create polygon from bbox
  poly <- st_polygon(list(matrix(c(
    bbox$xmin, bbox$ymin,
    bbox$xmax, bbox$ymin,
    bbox$xmax, bbox$ymax,
    bbox$xmin, bbox$ymax,
    bbox$xmin, bbox$ymin
  ), ncol = 2, byrow = TRUE)))
  
  # Convert to sf with CRS
  tile_sf <- st_sf(
    tile_id = make_tile_id(zone_id, level, col, row),
    zone_id = zone_id,
    level = level,
    col = col,
    row = row,
    geometry = st_sfc(poly, crs = zone_info$epsg)
  )
  
  return(tile_sf)
}

# ==============================================================================
# EXAMPLE USAGE
# ==============================================================================

if (FALSE) {
  # Initialize zones
  zones <- define_utm_zones()
  print(zones)
  
  # Example: Create a tile at a specific location
  # Heard Island is approximately at 73°E, 53°S
  # This falls in UTM zone 43S
  
  # Example tile indices
  example_tile <- create_tile_polygon("43S", "L1", 10, -50, zones)
  print(example_tile)
  
  # Get children of an L1 tile
  children <- get_child_tiles(10, -50)
  print(head(children))
  
  # Get parent of an L2 tile
  parent <- get_parent_tile(62, -298)
  print(parent)
}

# ==============================================================================
# SAVE GRID SPECIFICATION
# ==============================================================================

#' Save grid specification to RDS file
save_grid_spec <- function(filename = "antarctic_grid_spec.rds") {
  zones <- define_utm_zones()
  
  spec <- list(
    grid_params = GRID_SPEC,
    utm_zones = zones,
    created = Sys.time(),
    description = "Australian Antarctic Territory grid system aligned to Sentinel-2"
  )
  
  saveRDS(spec, filename)
  message("Grid specification saved to: ", filename)
  return(spec)
}

#' Load grid specification from RDS file
load_grid_spec <- function(filename = "antarctic_grid_spec.rds") {
  if (!file.exists(filename)) {
    stop("Grid specification file not found: ", filename)
  }
  readRDS(filename)
}
