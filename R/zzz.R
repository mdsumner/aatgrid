# Package startup

.onAttach <- function(libname, pkgname) {
  packageStartupMessage("aatgrid: Antarctic Territory Grid System")
  packageStartupMessage("Two-level hierarchical grid (L1: 36km, L2: 6km)")
  packageStartupMessage("Use define_utm_zones() to get started")
}
