# Antarctic Territory Grid System
# Based on UTM zones with Sentinel-2 grid alignment
# Coverage: Australian Antarctic Territory (44°E to 160°E, terrestrial focus)
# Built with terra package

#' @importFrom terra vect ext project crs values rast res
NULL

# Global grid specification - internal to package
.onLoad <- function(libname, pkgname) {
  # Grid specifications are loaded into package environment
  invisible()
}

#' Define UTM zones covering Australian Antarctic Territory
#'
#' Creates a data frame with specifications for UTM zones 42S through 58S,
#' covering the longitude range of the Australian Antarctic Territory.
#' Each zone includes grid origin coordinates aligned with Sentinel-2.
#'
#' @return data.frame with columns:
#'   \itemize{
#'     \item zone_number: UTM zone number (42-58)
#'     \item hemisphere: Hemisphere code ("S")
#'     \item epsg: EPSG code as string (e.g., "EPSG:32743")
#'     \item origin_x: Grid origin easting (Sentinel-2 standard: 166021)
#'     \item origin_y: Grid origin northing (0)
#'     \item central_meridian: Central meridian longitude for the zone
#'     \item zone_id: Zone identifier (e.g., "43S")
#'   }
#' @export
#' @examples
#' zones <- define_utm_zones()
#' print(zones[zones$zone_id == "43S", ])
define_utm_zones <- function() {
  # Zones covering AAT longitude range (44°E to 160°E)
  zone_numbers <- 39:60  # Conservative range to ensure full coverage

  zones <- data.frame(
    zone_number = zone_numbers,
    hemisphere = "S",
    epsg = paste0("EPSG:327", zone_numbers),
    # Sentinel-2 grid origin (standard for UTM southern hemisphere)
    #origin_x = 166021,
    origin_x = 140000,
    origin_y = 20000,
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
#' @export
utm_to_tile_index <- function(x, y, level) {
  tile_size <- GRID_SPEC[[level]]$tile_size
  zones <- define_utm_zones()
  # Calculate tile indices (floor division from origin)
  col <- floor((x - zones$origin_x[1L]) / tile_size)
  row <- floor((y - zones$origin_y[1L]) / tile_size)

  data.frame(col = col, row = row)
}

#' Convert tile indices to UTM extent
#'
#' @param col Tile column index
#' @param row Tile row index
#' @param level Grid level ("L1" or "L2")
#' @param origin_x Grid origin easting
#' @param origin_y Grid origin northing
#' @return numeric vector c(xmin, xmax, ymin, ymax) - terra ordering
#' @export
tile_index_to_extent <- function(col, row, level, origin_x = 166021, origin_y = 0) {
  tile_size <- GRID_SPEC[[level]]$tile_size

  xmin <- origin_x + (col * tile_size)
  ymin <- origin_y + (row * tile_size)
  xmax <- xmin + tile_size
  ymax <- ymin + tile_size

  cbind(xmin = xmin, xmax = xmax, ymin = ymin, ymax = ymax)
}

#' Generate tile ID string
#'
#' @param zone_id Zone identifier (e.g., "55S")
#' @param level Grid level ("L1" or "L2")
#' @param col Tile column index
#' @param row Tile row index
#' @return character tile ID (e.g., "55S_L1_0123_0456")
#' @export
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
#' @export
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
#' @export
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
#' @export
get_child_tiles <- function(l1_col, l1_row) {
  nf <- GRID_SPEC$nesting_factor

  # Generate all 6x6 child tiles
  child_cols <- rep(l1_col * nf + 0:(nf-1), each = nf)
  child_rows <- rep(l1_row * nf + 0:(nf-1), times = nf)

  data.frame(col = child_cols, row = child_rows)
}

# ==============================================================================
# SPATIAL FUNCTIONS (TERRA-BASED)
# ==============================================================================

#' Create SpatVector polygon for a tile
#'
#' @param zone_id Zone identifier
#' @param level Grid level
#' @param col Tile column
#' @param row Tile row
#' @param zones UTM zone definitions
#' @return SpatVector object with tile polygon
#' @export
create_tile_polygon <- function(zone_id, level, col, row, zones) {
  zone_info <- zones[zones$zone_id == zone_id, ]

  tile_ext <- tile_index_to_extent(col, row, level,
                                    zone_info$origin_x,
                                    zone_info$origin_y)

  # Create polygon from extent using terra ordering
  # tile_ext is c(xmin, xmax, ymin, ymax)
  coords <- matrix(c(
    tile_ext[1], tile_ext[3],  # xmin, ymin
    tile_ext[2], tile_ext[3],  # xmax, ymin
    tile_ext[2], tile_ext[4],  # xmax, ymax
    tile_ext[1], tile_ext[4],  # xmin, ymax
    tile_ext[1], tile_ext[3]   # xmin, ymin (close)
  ), ncol = 2, byrow = TRUE)

  # Create SpatVector polygon
  tile_vect <- vect(coords, type = "polygons", crs = zone_info$epsg)

  # Add attributes
  tile_id <- make_tile_id(zone_id, level, col, row)
  values(tile_vect) <- data.frame(
    tile_id = tile_id,
    zone_id = zone_id,
    level = level,
    col = col,
    row = row
  )

  return(tile_vect)
}

#' Create SpatExtent for a tile
#'
#' @param zone_id Zone identifier
#' @param level Grid level
#' @param col Tile column
#' @param row Tile row
#' @param zones UTM zone definitions
#' @return SpatExtent object
#' @export
create_tile_extent <- function(zone_id, level, col, row, zones) {
  zone_info <- zones[zones$zone_id == zone_id, ]

  tile_ext <- tile_index_to_extent(col, row, level,
                                    zone_info$origin_x,
                                    zone_info$origin_y)

  # terra ext() takes xmin, xmax, ymin, ymax
  ext(tile_ext[1], tile_ext[2], tile_ext[3], tile_ext[4])
}

#' Create template SpatRaster for a tile
#'
#' @param zone_id Zone identifier
#' @param level Grid level
#' @param col Tile column
#' @param row Tile row
#' @param zones UTM zone definitions
#' @return SpatRaster template (empty raster with correct extent/resolution)
#' @export
create_tile_template <- function(zone_id, level, col, row, zones) {
  zone_info <- zones[zones$zone_id == zone_id, ]

  # Get tile extent
  tile_ext <- create_tile_extent(zone_id, level, col, row, zones)

  # Create raster template
  npixels <- GRID_SPEC[[level]]$pixels
  resolution <- GRID_SPEC[[level]]$resolution

  r <- rast(tile_ext, nrows = npixels, ncols = npixels, crs = zone_info$epsg)

  # Add metadata
  names(r) <- make_tile_id(zone_id, level, col, row)

  return(r)
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

  # Example tile polygon
  example_tile <- create_tile_polygon("43S", "L1", 10, -50, zones)
  print(example_tile)

  # Example tile extent
  example_ext <- create_tile_extent("43S", "L1", 10, -50, zones)
  print(example_ext)

  # Example tile raster template
  example_rast <- create_tile_template("43S", "L1", 10, -50, zones)
  print(example_rast)

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
#' @export
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
#' @export
load_grid_spec <- function(filename = "antarctic_grid_spec.rds") {
  if (!file.exists(filename)) {
    stop("Grid specification file not found: ", filename)
  }
  readRDS(filename)
}
