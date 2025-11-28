# Generate Tile Grids for Regions of Interest
# This script creates actual tile sets that cover specific geographic areas
# Built with terra package



# ==============================================================================
# REGION OF INTEREST FUNCTIONS
# ==============================================================================

#' Generate tiles covering an extent
#' 
#' @param extent_lonlat Numeric vector c(xmin, xmax, ymin, ymax) in WGS84 lon/lat (terra ordering)
#' @param level Grid level ("L1" or "L2")
#' @param zones UTM zone definitions
#' @return SpatVector with all tiles covering the extent
#' @export
generate_tiles_for_extent <- function(extent_lonlat, level, zones) {
  
  # Determine which UTM zones intersect this extent
  lon_range <- c(extent_lonlat[1], extent_lonlat[2])
  
  # Calculate approximate UTM zones
  # UTM zone = floor((lon + 180) / 6) + 1
  zone_min <- floor((lon_range[1] + 180) / 6) + 1
  zone_max <- floor((lon_range[2] + 180) / 6) + 1
  
  relevant_zones <- zones[zones$zone_number >= zone_min & 
                          zones$zone_number <= zone_max, ]
  
  all_tiles <- list()
  
  for (i in 1:nrow(relevant_zones)) {
    zone <- relevant_zones[i, ]
    
    # Convert extent to this UTM zone
    extent_vect <- vect(
      matrix(c(extent_lonlat[1], extent_lonlat[3],
               extent_lonlat[2], extent_lonlat[3],
               extent_lonlat[2], extent_lonlat[4],
               extent_lonlat[1], extent_lonlat[4],
               extent_lonlat[1], extent_lonlat[3]),
             ncol = 2, byrow = TRUE),
      type = "polygons",
      crs = "EPSG:4326"
    )
    
    extent_utm <- project(extent_vect, zone$epsg)
    extent_utm_ext <- ext(extent_utm)
    
    # Calculate tile index ranges
    tile_size <- GRID_SPEC[[level]]$tile_size
    
    # extent is c(xmin, xmax, ymin, ymax)
    min_idx <- utm_to_tile_index(extent_utm_ext[1], extent_utm_ext[3], 
                                  level, zone$origin_x, zone$origin_y)
    max_idx <- utm_to_tile_index(extent_utm_ext[2], extent_utm_ext[4], 
                                  level, zone$origin_x, zone$origin_y)
    
    # Generate all tiles in range
    cols <- min_idx$col:max_idx$col
    rows <- min_idx$row:max_idx$row
    
    zone_tiles <- expand.grid(col = cols, row = rows)
    
    # Create tile polygons
    tiles_list <- lapply(1:nrow(zone_tiles), function(j) {
      create_tile_polygon(zone$zone_id, level, 
                         zone_tiles$col[j], 
                         zone_tiles$row[j], 
                         zones)
    })
    
    # Combine tiles for this zone
    if (length(tiles_list) > 0) {
      all_tiles[[i]] <- do.call(rbind, tiles_list)
    }
  }
  
  # Combine all zones
  if (length(all_tiles) > 0) {
    result <- do.call(rbind, all_tiles)
  } else {
    result <- NULL
  }
  
  return(result)
}

#' Generate tiles that intersect a spatial feature
#' 
#' @param feature_vect SpatVector object (polygon or multipolygon) in any CRS
#' @param level Grid level ("L1" or "L2")
#' @param zones UTM zone definitions
#' @param buffer_m Buffer distance in meters (optional)
#' @return SpatVector with tiles that intersect the feature
#' @export
generate_tiles_for_feature <- function(feature_vect, level, zones, buffer_m = 0) {
  
  # Get bbox in lon/lat
  feature_lonlat <- project(feature_vect, "EPSG:4326")
  bbox <- ext(feature_lonlat)
  
  # Generate tiles covering bbox
  bbox_vec <- c(xmin = bbox[1], ymin = bbox[3], xmax = bbox[2], ymax = bbox[4])
  candidate_tiles <- generate_tiles_for_bbox(bbox_vec, level, zones)
  
  if (is.null(candidate_tiles)) {
    return(NULL)
  }
  
  # Filter to only tiles that actually intersect the feature
  # For each unique zone, transform feature and test intersection
  zones_in_tiles <- unique(values(candidate_tiles)$zone_id)
  
  intersecting_tiles <- list()
  
  for (zone_id in zones_in_tiles) {
    zone_info <- zones[zones$zone_id == zone_id, ]
    zone_tile_idx <- values(candidate_tiles)$zone_id == zone_id
    zone_tiles <- candidate_tiles[zone_tile_idx, ]
    
    # Transform feature to this zone's CRS
    feature_utm <- project(feature_vect, zone_info$epsg)
    
    # Apply buffer if specified
    if (buffer_m > 0) {
      feature_utm <- buffer(feature_utm, buffer_m)
    }
    
    # Test intersection
    intersects <- relate(zone_tiles, feature_utm, "intersects")
    
    if (any(intersects)) {
      intersecting_tiles[[zone_id]] <- zone_tiles[intersects, ]
    }
  }
  
  # Combine results
  if (length(intersecting_tiles) > 0) {
    result <- do.call(rbind, intersecting_tiles)
  } else {
    result <- NULL
  }
  
  return(result)
}

# ==============================================================================
# PREDEFINED REGIONS
# ==============================================================================

