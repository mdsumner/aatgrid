"""Build explorer/coast.json: land and ice-shelf strips for the aatgrid explorer.

Inputs (pin these; `latest` and `master` move):
  - geoBoundaries CGAZ ADM0 parquet, from
    https://github.com/mdsumner/geoboundaries/releases/download/latest/geoBoundariesCGAZ_ADM0.parquet
    fetched 2026-09-29, 144765633 bytes,
    sha256 1f21197e1c8500edb1521d6fe2cd00faca0491cedcd3dcc1188b38e6119b2a7f
  - Natural Earth 10m Antarctic ice shelves, from
    https://raw.githubusercontent.com/nvkelso/natural-earth-vector/master/geojson/ne_10m_antarctic_ice_shelves_polys.geojson
    fetched 2026-09-29,
    sha256 8f9bf62368695f5664b5fcd9bc0e2baea66da295aea014ce0e9cf510f209898d
  CGAZ Antarctica is grounded land only (no ice shelves), hence the second source.

Output: lon 30..176, lat -84..-45, cut into 2-degree longitude strips so the
page can project only the strips near a zone's central meridian. Strip edges
are segmentized to 0.05 degree so they stay seamless after projection.
Coordinates are unsimplified, quantised to 1e-4 degree and delta-encoded.

Usage: python3 data-raw/explorer_coast.py CGAZ.parquet SHELVES.geojson explorer/coast.json
Requires: shapely >= 2, pyarrow.
"""
import json
import sys

import pyarrow.parquet as pq
import shapely
from shapely.geometry import Polygon, box, shape

LON0, LON1, LAT0, LAT1, STEP = 30, 176, -84, -45, 2
WINDOW = box(LON0, LAT0, LON1, LAT1)


def cgaz_land(path):
    t = pq.read_table(path)
    bb = t.column("geometry_bbox").to_pylist()
    geoms = []
    for i, b in enumerate(bb):
        if b["xmax"] < LON0 or b["xmin"] > LON1 or b["ymax"] < LAT0 or b["ymin"] > LAT1:
            continue
        g = shapely.from_wkb(t.column("geometry")[i].as_py()).intersection(WINDOW)
        if not g.is_empty:
            geoms.append(g)
    return shapely.union_all(geoms)


def ne_shelves(path):
    d = json.load(open(path))
    geoms = [shape(f["geometry"]).intersection(WINDOW) for f in d["features"]]
    return shapely.union_all([g for g in geoms if not g.is_empty])


def strips(geom, q):
    out = []
    for lon0 in range(LON0, LON1, STEP):
        s = geom.intersection(box(lon0, LAT0, lon0 + STEP, LAT1))
        if s.is_empty:
            continue
        polys = [g for g in getattr(s, "geoms", [s]) if isinstance(g, Polygon) and g.area > 0]
        enc = []
        for p in polys:
            p = shapely.segmentize(p, 0.05)
            rings = []
            for r in [p.exterior] + list(p.interiors):
                flat, px, py = [], 0, 0
                for x, y in list(r.coords)[:-1]:
                    ix, iy = round(x * q), round(y * q)
                    flat += [ix - px, iy - py]
                    px, py = ix, iy
                rings.append(flat)
            enc.append(rings)
        out.append([lon0, enc])
    return out


def main(cgaz, shelves, dest, q=10000):
    doc = {
        "q": q,
        "land": strips(cgaz_land(cgaz), q),
        "shelf": strips(ne_shelves(shelves), q),
        "source": {
            "land": "geoBoundaries CGAZ ADM0 (see data-raw/explorer_coast.py for the pinned file)",
            "shelf": "Natural Earth 10m antarctic_ice_shelves_polys",
            "window": "lon 30..176, lat -84..-45, 2-degree strips",
            "quantisation": "1e-4 degree, delta-encoded integers",
        },
    }
    with open(dest, "w") as f:
        json.dump(doc, f, separators=(",", ":"))


if __name__ == "__main__":
    main(*sys.argv[1:4])
