# Antarctic Territory Grid System
# Based on UTM zones with Sentinel-2 grid alignment
# Coverage: Australian Antarctic Territory (44°E to 160°E, terrestrial focus)
# Built with terra package

#' @importFrom terra vect ext project crs values rast res crds
NULL

# Global grid specification - internal to package
.onLoad <- function(libname, pkgname) {
  # Grid specifications are loaded into package environment
  invisible()
}

# ==============================================================================
# RESOLUTION HELPERS
# ==============================================================================

#' Resolve a resolution argument, accepting legacy level names
#'
#' @param res Numeric resolution in metres, or one of the legacy level
#'   names in [LEVEL_RESOLUTIONS] (currently "L1", "L2")
#' @return Numeric resolution in metres
#' @keywords internal
resolve_res <- function(res) {
  if (is.character(res)) {
    unknown <- setdiff(res, names(LEVEL_RESOLUTIONS))
    if (length(unknown) > 0) {
      stop("unknown resolution/level: ", paste(unknown, collapse = ", "))
    }
    res <- unname(LEVEL_RESOLUTIONS[res])
  }
  res
}

#' Tile size (metres) for a given resolution
#'
#' The generative invariant of the grid: every tile is
#' `PIXELS_PER_TILE` pixels square, so tile size is derived from
#' resolution rather than chosen independently.
#'
#' @param res Numeric resolution in metres, or a legacy level name
#'   ("L1", "L2")
#' @return Numeric tile size in metres
#' @export
tile_size <- function(res) {
  PIXELS_PER_TILE * resolve_res(res)
}

#' Check that arguments have mutually recyclable lengths
#'
#' Scalars (length 1) recycle freely; two or more non-scalar arguments
#' must share the same length, otherwise silent, wrong recycling would
#' occur (this was a real bug: `make_tile_id("43S", "L1", 5:7, 113:114)`
#' silently dropped a tile).
#'
#' @param ... Vectors to check
#' @keywords internal
check_recyclable_lengths <- function(...) {
  lens <- vapply(list(...), length, integer(1))
  nontrivial <- unique(lens[lens != 1])
  if (length(nontrivial) > 1) {
    stop("arguments imply differing, non-recyclable lengths: ",
         paste(lens, collapse = ", "))
  }
  invisible(TRUE)
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
  # Zones covering all longitude range
  ## not just AAT which is (44E to 160E)
  zone_numbers <- 1:60

  zones <- data.frame(
    zone_number = zone_numbers,
    hemisphere = "S",
    epsg = paste0("EPSG:327", sprintf("%02d",  zone_numbers)),
    # Sentinel-2 grid origin (standard for UTM southern hemisphere);
    # identical across every zone (see GRID_ORIGIN)
    origin_x = GRID_ORIGIN[["x"]],
    origin_y = GRID_ORIGIN[["y"]],
    # Central meridian for each zone
    central_meridian = -183 + (zone_numbers * 6),
    stringsAsFactors = FALSE
  )

  # Add zone ID (e.g., "42S", "43S", ...)
  zones$zone_id <- paste0(sprintf("%02d", zones$zone_number),
                          zones$hemisphere)

  return(zones)
}

# ==============================================================================
# TILE INDEXING FUNCTIONS
# ==============================================================================

#' Convert UTM coordinates to tile indices
#'
#' @param x UTM easting coordinate(s)
#' @param y UTM northing coordinate(s)
#' @param res Numeric resolution in metres, or a legacy level name
#'   ("L1", "L2"); the grid origin is shared by every UTM zone (see
#'   [GRID_ORIGIN])
#' @return data.frame with col and row indices
#' @export
utm_to_tile_index <- function(x, y, res) {
  ts <- tile_size(res)
  data.frame(
    col = floor((x - GRID_ORIGIN[["x"]]) / ts),
    row = floor((y - GRID_ORIGIN[["y"]]) / ts)
  )
}

#' Convert tile indices to UTM extent
#'
#' @param col Tile column index
#' @param row Tile row index
#' @param res Numeric resolution in metres, or a legacy level name
#'   ("L1", "L2")
#' @return data.frame with xmin, xmax, ymin, ymax (UTM metres)
#' @export
tile_index_to_extent <- function(col, row, res) {
  ts <- tile_size(res)
  xmin <- GRID_ORIGIN[["x"]] + (col * ts)
  ymin <- GRID_ORIGIN[["y"]] + (row * ts)

  data.frame(xmin = xmin, xmax = xmin + ts, ymin = ymin, ymax = ymin + ts)
}

