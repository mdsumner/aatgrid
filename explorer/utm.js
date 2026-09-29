// Transverse Mercator (Krueger n-series, Karney 2011), UTM south
const UTM = (() => {
  const a = 6378137, f = 1 / 298.257223563, k0 = 0.9996;
  const e2 = f * (2 - f), e = Math.sqrt(e2), n = f / (2 - f);
  const n2 = n*n, n3 = n2*n, n4 = n3*n, n5 = n4*n, n6 = n5*n;
  const A = a / (1 + n) * (1 + n2/4 + n4/64 + n6/256);
  const al = [0,
    n/2 - 2*n2/3 + 5*n3/16 + 41*n4/180 - 127*n5/288 + 7891*n6/37800,
    13*n2/48 - 3*n3/5 + 557*n4/1440 + 281*n5/630 - 1983433*n6/1935360,
    61*n3/240 - 103*n4/140 + 15061*n5/26880 + 167603*n6/181440,
    49561*n4/161280 - 179*n5/168 + 6601661*n6/7257600,
    34729*n5/80640 - 3418889*n6/1995840,
    212378941*n6/319334400];
  const be = [0,
    n/2 - 2*n2/3 + 37*n3/96 - n4/360 - 81*n5/512 + 96199*n6/604800,
    n2/48 + n3/15 - 437*n4/1440 + 46*n5/105 - 1118711*n6/3870720,
    17*n3/480 - 37*n4/840 - 209*n5/4480 + 5569*n6/90720,
    4397*n4/161280 - 11*n5/504 - 830251*n6/7257600,
    4583*n5/161280 - 108847*n6/3991680,
    20648693*n6/638668800];
  const D = Math.PI / 180;
  function fwd(lon, lat, cm) {
    const phi = lat * D, lam = (lon - cm) * D;
    const s = Math.sin(phi);
    const t = Math.sinh(Math.atanh(s) - e * Math.atanh(e * s));
    const cl = Math.cos(lam);
    const xi_ = Math.atan2(t, cl);
    const eta_ = Math.asinh(Math.sin(lam) / Math.sqrt(t*t + cl*cl));
    let xi = xi_, eta = eta_;
    for (let j = 1; j <= 6; j++) {
      xi += al[j] * Math.sin(2*j*xi_) * Math.cosh(2*j*eta_);
      eta += al[j] * Math.cos(2*j*xi_) * Math.sinh(2*j*eta_);
    }
    return [500000 + k0 * A * eta, 10000000 + k0 * A * xi];
  }
  function inv(x, y, cm) {
    const xi = (y - 10000000) / (k0 * A), eta = (x - 500000) / (k0 * A);
    let xi_ = xi, eta_ = eta;
    for (let j = 1; j <= 6; j++) {
      xi_ -= be[j] * Math.sin(2*j*xi) * Math.cosh(2*j*eta);
      eta_ -= be[j] * Math.cos(2*j*xi) * Math.sinh(2*j*eta);
    }
    const se = Math.sinh(eta_), cx = Math.cos(xi_);
    const tp = Math.sin(xi_) / Math.sqrt(se*se + cx*cx);
    let tau = tp;
    for (let i = 0; i < 6; i++) {
      const sq = Math.sqrt(1 + tau*tau);
      const sig = Math.sinh(e * Math.atanh(e * tau / sq));
      const tpi = tau * Math.sqrt(1 + sig*sig) - sig * sq;
      const d = (tp - tpi) / Math.sqrt(1 + tpi*tpi) * (1 + (1 - e2) * tau*tau) / ((1 - e2) * sq);
      tau += d;
      if (Math.abs(d) < 1e-14) break;
    }
    return [cm + Math.atan2(se, cx) / D, Math.atan(tau) / D];
  }
  return { fwd, inv };
})();
if (typeof module !== "undefined") module.exports = UTM;
