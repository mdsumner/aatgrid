# Raster-based Tile Identification System
# Fast tile identification using raster specifications
# Built with terra package



# ==============================================================================
# ZONE RASTER SPECIFICATIONS
# ==============================================================================

#' Create raster specification for a UTM zone at a given level
#' 
#' Each cell in the raster represents one tile in the grid.
#' This provides a fast spatial index for tile identification.
#' 
#' @param zone_id Zone identifier (e.g., "43S")
#' @param level Grid level ("L1" or "L2")
#' @param zones UTM zone definitions
#' @param zone_extent Optional: limit extent (xmin, xmax, ymin, ymax) in UTM coords
#' @return SpatRaster where each cell = one tile
#' @export
create_zone_raster <- function(zone_id, level, zones, zone_extent = NULL) {
  zone_info <- zones[zones$zone_id == zone_id, ]
  
  tile_size <- GRID_SPEC[[level]]$tile_size
  
  # Define extent for the zone if not specified
  if (is.null(zone_extent)) {
    # Create extent covering typical Antarctic latitudes
    # Adjust these based on your needs
    zone_extent <- c(
      xmin = zone_info$origin_x - 500000,  # 500 km west of origin
      xmax = zone_info$origin_x + 1500000, # 1500 km east of origin  
      ymin = zone_info$origin_y + 3000000, # Southern latitudes
      ymax = zone_info$origin_y + 6500000  # Northern latitudes
    )
  }
  
  # Align extent to tile boundaries
  # Snap to tile grid using origin
  xmin_snap <- zone_info$origin_x + 
    floor((zone_extent[1] - zone_info$origin_x) / tile_size) * tile_size
  xmax_snap <- zone_info$origin_x + 
    ceiling((zone_extent[2] - zone_info$origin_x) / tile_size) * tile_size
  ymin_snap <- zone_info$origin_y + 
    floor((zone_extent[3] - zone_info$origin_y) / tile_size) * tile_size
  ymax_snap <- zone_info$origin_y + 
    ceiling((zone_extent[4] - zone_info$origin_y) / tile_size) * tile_size
  
  # Create extent (terra ordering: xmin, xmax, ymin, ymax)
  zone_ext <- ext(xmin_snap, xmax_snap, ymin_snap, ymax_snap)
  
  # Calculate dimensions (each cell = one tile)
  ncols <- round((xmax_snap - xmin_snap) / tile_size)
  nrows <- round((ymax_snap - ymin_snap) / tile_size)
  
  # Create raster
  r <- rast(zone_ext, nrows = nrows, ncols = ncols, crs = zone_info$epsg)
  
  # Set resolution explicitly to ensure exact tile size
  res(r) <- c(tile_size, tile_size)
  
  # Add metadata
  names(r) <- paste0(zone_id, "_", level, "_grid")
  
  # Initialize with NA (no tiles identified yet)
  values(r) <- NA
  
  return(r)
}

#' Create raster specifications for all zones at a level
#' 
#' @param level Grid level ("L1" or "L2")
#' @param zones UTM zone definitions
#' @param zone_ids Optional: vector of zone IDs (default: all AAT zones)
#' @return Named list of SpatRaster objects
#' @export
create_all_zone_rasters <- function(level, zones, zone_ids = NULL) {
  if (is.null(zone_ids)) {
    zone_ids <- zones$zone_id
  }
  
  raster_list <- lapply(zone_ids, function(zid) {
    create_zone_raster(zid, level, zones)
  })
  
  names(raster_list) <- zone_ids
  
  return(raster_list)
}

# ==============================================================================
# FAST TILE IDENTIFICATION
# ==============================================================================