#' Generate tile ID string
#'
#' Encodes resolution rather than a level name, so it is parseable
#' without a registry: `"55S_R0060_0123_0456"` is a 60 m tile.
#'
#' @param zone_id Zone identifier (e.g., "55S")
#' @param res Numeric resolution in metres, or a legacy level name
#'   ("L1", "L2")
#' @param col Tile column index
#' @param row Tile row index
#' @return character tile ID (e.g., "55S_R0060_0123_0456")
#' @export
make_tile_id <- function(zone_id, res, col, row) {
  check_recyclable_lengths(zone_id, col, row)
  res <- resolve_res(res)
  for (i in seq_along(zone_id)) {
    if (nchar(zone_id[i]) == 2) {
      nc <- paste0("0", zone_id[i])
      zone_id[i] <- nc
    }
  }
  paste0(zone_id, "_R", sprintf("%04d", res), "_",
         sprintf("%04d", col), "_",
         sprintf("%04d", row))
}

#' Parse tile ID string
#'
#' Accepts both the current resolution-encoded form
#' (`"55S_R0060_0123_0456"`) and legacy level-named ids
#' (`"55S_L1_0123_0456"`), so nothing already written becomes an
#' orphan; legacy names are mapped to their resolution via
#' [LEVEL_RESOLUTIONS].
#'
#' @param tile_id Tile identifier string
#' @return list with zone_id, res (numeric, metres), col, row
#' @export
parse_tile_id <- function(tile_id) {
  parts <- strsplit(tile_id, "_")[[1]]
  tag <- parts[2]
  res <- if (grepl("^R[0-9]+$", tag)) {
    as.integer(sub("^R", "", tag))
  } else if (tag %in% names(LEVEL_RESOLUTIONS)) {
    unname(LEVEL_RESOLUTIONS[[tag]])
  } else {
    stop("unrecognized tile id resolution/level tag: ", tag)
  }
  if (nchar(parts[1]) == 2) {
    parts[1] <- paste0("0", parts[1])
  }
  list(
    zone_id = parts[1],
    res = res,
    col = as.integer(parts[3]),
    row = as.integer(parts[4]),
    zone_number = as.integer(gsub("[[:alpha:]]", "", parts[1])),
    hemisphere = gsub("[[:digit:]]", "", parts[1])
  )
}

#' Get parent tile at a coarser resolution
#'
#' @param col,row Tile column/row index at `res_child`
#' @param res_child,res_parent Numeric resolution in metres (or legacy
#'   level name); `res_parent / res_child` must be a positive integer
#' @return data.frame with parent col and row
#' @export
get_parent_tile <- function(col, row, res_child = 10, res_parent = 60) {
  f <- nesting_factor(res_parent, res_child)
  data.frame(
    col = floor(col / f),
    row = floor(row / f)
  )
}

#' Get child tiles at a finer resolution
#'
#' @param col,row Tile column/row index at `res_parent`
#' @param res_parent,res_child Numeric resolution in metres (or legacy
#'   level name); `res_parent / res_child` must be a positive integer
#' @return data.frame with all child col and row indices
#' @export
get_child_tiles <- function(col, row, res_parent = 60, res_child = 10) {
  f <- nesting_factor(res_parent, res_child)
  expand.grid(
    col = col * f + 0:(f - 1),
    row = row * f + 0:(f - 1)
  )
}

#' Nesting factor between two resolutions
#'
#' Nesting is exact whenever `res_parent / res_child` is a positive
#' integer; this is enforced here rather than assumed by convention.
#'
#' @param res_parent,res_child Numeric resolution in metres, or a
#'   legacy level name ("L1", "L2")
#' @return Integer nesting factor
#' @keywords internal
nesting_factor <- function(res_parent, res_child) {
  f <- resolve_res(res_parent) / resolve_res(res_child)
  if (f <= 0 || f != round(f)) {
    stop("res_parent / res_child must be a positive integer (got ", f, ")")
  }
  as.integer(round(f))
}



# ==============================================================================
# SPATIAL FUNCTIONS (TERRA-BASED)
# ==============================================================================

