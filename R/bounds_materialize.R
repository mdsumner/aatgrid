# Extent alignment, densified bounds, and wk materialization.
#
# Supersedes generate_tiles_for_extent() and the create_tile_polygon()
# terra path. Depends on PROJ and wk only.
#
# Extent ordering throughout is c(xmin, xmax, ymin, ymax).

# ==============================================================================
# EXTENT -> INDEX ALIGNMENT
# ==============================================================================

#' Align an extent to the tile lattice, in index space
#'
#' The only alignment door: converts an extent to the inclusive range of
#' tile indices it touches, and returns the implied tile-aligned extent.
#' Never snap extents with generic tools (the lattice origin is
#' GRID_ORIGIN, not zero: 140000 mod 36000 = 32000).
#'
#' Tiles are right-open ([min, max)): an extent edge lying exactly on a
#' seam does not drag in the empty neighbouring row/column. `tol`
#' (metres) absorbs reprojection fuzz so a coordinate meant to lie on a
#' seam (e.g. 391999.9999997) resolves to the seam; it applies here
#' only, never in utm_to_tile_index(), so point queries stay exact.
#'
#' @param extent c(xmin, xmax, ymin, ymax) in grid UTM metres
#' @param res Numeric resolution in metres, or a legacy level name
#' @param tol Seam tolerance in metres (default 1e-3, i.e. 1 mm)
#' @return list with col = c(min, max), row = c(min, max), and
#'   extent = the tile-aligned c(xmin, xmax, ymin, ymax)
#' @export
tile_range <- function(extent, res, tol = 1e-3) {
  ts <- tile_size(res)
  ox <- GRID_ORIGIN[["x"]]
  oy <- GRID_ORIGIN[["y"]]

  cmin <- floor((extent[1] - ox + tol) / ts)
  cmax <- ceiling((extent[2] - ox - tol) / ts) - 1
  rmin <- floor((extent[3] - oy + tol) / ts)
  rmax <- ceiling((extent[4] - oy - tol) / ts) - 1

  ## a degenerate (point or seam-width) extent still occupies one tile
  cmax <- max(cmax, cmin)
  rmax <- max(rmax, rmin)

  if (cmin < 0 || rmin < 0) {
    stop("extent lies outside the grid domain (negative tile index); ",
         "check the zone, or the coordinates are not in grid UTM")
  }

  list(
    col = c(cmin, cmax),
    row = c(rmin, rmax),
    extent = c(ox + cmin * ts, ox + (cmax + 1) * ts,
               oy + rmin * ts, oy + (rmax + 1) * ts)
  )
}

# ==============================================================================
# DENSIFIED BOUNDS (the anti-corner-trap)
# ==============================================================================

#' Densified boundary points of a lonlat extent
#'
#' @param extent_lonlat c(xmin, xmax, ymin, ymax), degrees
#' @param n Points per edge (default 21, matching proj_trans_bounds)
#' @return two-column matrix of lon, lat boundary vertices
#' @keywords internal
extent_boundary <- function(extent_lonlat, n = 21) {
  xs <- seq(extent_lonlat[1], extent_lonlat[2], length.out = n)
  ys <- seq(extent_lonlat[3], extent_lonlat[4], length.out = n)
  rbind(
    cbind(xs, extent_lonlat[3]),        # south edge
    cbind(extent_lonlat[2], ys),        # east edge
    cbind(rev(xs), extent_lonlat[4]),   # north edge
    cbind(extent_lonlat[1], rev(ys))    # west edge
  )
}

#' Project an extent by transforming its densified boundary
#'
#' Corner-only transformation of an extent is wrong under curvature: the
#' true extreme of an edge can exceed every corner (a parallel's max
#' northing occurs at the central meridian when the CM lies inside the
#' lon range; the Heard islet miss was the western-corner variant of the
#' same trap). Transforming n points per edge bounds the true extent to
#' well under tile scale.
#'
#' @param extent_lonlat c(xmin, xmax, ymin, ymax), degrees
#' @param target_crs Target CRS (anything PROJ accepts)
#' @param source_crs Source CRS (default EPSG:4326)
#' @param n Points per edge
#' @return c(xmin, xmax, ymin, ymax) in target CRS
#' @export
project_extent <- function(extent_lonlat, target_crs,
                           source_crs = "EPSG:4326", n = 64) {
reproj::reproj_extent(extent_lonlat, target_crs, source = source_crs, dimension = rep(n, length.out = 2L))
}

