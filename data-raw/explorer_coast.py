"""Build explorer/coast/: land and ice-shelf strips for the aatgrid explorer.

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

Output: everything south of 45S, unsimplified, as 2-degree longitude strips
grouped into 10-degree sector files (coast/s_<lon0>.json) plus coast/index.json.
The page fetches only the sectors its current zone can show, so dense
coastlines far from the view (southern Chile) cost nothing until needed.
Strip edges are segmentized to 0.05 degree so they stay seamless after
projection. Coordinates are quantised to 1e-4 degree and delta-encoded.

Usage: python3 data-raw/explorer_coast.py CGAZ.parquet SHELVES.geojson explorer/coast
Requires: shapely >= 2, pyarrow.
"""
import json
import os
import sys

import pyarrow.parquet as pq
import shapely
from shapely.geometry import Polygon, box, shape

LAT0, LAT1 = -90, -45
STRIP, SECTOR = 2, 10
Q = 10000
WINDOW = box(-180, LAT0, 180, LAT1)


def cgaz_land(path):
    t = pq.read_table(path)
    bb = t.column("geometry_bbox").to_pylist()
    geoms = []
    for i, b in enumerate(bb):
        if b["ymin"] > LAT1:
            continue
        g = shapely.from_wkb(t.column("geometry")[i].as_py()).intersection(WINDOW)
        if not g.is_empty:
            geoms.append(g)
    return shapely.union_all(geoms)


def ne_shelves(path):
    d = json.load(open(path))
    geoms = [shape(f["geometry"]).intersection(WINDOW) for f in d["features"]]
    return shapely.union_all([g for g in geoms if not g.is_empty])


def encode_strip(geom, lon0):
    s = geom.intersection(box(lon0, LAT0, lon0 + STRIP, LAT1))
    if s.is_empty:
        return None
    polys = [g for g in getattr(s, "geoms", [s]) if isinstance(g, Polygon) and g.area > 0]
    enc = []
    for p in polys:
        p = shapely.segmentize(p, 0.05)
        rings = []
        for r in [p.exterior] + list(p.interiors):
            flat, px, py = [], 0, 0
            for x, y in list(r.coords)[:-1]:
                ix, iy = round(x * Q), round(y * Q)
                flat += [ix - px, iy - py]
                px, py = ix, iy
            rings.append(flat)
        enc.append(rings)
    return [lon0, enc] if enc else None


def main(cgaz, shelves, dest):
    os.makedirs(dest, exist_ok=True)
    land, shelf = cgaz_land(cgaz), ne_shelves(shelves)
    sectors = []
    for s0 in range(-180, 180, SECTOR):
        doc = {"land": [], "shelf": []}
        for lon0 in range(s0, s0 + SECTOR, STRIP):
            for key, g in (("land", land), ("shelf", shelf)):
                e = encode_strip(g, lon0)
                if e:
                    doc[key].append(e)
        if not doc["land"] and not doc["shelf"]:
            continue
        name = f"s_{s0}.json"
        with open(os.path.join(dest, name), "w") as f:
            json.dump(doc, f, separators=(",", ":"))
        sectors.append({"lon0": s0, "lon1": s0 + SECTOR, "file": name,
                        "bytes": os.path.getsize(os.path.join(dest, name))})
    index = {
        "q": Q, "lat0": LAT0, "lat1": LAT1, "sectors": sectors,
        "source": {
            "land": "geoBoundaries CGAZ ADM0 (pinned in data-raw/explorer_coast.py)",
            "shelf": "Natural Earth 10m antarctic_ice_shelves_polys",
            "quantisation": "1e-4 degree, delta-encoded integers",
        },
    }
    with open(os.path.join(dest, "index.json"), "w") as f:
        json.dump(index, f, separators=(",", ":"))


if __name__ == "__main__":
    main(*sys.argv[1:4])
