# Generate Tile Grids for Regions of Interest
# This script creates actual tile sets that cover specific geographic areas

library(sf)
library(dplyr)


# ==============================================================================
# REGION OF INTEREST FUNCTIONS
# ==============================================================================

#' Generate tiles covering a bounding box
#' 
#' @param bbox_lonlat Vector c(xmin, ymin, xmax, ymax) in WGS84 lon/lat
#' @param level Grid level ("L1" or "L2")
#' @param zones UTM zone definitions
#' @return sf object with all tiles covering the region
generate_tiles_for_bbox <- function(bbox_lonlat, level, zones) {
  
  # Determine which UTM zones intersect this bbox
  lon_range <- c(bbox_lonlat[1], bbox_lonlat[3])
  
  # Calculate approximate UTM zones
  # UTM zone = floor((lon + 180) / 6) + 1
  zone_min <- floor((lon_range[1] + 180) / 6) + 1
  zone_max <- floor((lon_range[2] + 180) / 6) + 1
  
  relevant_zones <- zones[zones$zone_number >= zone_min & 
                          zones$zone_number <= zone_max, ]
  
  all_tiles <- list()
  
  for (i in 1:nrow(relevant_zones)) {
    zone <- relevant_zones[i, ]
    
    # Convert bbox to this UTM zone
    bbox_sf <- st_bbox(c(xmin = bbox_lonlat[1], 
                         ymin = bbox_lonlat[2],
                         xmax = bbox_lonlat[3], 
                         ymax = bbox_lonlat[4]),
                       crs = 4326) %>% 
      st_as_sfc() %>%
      st_transform(zone$epsg) %>%
      st_bbox()
    
    # Calculate tile index ranges
    tile_size <- GRID_SPEC[[level]]$tile_size
    
    min_idx <- utm_to_tile_index(bbox_sf["xmin"], bbox_sf["ymin"], 
                                  level, zone$origin_x, zone$origin_y)
    max_idx <- utm_to_tile_index(bbox_sf["xmax"], bbox_sf["ymax"], 
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
    
    all_tiles[[i]] <- do.call(rbind, tiles_list)
  }
  
  # Combine all zones
  result <- do.call(rbind, all_tiles)
  
  return(result)
}

#' Generate tiles that intersect a spatial feature
#' 
#' @param feature_sf sf object (polygon or multipolygon) in any CRS
#' @param level Grid level ("L1" or "L2")
#' @param zones UTM zone definitions
#' @param buffer_m Buffer distance in meters (optional)
#' @return sf object with tiles that intersect the feature
generate_tiles_for_feature <- function(feature_sf, level, zones, buffer_m = 0) {
  
  # Get bbox in lon/lat
  feature_lonlat <- st_transform(feature_sf, 4326)
  bbox <- st_bbox(feature_lonlat)
  
  # Generate tiles covering bbox
  candidate_tiles <- generate_tiles_for_bbox(
    c(bbox["xmin"], bbox["ymin"], bbox["xmax"], bbox["ymax"]),
    level, zones
  )
  
  # Filter to only tiles that actually intersect the feature
  # For each unique zone, transform feature and test intersection
  zones_in_tiles <- unique(candidate_tiles$zone_id)
  
  intersecting_tiles <- list()
  
  for (zone_id in zones_in_tiles) {
    zone_info <- zones[zones$zone_id == zone_id, ]
    zone_tiles <- candidate_tiles[candidate_tiles$zone_id == zone_id, ]
    
    # Transform feature to this zone's CRS
    feature_utm <- st_transform(feature_sf, zone_info$epsg)
    
    # Apply buffer if specified
    if (buffer_m > 0) {
      feature_utm <- st_buffer(feature_utm, buffer_m)
    }
    
    # Test intersection
    intersects <- st_intersects(zone_tiles, feature_utm, sparse = FALSE)
    
    intersecting_tiles[[zone_id]] <- zone_tiles[rowSums(intersects) > 0, ]
  }
  
  result <- do.call(rbind, intersecting_tiles)
  rownames(result) <- NULL
  
  return(result)
}

# ==============================================================================
# PREDEFINED REGIONS
# ==============================================================================

#' Define bounding boxes for key AAT regions
get_aat_regions <- function() {
  list(
    # Heard Island and McDonald Islands
    heard_mcdonald = c(
      xmin = 72.5, ymin = -53.5,
      xmax = 74.0, ymax = -52.5
    ),
    
    # Macquarie Island
    macquarie = c(
      xmin = 158.5, ymin = -54.8,
      xmax = 159.2, ymax = -54.4
    ),
    
    # Main Antarctic continent (AAT sector)
    # 44°E to 160°E, focusing on 70°S to 60°S for UTM applicability
    aat_mainland = c(
      xmin = 44, ymin = -70,
      xmax = 160, ymax = -60
    ),
    
    # Extended region (includes all of concern up to 50°S)
    aat_extended = c(
      xmin = 44, ymin = -70,
      xmax = 160, ymax = -50
    )
  )
}

# ==============================================================================
# TILE HIERARCHY FUNCTIONS
# ==============================================================================

#' Generate matching L1 and L2 tile sets
#' 
#' @param feature_sf Spatial feature to cover
#' @param zones UTM zone definitions
#' @return list with L1 and L2 tile sets
generate_tile_hierarchy <- function(feature_sf, zones) {
  
  # Generate L1 tiles
  l1_tiles <- generate_tiles_for_feature(feature_sf, "L1", zones)
  
  # For each L1 tile, generate its child L2 tiles
  l2_tiles_list <- lapply(1:nrow(l1_tiles), function(i) {
    l1 <- l1_tiles[i, ]
    children <- get_child_tiles(l1$col, l1$row)
    
    # Create L2 tile polygons
    tiles <- lapply(1:nrow(children), function(j) {
      create_tile_polygon(l1$zone_id, "L2", 
                         children$col[j], 
                         children$row[j], 
                         zones)
    })
    
    do.call(rbind, tiles)
  })
  
  l2_tiles <- do.call(rbind, l2_tiles_list)
  rownames(l2_tiles) <- NULL
  
  # Filter L2 tiles to those that intersect feature
  l2_tiles <- generate_tiles_for_feature(feature_sf, "L2", zones)
  
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
  heard_l1 <- generate_tiles_for_bbox(regions$heard_mcdonald, "L1", zones)
  heard_l2 <- generate_tiles_for_bbox(regions$heard_mcdonald, "L2", zones)
  
  print(paste("Heard Island region:"))
  print(paste("  L1 tiles:", nrow(heard_l1)))
  print(paste("  L2 tiles:", nrow(heard_l2)))
  
  # Check nesting (should be 36 L2 per L1)
  print(paste("  Ratio:", nrow(heard_l2) / nrow(heard_l1)))
  
  # Generate tiles for Macquarie Island
  macq_l1 <- generate_tiles_for_bbox(regions$macquarie, "L1", zones)
  macq_l2 <- generate_tiles_for_bbox(regions$macquarie, "L2", zones)
  
  print(paste("Macquarie Island region:"))
  print(paste("  L1 tiles:", nrow(macq_l1)))
  print(paste("  L2 tiles:", nrow(macq_l2)))
  
  # Save tile sets
  st_write(heard_l1, "heard_island_L1_tiles.gpkg", delete_dsn = TRUE)
  st_write(heard_l2, "heard_island_L2_tiles.gpkg", delete_dsn = TRUE)
}

# ==============================================================================
# TILE CATALOG FUNCTIONS
# ==============================================================================

#' Create a tile catalog data frame
#' 
#' @param tiles_sf sf object with tiles
#' @return data.frame with tile metadata
create_tile_catalog <- function(tiles_sf) {
  
  catalog <- st_drop_geometry(tiles_sf)
  
  # Add additional metadata
  catalog$tile_size_m <- GRID_SPEC[[tiles_sf$level[1]]]$tile_size
  catalog$resolution_m <- GRID_SPEC[[tiles_sf$level[1]]]$resolution
  catalog$pixels <- GRID_SPEC[[tiles_sf$level[1]]]$pixels
  
  # Add bbox coordinates for quick reference
  bboxes <- do.call(rbind, lapply(1:nrow(tiles_sf), function(i) {
    bb <- st_bbox(tiles_sf[i, ])
    data.frame(xmin = bb["xmin"], ymin = bb["ymin"],
               xmax = bb["xmax"], ymax = bb["ymax"])
  }))
  
  catalog <- cbind(catalog, bboxes)
  
  return(catalog)
}

#' Export tile catalog to CSV
#' 
#' @param tiles_sf sf object with tiles
#' @param filename Output CSV filename
export_tile_catalog <- function(tiles_sf, filename) {
  catalog <- create_tile_catalog(tiles_sf)
  write.csv(catalog, filename, row.names = FALSE)
  message("Tile catalog exported to: ", filename)
}