#' Create SpatVector polygon for a tile
#'
#' @param zone_id Zone identifier
#' @param res Numeric resolution in metres, or a legacy level name
#'   ("L1", "L2")
#' @param col Tile column
#' @param row Tile row
#' @param zones UTM zone definitions
#' @return SpatVector object with tile polygon
#' @export
create_tile_polygon <- function(zone_id, res, col, row, zones) {
  zone_info <- zones[zones$zone_id == zone_id, ]

  tile_ext <- tile_index_to_extent(col, row, res)

  # Create polygon from extent using terra ordering
  coords <- matrix(c(
    tile_ext$xmin, tile_ext$ymin,
    tile_ext$xmax, tile_ext$ymin,
    tile_ext$xmax, tile_ext$ymax,
    tile_ext$xmin, tile_ext$ymax,
    tile_ext$xmin, tile_ext$ymin   # close
  ), ncol = 2, byrow = TRUE)

  # Create SpatVector polygon
  tile_vect <- vect(coords, type = "polygons", crs = zone_info$epsg)

  # Add attributes
  tile_id <- make_tile_id(zone_id, res, col, row)
  terra::values(tile_vect) <- data.frame(
    tile_id = tile_id,
    zone_id = zone_id,
    res = resolve_res(res),
    col = col,
    row = row
  )

  return(tile_vect)
}

#' Create SpatExtent for a tile
#'
#' @param zone_id Zone identifier
#' @param res Numeric resolution in metres, or a legacy level name
#'   ("L1", "L2")
#' @param col Tile column
#' @param row Tile row
#' @param zones UTM zone definitions
#' @return SpatExtent object
#' @export
create_tile_extent <- function(zone_id, res, col, row, zones) {
  zone_info <- zones[zones$zone_id == zone_id, ]

  tile_ext <- tile_index_to_extent(col, row, res)

  # terra ext() takes xmin, xmax, ymin, ymax
  ext(tile_ext$xmin, tile_ext$xmax, tile_ext$ymin, tile_ext$ymax)
}

#' Create template SpatRaster for a tile
#'
#' @param zone_id Zone identifier
#' @param res Numeric resolution in metres, or a legacy level name
#'   ("L1", "L2")
#' @param col Tile column
#' @param row Tile row
#' @param zones UTM zone definitions
#' @return SpatRaster template (empty raster with correct extent/resolution)
#' @export
create_tile_template <- function(zone_id, res, col, row, zones) {
  zone_info <- zones[zones$zone_id == zone_id, ]

  # Get tile extent
  tile_ext <- create_tile_extent(zone_id, res, col, row, zones)

  # Create raster template
  npixels <- PIXELS_PER_TILE
  resolution <- resolve_res(res)

  r <- rast(tile_ext, nrows = npixels, ncols = npixels, crs = zone_info$epsg)

  # Add metadata
  names(r) <- make_tile_id(zone_id, res, col, row)

  return(r)
}

# ==============================================================================
# COORDINATE CONVERSION
# ==============================================================================

#' Convert lon/lat coordinates to UTM in a given zone
#'
#' @param lon,lat Numeric vectors, WGS84 degrees
#' @param zone Zone identifier, e.g. "43S" (see [define_utm_zones()])
#' @return data.frame with x, y (UTM metres)
#' @export
lonlat_to_utm <- function(lon, lat, zone) {
  zones <- define_utm_zones()
  zone_info <- zones[zones$zone_id == zone, ]
  if (nrow(zone_info) != 1) {
    stop("unknown zone: ", zone)
  }

  pts <- vect(cbind(lon, lat), crs = "EPSG:4326")
  pts_utm <- project(pts, zone_info$epsg)
  xy <- crds(pts_utm)

  data.frame(x = xy[, 1], y = xy[, 2])
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


save_grid_spec <- function(filename = "antarctic_grid_spec.rds") {
  zones <- define_utm_zones()

  spec <- list(
    origin = GRID_ORIGIN,
    pixels_per_tile = PIXELS_PER_TILE,
    level_resolutions = LEVEL_RESOLUTIONS,
    utm_zones = zones,
    created = Sys.time(),
    description = "Australian Antarctic Territory grid system aligned to Sentinel-2"
  )

  saveRDS(spec, filename)
  message("Grid specification saved to: ", filename)
  return(spec)
}


load_grid_spec <- function(filename = "antarctic_grid_spec.rds") {
  if (!file.exists(filename)) {
    stop("Grid specification file not found: ", filename)
  }
  readRDS(filename)
}
