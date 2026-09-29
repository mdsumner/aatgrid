# aatgrid explorer

A static page that draws the aatgrid tile lattice on UTM south zones over the
Australian Antarctic Territory coast. Published by `.github/workflows/pages.yml`
to `https://mdsumner.github.io/aatgrid/explorer/`.

Files:

- `index.html`: page and styles.
- `app.js`: grid arithmetic (mirrors `R/antarctic_grid_system.R` and
  `R/bounds_materialize.R`), rendering and interaction.
- `utm.js`: UTM south forward/inverse (Kruger n-series, Karney 2011); agrees
  with PROJ to under 0.1 mm, including 48 degrees off the central meridian.
- `coast.json`: land (geoBoundaries CGAZ ADM0, unsimplified) and ice shelves
  (Natural Earth 10m) in 2-degree strips. Rebuild with
  `data-raw/explorer_coast.py`, which records the pinned inputs.

Grid defaults in the page are origin 140000 / 20000, 720 px tiles and
resolutions 10, 20, 60. The page lets you switch tile size and origin, so
it can show both the v0.2.0 (600 px) and the 720 px scheme.

Run locally: `python3 -m http.server -d explorer` and open
http://localhost:8000. Opening `index.html` as a file will not load
`coast.json`.