#' Rasterize features to identify intersecting tiles
#' 
#' @param features SpatVector of features to rasterize
#' @param zone_raster SpatRaster template for the zone (each cell = one tile)
#' @param buffer_m Optional buffer distance in meters
#' @return SpatRaster with 1 where tiles intersect features, 0 elsewhere
#' @export
identify_intersecting_tiles <- function(features, zone_raster, buffer_m = 0) {
  # Project features to raster CRS if needed
  if (!is.null(crs(features)) && crs(features) != crs(zone_raster)) {
    features <- project(features, crs(zone_raster))
  }
  
  # Apply buffer if specified
  if (buffer_m > 0) {
    features <- buffer(features, buffer_m)
  }
  
  # Rasterize - cells touching features get value 1
  # Using touches=TRUE ensures edge cases are captured
  rasterized <- rasterize(features, zone_raster, touches = TRUE, background = 0)
  
  # Convert to binary (any intersection = 1)
  rasterized[rasterized > 0] <- 1
  
  return(rasterized)
}

#' Get tile indices from raster cell indices
#' 
#' @param zone_raster SpatRaster with tiles as cells
#' @param cell_indices Vector of cell indices
#' @return data.frame with cell, col, row indices
cells_to_tile_indices <- function(zone_raster, cell_indices) {
  # Get row/col from cell indices (terra is 1-based)
  rc <- rowColFromCell(zone_raster, cell_indices)
  
  # Convert to 0-based tile indices
  # Terra rows go from top to bottom, need to invert for our grid
  # Adjust based on grid origin convention
  data.frame(
    cell = cell_indices,
    col = rc[, 2] - 1,  # 0-based column
    row = rc[, 1] - 1   # 0-based row
  )
}

#' Fast workflow: features to tile list
#' 
#' @param features SpatVector of features (polygons, lines, points)
#' @param zone_id Zone identifier
#' @param level Grid level ("L1" or "L2")
#' @param zones UTM zone definitions
#' @param zone_raster Optional: pre-created zone raster (for efficiency)
#' @param buffer_m Optional buffer in meters
#' @return data.frame with tile_id, zone_id, level, col, row
#' @export
fast_identify_tiles <- function(features, zone_id, level, zones, 
                                zone_raster = NULL, buffer_m = 0) {
  
  # Create zone raster if not provided
  if (is.null(zone_raster)) {
    zone_raster <- create_zone_raster(zone_id, level, zones)
  }
  
  # Identify intersecting cells
  intersect_rast <- identify_intersecting_tiles(features, zone_raster, buffer_m)
  
  # Get cell indices where value == 1
  cell_idx <- which(values(intersect_rast) == 1)
  
  if (length(cell_idx) == 0) {
    return(data.frame(
      tile_id = character(0),
      zone_id = character(0),
      level = character(0),
      col = integer(0),
      row = integer(0)
    ))
  }
  
  # Convert to tile indices
  tile_indices <- cells_to_tile_indices(zone_raster, cell_idx)
  
  # Create tile IDs
  tile_ids <- make_tile_id(zone_id, level, tile_indices$col, tile_indices$row)
  
  # Return as data frame
  result <- data.frame(
    tile_id = tile_ids,
    zone_id = zone_id,
    level = level,
    col = tile_indices$col,
    row = tile_indices$row,
    stringsAsFactors = FALSE
  )
  
  return(result)
}

#' Fast workflow for multiple zones
#' 
#' @param features SpatVector of features in any CRS
#' @param zone_ids Vector of zone IDs to check
#' @param level Grid level ("L1" or "L2")
#' @param zones UTM zone definitions
#' @param buffer_m Optional buffer in meters
#' @return data.frame with all intersecting tiles across zones
#' @export
fast_identify_tiles_multizone <- function(features, zone_ids, level, zones, 
                                         buffer_m = 0) {
  
  # Get feature extent in lon/lat
  features_lonlat <- project(features, "EPSG:4326")
  feat_ext <- ext(features_lonlat)
  
  # Filter zones that might intersect based on longitude
  # UTM zone = floor((lon + 180) / 6) + 1
  lon_range <- c(feat_ext[1], feat_ext[2])
  zone_min <- floor((lon_range[1] + 180) / 6) + 1
  zone_max <- floor((lon_range[2] + 180) / 6) + 1
  
  relevant_zone_ids <- zones$zone_id[zones$zone_number >= zone_min & 
                                     zones$zone_number <= zone_max]
  relevant_zone_ids <- intersect(relevant_zone_ids, zone_ids)
  
  if (length(relevant_zone_ids) == 0) {
    return(data.frame(
      tile_id = character(0),
      zone_id = character(0),
      level = character(0),
      col = integer(0),
      row = integer(0)
    ))
  }
  
  # Process each zone
  tiles_list <- lapply(relevant_zone_ids, function(zid) {
    fast_identify_tiles(features, zid, level, zones, buffer_m = buffer_m)
  })
  
  # Combine results
  do.call(rbind, tiles_list)
}

