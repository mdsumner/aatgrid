# Raster-based Tile Identification System
# Fast tile identification using raster specifications
# Built with terra package



# ==============================================================================
# ZONE RASTER SPECIFICATIONS
# ==============================================================================

#' Create raster specification for a UTM zone at a given resolution
#'
#' Each cell in the raster represents one tile in the grid.
#' This provides a fast spatial index for tile identification.
#'
#' @param zone_id Zone identifier (e.g., "43S")
#' @param res Numeric resolution in metres, or a legacy level name ("L1", "L2")
#' @param zones UTM zone definitions
#' @param zone_extent Optional: limit extent (xmin, xmax, ymin, ymax) in UTM coords
#' @return SpatRaster where each cell = one tile
#' @export
#' @importFrom terra rast res<-
create_zone_raster <- function(zone_id, res, zones, zone_extent = NULL) {
  zone_info <- zones[zones$zone_id == zone_id, ]

  ts <- tile_size(res)

  # Define extent for the zone if not specified. The lattice starts at
  # the origin (no negative tile indices), and a UTM zone's eastings
  # never fall below ~166 km, so the west edge is the origin itself.
  # Northings: ~1.0e6 to ~4.2e6 m covers roughly 81S to 52S.
  if (is.null(zone_extent)) {
    zone_extent <- c(
      zone_info$origin_x,             # xmin: the lattice origin
      zone_info$origin_x + 700000,    # xmax: beyond any zone's east edge
      zone_info$origin_y + 1000000,   # ymin: deep Antarctic
      zone_info$origin_y + 4200000    # ymax: subantarctic islands
    )
  }
  if (length(zone_extent) != 4L) {
    stop("zone_extent must be c(xmin, xmax, ymin, ymax)")
  }

  # Align extent to tile boundaries
  # Snap to tile grid using origin
  xmin_snap <- zone_info$origin_x +
    floor((zone_extent[1] - zone_info$origin_x) / ts) * ts
  xmax_snap <- zone_info$origin_x +
    ceiling((zone_extent[2] - zone_info$origin_x) / ts) * ts
  ymin_snap <- zone_info$origin_y +
    floor((zone_extent[3] - zone_info$origin_y) / ts) * ts
  ymax_snap <- zone_info$origin_y +
    ceiling((zone_extent[4] - zone_info$origin_y) / ts) * ts

  if (xmin_snap < zone_info$origin_x || ymin_snap < zone_info$origin_y) {
    stop("zone_extent lies below the grid origin (negative tile index); ",
         "the lattice starts at GRID_ORIGIN")
  }

  # Create extent (terra ordering: xmin, xmax, ymin, ymax)
  zone_ext <- ext(xmin_snap, xmax_snap, ymin_snap, ymax_snap)

  # Calculate dimensions (each cell = one tile)
  ncols <- round((xmax_snap - xmin_snap) / ts)
  nrows <- round((ymax_snap - ymin_snap) / ts)

  # Create raster: a pure specification (extent + dimension + crs), no
  # values allocated -- rasterize() against it needs none
  r <- terra::rast(zone_ext, nrows = nrows, ncols = ncols, crs = zone_info$epsg)

  names(r) <- paste0(zone_id, "_R", sprintf("%04d", resolve_res(res)), "_grid")

  return(r)
}

#' Create raster specifications for all zones at a resolution
#'
#' @param res Numeric resolution in metres, or a legacy level name ("L1", "L2")
#' @param zones UTM zone definitions
#' @param zone_ids Optional: vector of zone IDs (default: all AAT zones)
#' @return Named list of SpatRaster objects
#' @export
create_all_zone_rasters <- function(res, zones, zone_ids = NULL) {
  if (is.null(zone_ids)) {
    zone_ids <- zones$zone_id
  }

  raster_list <- lapply(zone_ids, function(zid) {
    create_zone_raster(zid, res, zones)
  })

  names(raster_list) <- zone_ids

  return(raster_list)
}

# ==============================================================================
# FAST TILE IDENTIFICATION
# ==============================================================================

