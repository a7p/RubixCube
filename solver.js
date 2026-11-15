/*
 * Zauberwürfel-Löser (3x3x3) – Zwei-Phasen-Algorithmus (nach Kociemba).
 * Läuft komplett im Browser (oder in Node zum Testen). Keine Abhängigkeiten.
 *
 * Facelet-Reihenfolge (54 Zeichen): U1-U9, R1-R9, F1-F9, D1-D9, L1-L9, B1-B9
 * Jedes Zeichen ist der Name der Seite, zu der die Farbe gehört (U,R,F,D,L,B).
 */
(function (root) {
  'use strict';

  var U = 0, R = 1, F = 2, D = 3, L = 4, B = 5;
  var FACE_LETTERS = 'URFDLB';

  // Ecken / Kanten
  var URF = 0, UFL = 1, ULB = 2, UBR = 3, DFR = 4, DLF = 5, DBL = 6, DRB = 7;
  var UR = 0, UF = 1, UL = 2, UB = 3, DR = 4, DF = 5, DL = 6, DB = 7, FR = 8, FL = 9, BL = 10, BR = 11;

  // Facelet-Positionen (Index in 0..53) je Ecke / Kante
  var cornerFacelet = [
    [8, 9, 20], [6, 18, 38], [0, 36, 47], [2, 45, 11],
    [29, 26, 15], [27, 44, 24], [33, 53, 42], [35, 17, 51]
  ];
  var edgeFacelet = [
    [5, 10], [7, 19], [3, 37], [1, 46], [32, 16], [28, 25], [30, 43], [34, 52],
    [23, 12], [21, 41], [50, 39], [48, 14]
  ];
  var cornerColor = [
    [U, R, F], [U, F, L], [U, L, B], [U, B, R],
    [D, F, R], [D, L, F], [D, B, L], [D, R, B]
  ];
  var edgeColor = [
    [U, R], [U, F], [U, L], [U, B], [D, R], [D, F], [D, L], [D, B],
    [F, R], [F, L], [B, L], [B, R]
  ];

  function range(n) { var a = []; for (var i = 0; i < n; i++) a.push(i); return a; }
  function zeros(n) { var a = []; for (var i = 0; i < n; i++) a.push(0); return a; }

  function newCube() { return { cp: range(8), co: zeros(8), ep: range(12), eo: zeros(12) }; }

  function multiply(a, b) {
    var c = { cp: new Array(8), co: new Array(8), ep: new Array(12), eo: new Array(12) };
    for (var i = 0; i < 8; i++) {
      var k = b.cp[i];
      c.cp[i] = a.cp[k];
      c.co[i] = (a.co[k] + b.co[i]) % 3;
    }
    for (var j = 0; j < 12; j++) {
      var m = b.ep[j];
      c.ep[j] = a.ep[m];
      c.eo[j] = (a.eo[m] + b.eo[j]) % 2;
    }
    return c;
  }

  var basicMoves = [
    // U
    { cp: [UBR, URF, UFL, ULB, DFR, DLF, DBL, DRB], co: zeros(8),
      ep: [UB, UR, UF, UL, DR, DF, DL, DB, FR, FL, BL, BR], eo: zeros(12) },
    // R
    { cp: [DFR, UFL, ULB, URF, DRB, DLF, DBL, UBR], co: [2, 0, 0, 1, 1, 0, 0, 2],
      ep: [FR, UF, UL, UB, BR, DF, DL, DB, DR, FL, BL, UR], eo: zeros(12) },
    // F
    { cp: [UFL, DLF, ULB, UBR, URF, DFR, DBL, DRB], co: [1, 2, 0, 0, 2, 1, 0, 0],
      ep: [UR, FL, UL, UB, DR, FR, DL, DB, UF, DF, BL, BR], eo: [0, 1, 0, 0, 0, 1, 0, 0, 1, 1, 0, 0] },
    // D
    { cp: [URF, UFL, ULB, UBR, DLF, DBL, DRB, DFR], co: zeros(8),
      ep: [UR, UF, UL, UB, DF, DL, DB, DR, FR, FL, BL, BR], eo: zeros(12) },
    // L
    { cp: [URF, ULB, DBL, UBR, DFR, UFL, DLF, DRB], co: [0, 1, 2, 0, 0, 2, 1, 0],
      ep: [UR, UF, BL, UB, DR, DF, FL, DB, FR, UL, DL, BR], eo: zeros(12) },
    // B
    { cp: [URF, UFL, UBR, DRB, DFR, DLF, ULB, DBL], co: [0, 0, 1, 2, 0, 0, 2, 1],
      ep: [UR, UF, UL, BR, DR, DF, DL, BL, FR, FL, UB, DB], eo: [0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 1, 1] }
  ];

  // 18 Züge: Index = 3*Seite + (0: Viertel cw, 1: halbe Drehung, 2: Viertel ccw)
  var moveCubes = [];
  var moveNames = [];
  (function () {
    for (var f = 0; f < 6; f++) {
      var p = basicMoves[f], cur = newCube();
      for (var k = 0; k < 3; k++) {
        cur = multiply(cur, p);
        moveCubes.push(cur);
        moveNames.push(FACE_LETTERS[f] + (k === 0 ? '' : k === 1 ? '2' : "'"));
      }
    }
  })();

  // ---------- Umwandlung Facelets <-> Würfel ----------

  function parity(arr) {
    var s = 0;
    for (var i = 0; i < arr.length; i++)
      for (var j = i + 1; j < arr.length; j++) if (arr[i] > arr[j]) s++;
    return s & 1;
  }

  /** Wandelt einen 54-Zeichen-String in einen Würfel. Gibt {cube} oder {error} zurück. */
  function fromFacelets(str) {
    if (typeof str !== 'string' || str.length !== 54) return { error: 'Ungültige Eingabe.' };
    var fc = [];
    for (var i = 0; i < 54; i++) {
      var f = FACE_LETTERS.indexOf(str[i]);
      if (f < 0) return { error: 'Es sind noch nicht alle Felder ausgefüllt.' };
      fc.push(f);
    }
    var counts = zeros(6);
    for (i = 0; i < 54; i++) counts[fc[i]]++;
    for (i = 0; i < 6; i++)
      if (counts[i] !== 9) return { error: 'Jede Farbe muss genau 9-mal vorkommen (zurzeit: ' + FACE_LETTERS[i] + ' ' + counts[i] + '×).', counts: counts };
    var c = newCube(), seen, j, ori;
    seen = zeros(8);
    for (i = 0; i < 8; i++) {
      var cf = cornerFacelet[i];
      for (ori = 0; ori < 3; ori++) if (fc[cf[ori]] === U || fc[cf[ori]] === D) break;
      if (ori === 3) return { error: 'Eine Ecke enthält weder Weiß noch Gelb – das gibt es nicht.' };
      var c1 = fc[cf[(ori + 1) % 3]], c2 = fc[cf[(ori + 2) % 3]];
      var found = false;
      for (j = 0; j < 8; j++) {
        if (c1 === cornerColor[j][1] && c2 === cornerColor[j][2]) {
          c.cp[i] = j; c.co[i] = ori; found = true; break;
        }
      }
      if (!found) return { error: 'Eine Ecke hat eine Farbkombination, die es an einem echten Würfel nicht gibt.' };
      seen[c.cp[i]]++;
    }
    for (i = 0; i < 8; i++) if (seen[i] !== 1) return { error: 'Eine Ecke kommt doppelt vor (und eine andere fehlt).' };
    seen = zeros(12);
    for (i = 0; i < 12; i++) {
      var ef = edgeFacelet[i], a = fc[ef[0]], b = fc[ef[1]], ok = false;
      for (j = 0; j < 12; j++) {
        if (a === edgeColor[j][0] && b === edgeColor[j][1]) { c.ep[i] = j; c.eo[i] = 0; ok = true; break; }
        if (a === edgeColor[j][1] && b === edgeColor[j][0]) { c.ep[i] = j; c.eo[i] = 1; ok = true; break; }
      }
      if (!ok) return { error: 'Eine Kante hat eine Farbkombination, die es an einem echten Würfel nicht gibt.' };
      seen[c.ep[i]]++;
    }
    for (i = 0; i < 12; i++) if (seen[i] !== 1) return { error: 'Eine Kante kommt doppelt vor (und eine andere fehlt).' };
    var v = verify(c);
    if (v) return { error: v };
    return { cube: c };
  }

  /** Prüft, ob der Würfel physikalisch lösbar ist. Gibt null oder eine Fehlermeldung zurück. */
  function verify(c) {
    var s = 0, i;
    for (i = 0; i < 12; i++) s += c.eo[i];
    if (s % 2 !== 0) return 'Eine Kante ist falsch herum gedreht (Kanten-Orientierung ungültig).';
    s = 0;
    for (i = 0; i < 8; i++) s += c.co[i];
    if (s % 3 !== 0) return 'Eine Ecke ist verdreht (Ecken-Orientierung ungültig).';
    if (parity(c.ep) !== parity(c.cp)) return 'Zwei Steine sind vertauscht (Permutations-Parität ungültig) – ein echter Würfel lässt sich so nicht erreichen.';
    return null;
  }

  function toFacelets(c) {
    var fc = new Array(54), i, n, j;
    for (i = 0; i < 6; i++) fc[9 * i + 4] = FACE_LETTERS[i];
    for (i = 0; i < 8; i++) {
      j = c.cp[i];
      for (n = 0; n < 3; n++) fc[cornerFacelet[i][(n + c.co[i]) % 3]] = FACE_LETTERS[cornerColor[j][n]];
    }
    for (i = 0; i < 12; i++) {
      j = c.ep[i];
      for (n = 0; n < 2; n++) fc[edgeFacelet[i][(n + c.eo[i]) % 2]] = FACE_LETTERS[edgeColor[j][n]];
    }
    return fc.join('');
  }

  /** Wendet einen Zug (z. B. "R", "U'", "F2") auf einen Facelet-String an. */
  function applyMove(str, name) {
    var r = fromFacelets(str);
    if (!r.cube) throw new Error(r.error);
    var m = moveNames.indexOf(name);
    if (m < 0) throw new Error('Unbekannter Zug ' + name);
    return toFacelets(multiply(r.cube, moveCubes[m]));
  }

  // ---------- Koordinaten ----------

  function binom(n, k) {
    if (k < 0 || k > n) return 0;
    var r = 1;
    for (var i = 1; i <= k; i++) r = r * (n - k + i) / i;
    return Math.round(r);
  }

  function getTwist(c) { var t = 0; for (var i = 0; i < 7; i++) t = 3 * t + c.co[i]; return t; }
  function setTwist(c, t) {
    var p = 0;
    for (var i = 6; i >= 0; i--) { c.co[i] = t % 3; p += c.co[i]; t = (t / 3) | 0; }
    c.co[7] = (3 - p % 3) % 3;
  }
  function getFlip(c) { var t = 0; for (var i = 0; i < 11; i++) t = 2 * t + c.eo[i]; return t; }
  function setFlip(c, t) {
    var p = 0;
    for (var i = 10; i >= 0; i--) { c.eo[i] = t & 1; p += c.eo[i]; t >>= 1; }
    c.eo[11] = p & 1;
  }
  // Position der 4 Mittelschicht-Kanten (Ids 8..11), ohne Reihenfolge: 0..494
  function getSlice(c) {
    var idx = 0, k = 0;
    for (var pos = 0; pos < 12; pos++) if (c.ep[pos] >= 8) { k++; idx += binom(pos, k); }
    return idx;
  }
  function setSlice(c, idx) {
    var positions = [], k, pos;
    for (k = 4; k >= 1; k--) {
      pos = 11;
      while (binom(pos, k) > idx) pos--;
      idx -= binom(pos, k);
      positions.push(pos);
    }
    var isSlice = zeros(12);
    positions.forEach(function (p) { isSlice[p] = 1; });
    var nextS = 8, nextO = 0;
    for (pos = 0; pos < 12; pos++) c.ep[pos] = isSlice[pos] ? nextS++ : nextO++;
  }

  function rankPerm(arr, off, n) {
    var r = 0;
    for (var i = 0; i < n; i++) {
      var cnt = 0;
      for (var j = i + 1; j < n; j++) if (arr[off + j] < arr[off + i]) cnt++;
      r = r * (n - i) + cnt;
    }
    return r;
  }
  function unrankPerm(r, n) {
    var digits = new Array(n), i;
    for (i = n - 1; i >= 0; i--) { var base = n - i; digits[i] = r % base; r = (r / base) | 0; }
    var avail = range(n), out = [];
    for (i = 0; i < n; i++) out.push(avail.splice(digits[i], 1)[0]);
    return out;
  }
  function getCP(c) { return rankPerm(c.cp, 0, 8); }
  function setCP(c, r) { c.cp = unrankPerm(r, 8); }
  function getEP(c) { return rankPerm(c.ep, 0, 8); }
  function setEP(c, r) { var p = unrankPerm(r, 8); for (var i = 0; i < 8; i++) c.ep[i] = p[i]; for (i = 8; i < 12; i++) c.ep[i] = i; }
  function getSP(c) { return rankPerm(c.ep, 8, 4); }
  function setSP(c, r) { var p = unrankPerm(r, 4); for (var i = 0; i < 4; i++) c.ep[8 + i] = 8 + p[i]; }

  // ---------- Tabellen ----------

  var P2 = [0, 1, 2, 4, 7, 9, 10, 11, 13, 16]; // erlaubte Züge in Phase 2
  var T = null;

  function buildMoveTable(n, get, set, moves) {
    var m = moves.length, t = new Int32Array(n * m);
    for (var c = 0; c < n; c++) {
      var base = newCube();
      set(base, c);
      for (var k = 0; k < m; k++) t[c * m + k] = get(multiply(base, moveCubes[moves[k]]));
    }
    return t;
  }

  function buildPrun(n1, n2, t1, t2, m, goal1, goal2) {
    var size = n1 * n2, p = new Int8Array(size).fill(-1), q = new Int32Array(size);
    var head = 0, tail = 0, start = goal2 * n1 + goal1;
    p[start] = 0; q[tail++] = start;
    while (head < tail) {
      var idx = q[head++], a1 = idx % n1, a2 = (idx / n1) | 0, d = p[idx] + 1;
      for (var k = 0; k < m; k++) {
        var j = t2[a2 * m + k] * n1 + t1[a1 * m + k];
        if (p[j] < 0) { p[j] = d; q[tail++] = j; }
      }
    }
    return p;
  }

  function init() {
    if (T) return;
    var all = range(18), solved = newCube();
    T = {};
    T.twist = buildMoveTable(2187, getTwist, setTwist, all);
    T.flip = buildMoveTable(2048, getFlip, setFlip, all);
    T.slice = buildMoveTable(495, getSlice, setSlice, all);
    T.sliceGoal = getSlice(solved);
    T.cp = buildMoveTable(40320, getCP, setCP, P2);
    T.ep = buildMoveTable(40320, getEP, setEP, P2);
    T.sp = buildMoveTable(24, getSP, setSP, P2);
    T.pTwSl = buildPrun(2187, 495, T.twist, T.slice, 18, 0, T.sliceGoal);
    T.pFlSl = buildPrun(2048, 495, T.flip, T.slice, 18, 0, T.sliceGoal);
    T.pCpSp = buildPrun(40320, 24, T.cp, T.sp, 10, 0, 0);
    T.pEpSp = buildPrun(40320, 24, T.ep, T.sp, 10, 0, 0);
  }

  // ---------- Suche ----------

  function now() { return (typeof performance !== 'undefined' ? performance : Date).now(); }

  function allowed(face, lastFace) {
    if (lastFace < 0) return true;
    if (face === lastFace) return false;
    if (face % 3 === lastFace % 3 && face < lastFace) return false; // gegenüberliegende Seiten nur in einer Reihenfolge
    return true;
  }

  /**
   * Löst einen Würfel. Rückgabe: { moves: [...], phase1: n } (phase1 = Anzahl Züge der Phase 1).
   * opts.timeLimit: Zeit (ms) für die Suche nach kürzeren Lösungen, nachdem eine erste gefunden wurde.
   */
  function solveCube(cube, opts) {
    opts = opts || {};
    init();
    var extraTime = opts.timeLimit != null ? opts.timeLimit : 1200;
    var hardLimit = 20000;
    var tStart = now(), tFirst = 0;
    var tw0 = getTwist(cube), fl0 = getFlip(cube), sl0 = getSlice(cube);
    var best = null; // { path: [...], d1 }
    var maxTotal = 30;
    var stop = false, nodes = 0;
    var path = [];

    function timeUp() {
      if (best) return now() - tFirst > extraTime;
      return now() - tStart > hardLimit;
    }

    function search2(cp, ep, sp, depth, lastFace, out) {
      if (depth === 0) return cp === 0 && ep === 0 && sp === 0;
      var h = Math.max(T.pCpSp[sp * 40320 + cp], T.pEpSp[sp * 40320 + ep]);
      if (h > depth) return false;
      for (var k = 0; k < 10; k++) {
        var mv = P2[k], face = (mv / 3) | 0;
        if (!allowed(face, lastFace)) continue;
        var ncp = T.cp[cp * 10 + k], nep = T.ep[ep * 10 + k], nsp = T.sp[sp * 10 + k];
        out.push(mv);
        if (search2(ncp, nep, nsp, depth - 1, face, out)) return true;
        out.pop();
      }
      return false;
    }

    function leaf(d1) {
      var c = cube;
      for (var i = 0; i < path.length; i++) c = multiply(c, moveCubes[path[i]]);
      var cp = getCP(c), ep = getEP(c), sp = getSP(c);
      var limit = (best ? best.path.length - 1 : maxTotal) - d1;
      var lastFace = path.length ? (path[path.length - 1] / 3) | 0 : -1;
      for (var d2 = 0; d2 <= limit; d2++) {
        var out = [];
        if (search2(cp, ep, sp, d2, lastFace, out)) {
          if (!best) tFirst = now();
          best = { path: path.concat(out), d1: d1 };
          return;
        }
      }
    }

    function search1(tw, fl, sl, depth, lastFace, d1) {
      if (stop) return;
      if (depth === 0) {
        if (tw === 0 && fl === 0 && sl === T.sliceGoal) leaf(d1);
        return;
      }
      if (((++nodes) & 1023) === 0 && timeUp()) { stop = true; return; }
      var h = Math.max(T.pTwSl[sl * 2187 + tw], T.pFlSl[sl * 2048 + fl]);
      if (h > depth) return;
      for (var m = 0; m < 18; m++) {
        var face = (m / 3) | 0;
        if (!allowed(face, lastFace)) continue;
        path.push(m);
        search1(T.twist[tw * 18 + m], T.flip[fl * 18 + m], T.slice[sl * 18 + m], depth - 1, face, d1);
        path.pop();
        if (stop) return;
      }
    }

    for (var d1 = 0; d1 <= 20 && !stop; d1++) {
      if (best && d1 >= best.path.length) break;
      search1(tw0, fl0, sl0, d1, -1, d1);
    }
    if (!best) throw new Error('Keine Lösung gefunden.');
    return { moves: best.path.map(function (m) { return moveNames[m]; }), phase1: best.d1 };
  }

  /** Bequeme Funktion: Facelet-String -> Lösung oder {error}. */
  function solve(str, opts) {
    var r = fromFacelets(str);
    if (!r.cube) return { error: r.error, counts: r.counts };
    return solveCube(r.cube, opts);
  }

  root.CubeSolver = {
    init: init, solve: solve, solveCube: solveCube, fromFacelets: fromFacelets, toFacelets: toFacelets,
    applyMove: applyMove, verify: verify, moveNames: moveNames, moveCubes: moveCubes, multiply: multiply,
    newCube: newCube, SOLVED: toFacelets(newCube())
  };
  if (typeof module !== 'undefined' && module.exports) module.exports = root.CubeSolver;
})(typeof window !== 'undefined' ? window : (typeof self !== 'undefined' ? self : globalThis));
