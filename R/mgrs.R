# Sentinel-2 MGRS scene geometry: the bridge between aatgrid tiles and
# the MGRS acquisition vocabulary (starc's acquisition `tile` field).
#
# The extent convention was reverse-engineered from archive residuals
# and VERIFIED EXACT (0 m on all four edges) against 132 distinct MGRS
# codes across 55 UTM zones and both hemispheres, using real
# proj metadata from the starc raw stash (Sep 2026):
#   - geographiclib's MGRS reverse at this precision returns the CENTER
#     of the 100 km square
#   - the scene UL-x is the square's W edge snapped WEST to the global
#     60 m easting lattice (ulx %% 60 == 0)
#   - the scene UL-y is the square's N edge snapped NORTH to the global
#     60 m northing lattice ANCHORED AT THE EQUATOR: congruent to 0
#     (mod 60) in northern zones, and to 40 (mod 60) in southern zones
#     because the 10,000,000 m false northing is not a multiple of 60
#     (1e7 %% 60 == 40)
#   - the scene extends 109800 m east and south (100 km square + all
#     margin on the right/bottom, none left/top)
#
# Consequence for aatgrid alignment: S2 10 m and 20 m band lattices
# coincide exactly with aatgrid's (origin 140000/20000); the 60 m bands
# sit at a CONSTANT (20, 20) m sub-pixel shift in southern zones,
# absorbed by the warp.
#
# Suggests: geographiclib

#' Scene extent for a Sentinel-2 MGRS code, in its own zone CRS
#'
#' @param mgrs 5-character code, e.g. "43DDE"
#' @return list(extent = c(xmin, xmax, ymin, ymax), zone_number,
#'   hemisphere, epsg)
#' @export
mgrs_extent <- function(mgrs) {
  if (!requireNamespace("geographiclib", quietly = TRUE)) {
    stop("mgrs_extent() requires the 'geographiclib' package; ",
         "install.packages('geographiclib')")
  }
  ## NOTE: adapt this one call to the geographiclib API in use --
  ## required: UTM x, y of the 100 km square CENTER, zone number,
  ## and hemisphere for the code.
  cen <- geographiclib::mgrs_rev(mgrs)
  north <- isTRUE(cen$northp)

  ulx <- floor((cen$x - 50000) / 60) * 60
  y0 <- cen$y + 50000
  off <- if (north) 0 else 40      # 1e7 %% 60
  uly <- y0 + ((off - y0) %% 60)

  list(
    extent = c(ulx, ulx + 109800, uly - 109800, uly),
    zone_number = cen$zone,
    hemisphere = if (north) "N" else "S",
    epsg = sprintf("EPSG:%s%02d", if (north) "326" else "327", cen$zone)
  )
}

#' Candidate MGRS codes near a zone, prefiltered from the code string
#' @keywords internal
mgrs_candidates <- function(zone_number, lat_bands, valid) {
  zn <- as.integer(sub("^([0-9]{1,2}).*", "\\1", valid))
  band <- sub("^[0-9]{1,2}([A-Z]).*", "\\1", valid)
  near <- abs(zn - zone_number) <= 1 | abs(zn - zone_number) == 59
  valid[near & band %in% lat_bands]
}

#' Map aatgrid tiles to intersecting Sentinel-2 MGRS scenes
#'
#' Same-zone pairs intersect by interval arithmetic; cross-zone pairs
#' reproject the scene extent into the tile zone via densified
#' project_extent() (MGRS squares are subject to the corner trap under
#' reprojection exactly as any extent is).
#'
#' @param tiles data.frame from tiles_for_extent2() (tile_id, col, row,
#'   res; single zone)
#' @param valid Character vector of valid S2 MGRS codes (see starc's
#'   inst/extdata/valid_mgrs_sentinel2.parquet)
#' @param lat_bands Latitude band letters to consider (e.g. c("C","D"))
#' @return long data.frame: tile_id, mgrs, same_zone
#' @export
tiles_to_mgrs <- function(tiles, valid, lat_bands) {
  zp <- parse_tile_id(tiles$tile_id[1])
  tile_epsg <- sprintf("EPSG:%s%02d",
                       if (zp$hemisphere == "N") "326" else "327",
                       zp$zone_number)
  cands <- mgrs_candidates(zp$zone_number, lat_bands, valid)
  tex <- tile_index_to_extent(tiles$col, tiles$row, tiles$res[1])

  out <- vector("list", length(cands))
  for (k in seq_along(cands)) {
    me <- mgrs_extent(cands[k])
    same_zone <- me$zone_number == zp$zone_number &&
      me$hemisphere == zp$hemisphere
    ex <- if (same_zone) me$extent else {
      project_extent(utm_extent_to_lonlat(me$extent, me$epsg), tile_epsg)
    }
    hit <- tex$xmin < ex[2] & tex$xmax > ex[1] &
           tex$ymin < ex[4] & tex$ymax > ex[3]
    if (any(hit)) {
      out[[k]] <- data.frame(tile_id = tiles$tile_id[hit],
                             mgrs = cands[k], same_zone = same_zone,
                             stringsAsFactors = FALSE)
    }
  }
  do.call(rbind, out)
}

#' Lonlat bbox of a UTM extent, densified (cross-zone helper)
#' @keywords internal
utm_extent_to_lonlat <- function(extent, epsg, n = 21) {
  if (!requireNamespace("PROJ", quietly = TRUE)) {
    stop("cross-zone tiles_to_mgrs() requires the 'PROJ' package; ",
         "remotes::install_github('hypertidy/PROJ')")
  }
  b <- extent_boundary(extent, n)
  xy <- as.matrix(PROJ::proj_trans(b, "EPSG:4326", source_crs = epsg))
  c(min(xy[, 1]), max(xy[, 1]), min(xy[, 2]), max(xy[, 2]))
}
