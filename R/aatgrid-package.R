#' aatgrid: Antarctic Territory Grid System
#'
#' A hierarchical geospatial tiling system for the Australian Antarctic
#' Territory (AAT). Provides standardized grid frameworks at multiple
#' resolutions (36km and 6km tiles) aligned with Sentinel-2 grid origins.
#'
#' @description
#' The aatgrid package provides tools for working with a standardized grid
#' system covering the Australian Antarctic Territory. The system uses:
#' \itemize{
#'   \item Two resolution levels (L1: 36km tiles, L2: 6km tiles)
#'   \item UTM projections (zones 42S-58S)
#'   \item Sentinel-2 grid alignment
#'   \item Fast raster-based tile identification
#' }
#'
#' @section Main functions:
#' \itemize{
#'   \item \code{\link{define_utm_zones}}: Define UTM zone specifications
#'   \item \code{\link{create_zone_raster}}: Create raster-based spatial index
#'   \item \code{\link{fast_identify_tiles}}: Fast tile identification
#'   \item \code{\link{create_tile_template}}: Generate tile raster templates
#' }
#'
#' @docType package
#' @name aatgrid-package
#' @aliases aatgrid
#' @keywords internal
"_PACKAGE"

## usethis namespace: start
#' @importFrom terra vect ext project crs values rast res buffer rasterize
#' @importFrom terra relate rowColFromCell writeVector
## usethis namespace: end
NULL