#' Rasterize features to identify intersecting tiles
#'
#' Features in a geographic (lonlat) CRS are densified before projection
#' (lines and polygons only): a straight lonlat edge becomes a curve in
#' UTM, and projecting only its vertices replaces that curve with a
#' chord that can fall short of a tile seam. This is the polygon form of
#' the corner trap handled by [project_extent()] for extents.
#'
#' @param features SpatVector of features to rasterize
#' @param zone_raster SpatRaster template for the zone (each cell = one tile)
#' @param buffer_m Optional buffer distance in meters
#' @param densify_m Vertex spacing in metres (terra::densify's unit for
#'   lonlat input) used to densify lonlat lines/polygons before
#'   projecting; NULL disables. 1 km bounds the chord error to well
#'   under a 10 m tile's size at these latitudes
#' @return SpatRaster with 1 where tiles intersect features, 0 elsewhere
#' @export
#' @importFrom terra is.lonlat densify geomtype
identify_intersecting_tiles <- function(features, zone_raster, buffer_m = 0,
                                        densify_m = 1000) {
  # Project features to raster CRS if needed
  if (!is.null(crs(features)) && crs(features) != crs(zone_raster)) {
    if (!is.null(densify_m) && isTRUE(terra::is.lonlat(features)) &&
        terra::geomtype(features) %in% c("lines", "polygons")) {
      features <- terra::densify(features, interval = densify_m)
    }
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
#' A zone raster (see [create_zone_raster()]) is a window onto the tile
#' lattice: its cells are tiles, but its first column need not be tile
#' column 0, and terra numbers rows from the top (north) down while tile
#' rows count up from the origin (south). So raster row/col numbers are
#' never tile indices; the tile index is recovered from each cell's
#' centre coordinate against [GRID_ORIGIN], which is exact because the
#' raster is tile-aligned.
#'
#' @param zone_raster SpatRaster with tiles as cells
#' @param cell_indices Vector of cell indices (1-based, terra order)
#' @return data.frame with cell, col, row (0-based tile indices)
#' @export
#' @importFrom terra xyFromCell
cells_to_tile_indices <- function(zone_raster, cell_indices) {
  ts <- terra::res(zone_raster)[1]
  xy <- terra::xyFromCell(zone_raster, cell_indices)
  data.frame(
    cell = cell_indices,
    col = as.integer(floor((xy[, 1] - GRID_ORIGIN[["x"]]) / ts)),
    row = as.integer(floor((xy[, 2] - GRID_ORIGIN[["y"]]) / ts))
  )
}

#' Fast workflow: features to tile list
#'
#' @param features SpatVector of features (polygons, lines, points)
#' @param zone_id Zone identifier
#' @param res Numeric resolution in metres, or a legacy level name ("L1", "L2")
#' @param zones UTM zone definitions
#' @param zone_raster Optional: pre-created zone raster (for efficiency)
#' @param buffer_m Optional buffer in meters
#' @return data.frame with tile_id, zone_id, res, col, row
#' @export
fast_identify_tiles <- function(features, zone_id, res, zones,
                                zone_raster = NULL, buffer_m = 0) {
  res <- resolve_res(res)

  # Create zone raster if not provided
  if (is.null(zone_raster)) {
    zone_raster <- create_zone_raster(zone_id, res, zones)
  } else if (!isTRUE(all.equal(terra::res(zone_raster)[1], tile_size(res)))) {
    stop("zone_raster cell size (", terra::res(zone_raster)[1],
         ") does not match tile_size(res) = ", tile_size(res))
  }

  # Identify intersecting cells
  intersect_rast <- identify_intersecting_tiles(features, zone_raster, buffer_m)

  # Get cell indices where value == 1
  cell_idx <- which(values(intersect_rast) == 1)

  if (length(cell_idx) == 0) {
    return(empty_tile_df())
  }

  # Convert to tile indices
  tile_indices <- cells_to_tile_indices(zone_raster, cell_idx)

  # Create tile IDs
  tile_ids <- make_tile_id(zone_id, res, tile_indices$col, tile_indices$row)

  # Return as data frame
  result <- data.frame(
    tile_id = tile_ids,
    zone_id = zone_id,
    res = res,
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
#' @param res Numeric resolution in metres, or a legacy level name ("L1", "L2")
#' @param zones UTM zone definitions
#' @param buffer_m Optional buffer in meters
#' @return data.frame with all intersecting tiles across zones
#' @export
fast_identify_tiles_multizone <- function(features, zone_ids, res, zones,
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
    return(empty_tile_df())
  }

  # Process each zone
  tiles_list <- lapply(relevant_zone_ids, function(zid) {
    fast_identify_tiles(features, zid, res, zones, buffer_m = buffer_m)
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
      tile_df$res[i],
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
#' Vectorised over the rows of `tile_df`; the extents depend only on
#' (col, row, res) since the origin is shared by every zone, so `zones`
#' is accepted for interface symmetry but not consulted.
#'
#' @param tile_df data.frame from fast_identify_tiles (tile_id, res, col, row)
#' @param zones UTM zone definitions (unused; kept for a stable signature)
#' @return data.frame with tile_id and extent columns (xmin, xmax, ymin, ymax)
#' @export
get_tile_extents_from_df <- function(tile_df, zones = NULL) {
  if (nrow(tile_df) == 0) {
    return(data.frame(tile_id = character(0), xmin = numeric(0),
                      xmax = numeric(0), ymin = numeric(0),
                      ymax = numeric(0), stringsAsFactors = FALSE))
  }
  res <- resolve_res(tile_df$res)
  if (length(unique(res)) != 1L) {
    stop("tile_df mixes resolutions; split by res first")
  }
  tile_ext <- tile_index_to_extent(tile_df$col, tile_df$row, res[1])
  data.frame(
    tile_id = tile_df$tile_id,
    xmin = tile_ext$xmin,
    xmax = tile_ext$xmax,
    ymin = tile_ext$ymin,
    ymax = tile_ext$ymax,
    stringsAsFactors = FALSE
  )
}

#' Empty tile data.frame with the canonical columns
#' @keywords internal
empty_tile_df <- function() {
  data.frame(
    tile_id = character(0),
    zone_id = character(0),
    res = numeric(0),
    col = integer(0),
    row = integer(0),
    stringsAsFactors = FALSE
  )
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
  #   res = "L2",
  #   zones = zones
  # )
}