#' Define extents for key AAT regions
#' 
#' @return list of extents in terra ordering c(xmin, xmax, ymin, ymax)
#' @export
get_aat_regions <- function() {
  list(
    # Heard Island and McDonald Islands
    heard_mcdonald = c(
      xmin = 72.5, xmax = 74.0,
      ymin = -53.5, ymax = -52.5
    ),
    
    # Macquarie Island
    macquarie = c(
      xmin = 158.5, xmax = 159.2,
      ymin = -54.8, ymax = -54.4
    ),
    
    # Main Antarctic continent (AAT sector)
    # 44°E to 160°E, focusing on 70°S to 60°S for UTM applicability
    aat_mainland = c(
      xmin = 44, xmax = 160,
      ymin = -70, ymax = -60
    ),
    
    # Extended region (includes all of concern up to 50°S)
    aat_extended = c(
      xmin = 44, xmax = 160,
      ymin = -70, ymax = -50
    )
  )
}

# ==============================================================================
# TILE HIERARCHY FUNCTIONS
# ==============================================================================

#' Generate matching L1 and L2 tile sets
#' 
#' @param feature_vect SpatVector to cover
#' @param zones UTM zone definitions
#' @return list with L1 and L2 tile sets
#' @export
generate_tile_hierarchy <- function(feature_vect, zones) {
  
  # Generate L1 tiles
  l1_tiles <- generate_tiles_for_feature(feature_vect, "L1", zones)
  
  if (is.null(l1_tiles)) {
    return(list(L1 = NULL, L2 = NULL))
  }
  
  # For each L1 tile, generate its child L2 tiles
  l1_values <- values(l1_tiles)
  l2_tiles_list <- lapply(1:nrow(l1_values), function(i) {
    children <- get_child_tiles(l1_values$col[i], l1_values$row[i])
    
    # Create L2 tile polygons
    tiles <- lapply(1:nrow(children), function(j) {
      create_tile_polygon(l1_values$zone_id[i], "L2", 
                         children$col[j], 
                         children$row[j], 
                         zones)
    })
    
    do.call(rbind, tiles)
  })
  
  l2_tiles <- do.call(rbind, l2_tiles_list)
  
  # Filter L2 tiles to those that intersect feature
  l2_tiles <- generate_tiles_for_feature(feature_vect, "L2", zones)
  
  list(
    L1 = l1_tiles,
    L2 = l2_tiles
  )
}

# ==============================================================================
# EXAMPLE USAGE
# ==============================================================================

if (FALSE) {
  # Initialize system
  zones <- define_utm_zones()
  regions <- get_aat_regions()
  
  # Generate tiles for Heard Island region
  heard_l1 <- generate_tiles_for_extent(regions$heard_mcdonald, "L1", zones)
  heard_l2 <- generate_tiles_for_extent(regions$heard_mcdonald, "L2", zones)
  
  print(paste("Heard Island region:"))
  print(paste("  L1 tiles:", nrow(values(heard_l1))))
  print(paste("  L2 tiles:", nrow(values(heard_l2))))
  
  # Check nesting (should be 36 L2 per L1)
  print(paste("  Ratio:", nrow(values(heard_l2)) / nrow(values(heard_l1))))
  
  # Generate tiles for Macquarie Island
  macq_l1 <- generate_tiles_for_extent(regions$macquarie, "L1", zones)
  macq_l2 <- generate_tiles_for_extent(regions$macquarie, "L2", zones)
  
  print(paste("Macquarie Island region:"))
  print(paste("  L1 tiles:", nrow(values(macq_l1))))
  print(paste("  L2 tiles:", nrow(values(macq_l2))))
  
  # Save tile sets
  writeVector(heard_l1, "heard_island_L1_tiles.gpkg", overwrite = TRUE)
  writeVector(heard_l2, "heard_island_L2_tiles.gpkg", overwrite = TRUE)
}

# ==============================================================================
# TILE CATALOG FUNCTIONS
# ==============================================================================

#' Create a tile catalog data frame
#' 
#' @param tiles_vect SpatVector with tiles
#' @return data.frame with tile metadata
#' @export
create_tile_catalog <- function(tiles_vect) {
  
  catalog <- values(tiles_vect)
  
  # Add additional metadata
  level <- catalog$level[1]
  catalog$tile_size_m <- GRID_SPEC[[level]]$tile_size
  catalog$resolution_m <- GRID_SPEC[[level]]$resolution
  catalog$pixels <- GRID_SPEC[[level]]$pixels
  
  # Add extent coordinates (terra ordering: xmin, xmax, ymin, ymax)
  extents <- do.call(rbind, lapply(1:nrow(catalog), function(i) {
    tile_ext <- ext(tiles_vect[i, ])
    data.frame(
      xmin = tile_ext[1], 
      xmax = tile_ext[2], 
      ymin = tile_ext[3], 
      ymax = tile_ext[4]
    )
  }))
  
  catalog <- cbind(catalog, extents)
  
  return(catalog)
}

#' Export tile catalog to CSV
#' 
#' @param tiles_vect SpatVector with tiles
#' @param filename Output CSV filename
#' @export
export_tile_catalog <- function(tiles_vect, filename) {
  catalog <- create_tile_catalog(tiles_vect)
  write.csv(catalog, filename, row.names = FALSE)
  message("Tile catalog exported to: ", filename)
}