# ==============================================================================
# MATERIALIZATION (wk rct, vectorized; no per-tile object loop)
# ==============================================================================

#' Tiles covering a lonlat extent, as a data.frame with wk geometry
#'
#' Zone policy: one zone per call. By default the zone containing the
#' extent's centroid longitude is used; regions straddling a zone
#' boundary are a registry decision, not an arithmetic one -- pass
#' `zone` explicitly to override, and call twice for a deliberate
#' two-zone scheme (ids are zone-qualified, so they cannot collide).
#'
#' @param extent_lonlat c(xmin, xmax, ymin, ymax), degrees
#' @param res Numeric resolution in metres, or a legacy level name
#' @param zone Zone id (e.g. "43S"); default: centroid zone
#' @param zones Zone table (see define_utm_zones())
#' @param pad Integer collar of extra tile rings (default 0). Padding is
#'   tile-denominated on purpose: "one ring of context ocean" is a
#'   statement about the grid; a padded lonlat bbox is not.
#' @param n Boundary densification, points per edge
#' @return data.frame: tile_id, zone_id, res, col, row, geometry
#'   (wk::rct with the zone CRS attached)
#' @export
tiles_for_extent2 <- function(extent_lonlat, res, zone = NULL,
                              zones = define_utm_zones(), pad = 0, n = 21) {
  res <- resolve_res(res)

  if (is.null(zone)) {
    zone_number <- floor((mean(extent_lonlat[1:2]) + 180) / 6) + 1
    zone <- paste0(zone_number, "S")
  }
  zi <- zones[zones$zone_id == zone, ]
  if (nrow(zi) != 1) {
    stop("zone not in table: ", zone, " (extend define_utm_zones()?)")
  }

  ext_utm <- project_extent(extent_lonlat, zi$epsg, n = n)
  tr <- tile_range(ext_utm, res)

  cols <- (tr$col[1] - pad):(tr$col[2] + pad)
  rows <- (tr$row[1] - pad):(tr$row[2] + pad)
  if (min(cols) < 0 || min(rows) < 0) {
    stop("pad pushes the block outside the grid domain")
  }

  g <- expand.grid(col = cols, row = rows)
  ex <- tile_index_to_extent(g$col, g$row, res)

  out <- data.frame(
    tile_id = make_tile_id(zone, res, g$col, g$row),
    zone_id = zone,
    res = res,
    col = g$col,
    row = g$row,
    stringsAsFactors = FALSE
  )
  out$geometry <- wk::rct(ex$xmin, ex$ymin, ex$xmax, ex$ymax, crs = zi$epsg)
  out
}

#' GDAL geotransform for tiles
#'
#' `(extent, PIXELS_PER_TILE^2, zone crs)` is a complete warp target;
#' this is the entire aatgrid -> renderer interface.
#'
#' @param col,row Tile indices (vectorized)
#' @param res Numeric resolution in metres, or a legacy level name
#' @return matrix, one row per tile: c(xmin, xres, 0, ymax, 0, -yres)
#' @export
tile_gt <- function(col, row, res) {
  res <- resolve_res(res)
  ex <- tile_index_to_extent(col, row, res)
  cbind(xmin = ex$xmin, xres = res, xskew = 0,
        ymax = ex$ymax, yskew = 0, yres = -res)
}

# ==============================================================================
# FUTURE: reproj methods for wk vectors (sketch, not yet registered)
# ==============================================================================
# A general helper belongs in reproj (or wk), not here, but the shape is:
#
# reproj.wk_wkb <- function(x, target, ..., source = NULL) {
#   src <- if (is.null(source)) wk::wk_crs(x) else source
#   wk::wk_transform(x, PROJ::proj_trans_create(src, target))
# }
#
# CAUTION for rct specifically: wk_transform of an rct yields the bbox of
# its transformed corners -- the corner-only trap in vctr form. An rct
# must be densified to a polygon before transforming (then wk_bbox if a
# rect is wanted). project_extent() above is the extent-shaped version of
# exactly that rule; do not add an rct shortcut that skips it.