# ==============================================================================
# TILE MATERIALIZATION HELPERS
# ==============================================================================

#' Create tile templates only for identified tiles
#' 
#' @param tile_df data.frame from fast_identify_tiles with tile_id, zone_id, col, row
#' @param zones UTM zone definitions
#' @return List of SpatRaster templates
#' @export
create_tile_templates_from_df <- function(tile_df, zones) {
  
  templates <- lapply(1:nrow(tile_df), function(i) {
    create_tile_template(
      tile_df$zone_id[i],
      tile_df$level[i],
      tile_df$col[i],
      tile_df$row[i],
      zones
    )
  })
  
  names(templates) <- tile_df$tile_id
  
  return(templates)
}

#' Get tile extents for identified tiles
#' 
#' @param tile_df data.frame from fast_identify_tiles
#' @param zones UTM zone definitions  
#' @return data.frame with tile_id and extent columns (xmin, xmax, ymin, ymax)
#' @export
get_tile_extents_from_df <- function(tile_df, zones) {
  
  extents <- lapply(1:nrow(tile_df), function(i) {
    zone_info <- zones[zones$zone_id == tile_df$zone_id[i], ]
    tile_ext <- tile_index_to_extent(
      tile_df$col[i],
      tile_df$row[i],
      tile_df$level[i],
      zone_info$origin_x,
      zone_info$origin_y
    )
    
    data.frame(
      tile_id = tile_df$tile_id[i],
      xmin = tile_ext[1],
      xmax = tile_ext[2],
      ymin = tile_ext[3],
      ymax = tile_ext[4]
    )
  })
  
  do.call(rbind, extents)
}

# ==============================================================================
# EXAMPLE USAGE
# ==============================================================================

if (FALSE) {
  library(terra)
  source("antarctic_grid_system.R")
  source("raster_tile_identification.R")
  
  zones <- define_utm_zones()
  
  # Example 1: Create zone raster specifications
  heard_l1_spec <- create_zone_raster("43S", "L1", zones)
  heard_l2_spec <- create_zone_raster("43S", "L2", zones)
  
  print(heard_l1_spec)
  print(heard_l2_spec)
  
  # Example 2: Load some features (coastline, ice extent, etc.)
  # features <- vect("coastline.gpkg")
  
  # Example 3: Fast identify tiles
  # tiles_l1 <- fast_identify_tiles(features, "43S", "L1", zones)
  # tiles_l2 <- fast_identify_tiles(features, "43S", "L2", zones)
  
  # print(head(tiles_l1))
  # print(paste("Identified", nrow(tiles_l1), "L1 tiles"))
  # print(paste("Identified", nrow(tiles_l2), "L2 tiles"))
  
  # Example 4: Get tile extents for rendering
  # tile_extents <- get_tile_extents_from_df(tiles_l2, zones)
  # print(head(tile_extents))
  
  # Example 5: Create raster templates only for needed tiles
  # templates <- create_tile_templates_from_df(tiles_l2[1:10, ], zones)
  # 
  # # Now process imagery into each template
  # for (tid in names(templates)) {
  #   template <- templates[[tid]]
  #   # Load and crop your 10m imagery to this template
  #   # imagery <- rast("source_image.tif")
  #   # tile_img <- crop(imagery, template)
  #   # writeRaster(tile_img, paste0(tid, ".tif"))
  # }
  
  # Example 6: Multi-zone workflow
  # tiles_all <- fast_identify_tiles_multizone(
  #   features, 
  #   zone_ids = c("42S", "43S", "44S"),
  #   level = "L2",
  #   zones = zones
  # )
}
