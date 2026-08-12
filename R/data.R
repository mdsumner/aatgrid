# Package data and constants

#' Grid specification constants
#'
#' The AAT grid is fully specified by three numbers: an origin, a fixed
#' pixel count per tile, and a resolution. Tile size is *derived* from
#' these (`tile_size(res) = PIXELS_PER_TILE * res`) rather than chosen
#' independently, so the 600x600-pixel Sentinel-2-aligned tile is the
#' generative invariant of the whole scheme.
#'
#' Named levels ("L1", "L2") are just historical instances of this at
#' 60 m and 10 m resolution respectively. They are kept only as
#' convenience aliases accepted wherever a resolution is expected (see
#' [tile_size()]) and as a parse-time alias in [parse_tile_id()]; new
#' resolutions do not need a name.
#'
#' @format
#' \describe{
#'   \item{GRID_ORIGIN}{c(x = 140000, y = 20000): grid origin in UTM
#'     metres, shared by every UTM zone and aligned to the Sentinel-2
#'     tiling grid}
#'   \item{PIXELS_PER_TILE}{600: pixel count per tile edge, fixed across
#'     every resolution}
#'   \item{LEVEL_RESOLUTIONS}{c(L1 = 60, L2 = 10): resolution (metres)
#'     named by legacy level, used only to resolve/parse level aliases}
#' }
#' @name GRID_SPEC
NULL

#' @rdname GRID_SPEC
#' @export
GRID_ORIGIN <- c(x = 140000, y = 20000)

#' @rdname GRID_SPEC
#' @export
PIXELS_PER_TILE <- 600

#' @rdname GRID_SPEC
#' @export
LEVEL_RESOLUTIONS <- c(L1 = 60, L2 = 10)
