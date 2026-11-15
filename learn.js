/*
 * Lernmodus: Anfängermethode (Schicht für Schicht) mit Erklärungen.
 * Weiß liegt oben (erste Ebene), Gelb unten (letzte Ebene). Der Würfel muss nie gedreht werden.
 * Baut auf CubeSolver (solver.js) auf.
 *
 * Die klassischen Zugfolgen sind für "erste Ebene unten" notiert (Standard der Lehrbücher).
 * Da hier die erste Ebene oben liegt, werden sie per Vertauschen U<->D und F<->B übertragen
 * (entspricht einer Würfeldrehung um 180° um die Links-Rechts-Achse).
 */
(function (root) {
  'use strict';
  var S = root.CubeSolver || (typeof require !== 'undefined' ? require('./solver.js') : null);
  var multiply = S.multiply, moveCubes = S.moveCubes, moveNames = S.moveNames, newCube = S.newCube;

  var MAPL = { U: 'D', D: 'U', F: 'B', B: 'F', R: 'R', L: 'L' };
  var NAME = { U: 'Weiß', R: 'Rot', F: 'Grün', D: 'Gelb', L: 'Orange', B: 'Blau' };
  var CORNERS = ['URF', 'UFL', 'ULB', 'UBR', 'DFR', 'DLF', 'DBL', 'DRB'];
  var EDGES = ['UR', 'UF', 'UL', 'UB', 'DR', 'DF', 'DL', 'DB', 'FR', 'FL', 'BL', 'BR'];

  function sortStr(s) { return s.split('').sort().join(''); }
  function idxOf(list, letters) {
    var t = sortStr(letters);
    for (var i = 0; i < list.length; i++) if (sortStr(list[i]) === t) return i;
    throw new Error('Teil nicht gefunden: ' + letters);
  }
  function mapLetters(s) { return s.split('').map(function (c) { return MAPL[c]; }).join(''); }
  function realCorner(stdLetters) { return idxOf(CORNERS, mapLetters(stdLetters)); }
  function realEdge(stdLetters) { return idxOf(EDGES, mapLetters(stdLetters)); }
  function pieceName(letters) { return letters.split('').map(function (c) { return NAME[c]; }).join('-'); }

  function parse(alg) { return alg.trim().split(/\s+/).filter(Boolean); }
  function mapAlg(alg) { return parse(alg).map(function (t) { return MAPL[t[0]] + t.slice(1); }); }
  function applyMoves(cube, moves) {
    var c = cube;
    for (var i = 0; i < moves.length; i++) {
      var m = moveNames.indexOf(moves[i]);
      if (m < 0) throw new Error('Unbekannter Zug ' + moves[i]);
      c = multiply(c, moveCubes[m]);
    }
    return c;
  }
  function posOfCorner(c, id) { return c.cp.indexOf(id); }
  function posOfEdge(c, id) { return c.ep.indexOf(id); }

  // ------------------------------------------------------------------
  // Stufe 1: Kreuz – Kante für Kante, kürzester Weg über Tabellen
  // ------------------------------------------------------------------
  var CROSS_EDGES = [1, 0, 3, 2]; // UF (grün), UR (rot), UB (blau), UL (orange)
  var E_INV = moveCubes.map(function (mc) { var inv = []; for (var j = 0; j < 12; j++) inv[mc.ep[j]] = j; return inv; });
  var crossTables = {};

  function encodeStates(st) { var k = 0; for (var i = st.length - 1; i >= 0; i--) k = k * 24 + st[i]; return k; }
  function decodeStates(k, n) { var st = []; for (var i = 0; i < n; i++) { st.push(k % 24); k = (k / 24) | 0; } return st; }
  function stepEdgeState(s, m) {
    var p = s >> 1, o = s & 1, np = E_INV[m][p];
    return np * 2 + ((o + moveCubes[m].eo[np]) & 1);
  }
  function crossTable(k) {
    if (crossTables[k]) return crossTables[k];
    var n = k + 1, goal = [], i;
    for (i = 0; i < n; i++) goal.push(CROSS_EDGES[i] * 2);
    var dist = new Map(), q = [encodeStates(goal)], head = 0;
    dist.set(q[0], 0);
    while (head < q.length) {
      var key = q[head++], d = dist.get(key), st = decodeStates(key, n);
      for (var m = 0; m < 18; m++) {
        var ns = [];
        for (i = 0; i < n; i++) ns.push(stepEdgeState(st[i], m));
        var nk = encodeStates(ns);
        if (!dist.has(nk)) { dist.set(nk, d + 1); q.push(nk); }
      }
    }
    crossTables[k] = dist;
    return dist;
  }
  function crossKey(cube, k) {
    var st = [];
    for (var i = 0; i <= k; i++) { var p = posOfEdge(cube, CROSS_EDGES[i]); st.push(p * 2 + cube.eo[p]); }
    return encodeStates(st);
  }
  function solveCrossEdge(cube, k) {
    var dist = crossTable(k), moves = [], c = cube;
    var d = dist.get(crossKey(c, k));
    while (d > 0) {
      var found = false;
      for (var m = 0; m < 18; m++) {
        var nc = multiply(c, moveCubes[m]);
        if (dist.get(crossKey(nc, k)) === d - 1) { moves.push(moveNames[m]); c = nc; d--; found = true; break; }
      }
      if (!found) throw new Error('Kreuz: kein Weg gefunden');
    }
    return { moves: moves, cube: c };
  }

  // ------------------------------------------------------------------
  // Allgemeine Suche über Bausteine (Dijkstra, Kosten = Anzahl Züge)
  // ------------------------------------------------------------------
  function dijkstra(startCube, alphabet, keyFn, goalFn) {
    var best = new Map(), startKey = keyFn(startCube);
    var open = [{ cube: startCube, cost: 0, prev: null, via: null, key: startKey }];
    best.set(startKey, 0);
    var visited = 0;
    while (open.length) {
      var bi = 0, i;
      for (i = 1; i < open.length; i++) if (open[i].cost < open[bi].cost) bi = i;
      var node = open[bi];
      open[bi] = open[open.length - 1]; open.pop();
      if (node.cost > best.get(node.key)) continue;
      if (goalFn(node.cube)) {
        var path = [];
        for (var n = node; n.prev; n = n.prev) path.push({ alpha: n.via, before: n.prev.cube });
        path.reverse();
        return path;
      }
      if (++visited > 60000) break;
      for (i = 0; i < alphabet.length; i++) {
        var a = alphabet[i], nc = multiply(node.cube, a.cube), nk = keyFn(nc), cost = node.cost + a.moves.length;
        if (!best.has(nk) || cost < best.get(nk)) {
          best.set(nk, cost);
          open.push({ cube: nc, cost: cost, prev: node, via: a, key: nk });
        }
      }
    }
    throw new Error('Keine Baustein-Folge gefunden');
  }

  function macro(stdAlg, tag, extra) {
    var moves = mapAlg(stdAlg), o = { moves: moves, cube: applyMoves(newCube(), moves), tag: tag };
    if (extra) for (var k in extra) o[k] = extra[k];
    return o;
  }
  var TURNS = ['U', "U'", 'U2'].map(function (t) { return macro(t, 'align'); });

  function cornerKey(ids) {
    return function (c) {
      var k = 0;
      for (var i = 0; i < ids.length; i++) { var p = posOfCorner(c, ids[i]); k = k * 24 + p * 3 + c.co[p]; }
      return k;
    };
  }
  function edgeKey(ids) {
    return function (c) {
      var k = 0;
      for (var i = 0; i < ids.length; i++) { var p = posOfEdge(c, ids[i]); k = k * 24 + p * 2 + c.eo[p]; }
      return k;
    };
  }
  function cornerPair(ids) { var f = cornerKey(ids); return function (c) { return f(c); }; }

  // ------------------------------------------------------------------
  // Hauptfunktion
  // ------------------------------------------------------------------
  function solveLearn(startCube) {
    var cube = startCube;
    var stages = [];

    function stage(title, intro) { var st = { title: title, intro: intro, steps: [] }; stages.push(st); return st; }
    function addStep(st, title, why, items) {
      var macros = items.filter(function (m) { return m.moves.length; });
      if (macros.length) st.steps.push({ title: title, why: why, macros: macros });
    }
    function runPath(path, noteFn) {
      var out = [];
      path.forEach(function (p) { out.push({ moves: p.alpha.moves.slice(), tag: p.alpha.tag, note: noteFn(p.alpha, p.before) }); });
      return out;
    }
    function advance(path) {
      path.forEach(function (p) { cube = multiply(cube, p.alpha.cube); });
    }

    // ---- Stufe 1: Weißes Kreuz ----
    var st1 = stage('Das weiße Kreuz',
      'Wir beginnen oben mit den vier weißen Kanten. Sie bilden ein Kreuz auf der weißen Seite. ' +
      'Wichtig: Die zweite Farbe jeder Kante muss zur Mittelfarbe der Seitenfläche passen ' +
      '(Grün vorne, Rot rechts, Blau hinten, Orange links). Hier gibt es noch keine feste Zugfolge – ' +
      'das Programm zeigt dir den kürzesten Weg für jede Kante, ohne die schon fertigen zu zerstören.');
    for (var k = 0; k < 4; k++) {
      var r = solveCrossEdge(cube, k), id = CROSS_EDGES[k], nm = pieceName(EDGES[id]);
      addStep(st1, 'Kante ' + nm,
        'Bringe die Kante ' + nm + ' an ihren Platz oben: Weiß auf der weißen Seite, die zweite Farbe an der passenden Mittelfarbe.',
        [{ moves: r.moves, tag: 'cross', note: 'Kürzester Weg für die Kante ' + nm + '. Die schon fertigen Kreuz-Kanten bleiben am Ende erhalten.' }]);
      cube = r.cube;
    }

    // ---- Stufe 2: weiße Ecken ----
    var st2 = stage('Die weißen Ecken (erste Ebene)',
      'Jetzt kommen die vier weißen Ecken an ihren Platz oben. Jede Ecke wird zuerst in der unteren (gelben) Ebene so ausgerichtet, ' +
      'dass sie genau unter ihrem Zielplatz liegt. Dann hebt ein kurzer Baustein (rechts rein – Ebene drehen – rechts raus – Ebene zurück) ' +
      'sie nach oben. Diesen Baustein wiederholst du, bis die Ecke richtig sitzt. Steckt eine Ecke oben im falschen Platz, ' +
      'holt derselbe Baustein sie zuerst nach unten.');
    var cslots = [
      { c: 'DFR', s: 'R' }, { c: 'DRB', s: 'B' }, { c: 'DBL', s: 'L' }, { c: 'DLF', s: 'F' }
    ].map(function (x) {
      return { id: realCorner(x.c), s: x.s, T: macro(x.s + ' U ' + x.s + "' U'", 'corner') };
    });
    cslots.forEach(function (sl, j) {
      var target = sl.id, nm = pieceName(CORNERS[target]);
      var alpha = TURNS.slice();
      for (var q = j; q < 4; q++) { var T = cslots[q].T; alpha.push({ moves: T.moves, cube: T.cube, tag: 'corner', slot: cslots[q].id }); }
      var path = dijkstra(cube, alpha, cornerKey([target]), function (c) { var p = posOfCorner(c, target); return p === target && c.co[p] === 0; });
      var items = runPath(path, function (a, before) {
        if (a.tag === 'align') return 'Ausrichten: Drehe die untere (gelbe) Ebene, bis die Ecke ' + nm + ' im passenden Winkel unter ihrem Zielplatz steht.';
        var p = posOfCorner(before, target);
        if (p === a.slot) return 'Die Ecke steckt noch im falschen Platz bzw. falsch gedreht: Der Baustein hebt sie heraus. Wiederholt man ihn, setzt er sie am Ende richtig ein.';
        if (a.slot === target) return 'Baustein „Ecke einsetzen“: Wiederhole ihn so lange, bis die Ecke ' + nm + ' richtig oben sitzt (maximal 5-mal).';
        return 'Zwischenschritt: Dieser Baustein bringt die Ecke in eine günstigere Lage.';
      });
      advance(path);
      addStep(st2, 'Ecke ' + nm, 'Setze die Ecke ' + nm + ' an ihren Platz in der weißen Ebene.', items);
    });

    // ---- Stufe 3: Mittelschicht ----
    var st3 = stage('Die mittlere Ebene',
      'Die Ebene oben (weiß) ist fertig. Jetzt fehlen die vier Kanten der mittleren Ebene – das sind die Kanten ohne Gelb und ohne Weiß. ' +
      'Du drehst die untere (gelbe) Ebene so, dass die Kante mit ihrer Frontfarbe vor der passenden Mitte steht, und schiebst sie dann ' +
      'mit einem Baustein nach links oder rechts in die Mittelschicht. Sitzt eine Kante in der Mitte falsch, holt der Baustein sie zuerst heraus.');
    var eslots = [['F', 'R'], ['R', 'B'], ['B', 'L'], ['L', 'F']].map(function (pr) {
      var A = pr[0], B = pr[1];
      return {
        id: realEdge(A + B),
        R: macro('U ' + B + " U' " + B + "' U' " + A + "' U " + A, 'edge-right'),
        L: macro("U' " + A + "' U " + A + ' U ' + B + " U' " + B + "'", 'edge-left')
      };
    });
    eslots.forEach(function (sl, j) {
      var target = sl.id, nm = pieceName(EDGES[target]);
      var alpha = TURNS.slice();
      for (var q = j; q < 4; q++) {
        ['R', 'L'].forEach(function (d) {
          var M = eslots[q][d];
          alpha.push({ moves: M.moves, cube: M.cube, tag: M.tag, slot: eslots[q].id });
        });
      }
      var path = dijkstra(cube, alpha, edgeKey([target]), function (c) { var p = posOfEdge(c, target); return p === target && c.eo[p] === 0; });
      var items = runPath(path, function (a, before) {
        if (a.tag === 'align') return 'Ausrichten: Drehe die untere (gelbe) Ebene, bis die Kante ' + nm + ' mit ihrer Frontfarbe vor der passenden Mittelfarbe steht.';
        var p = posOfEdge(before, target);
        if (p === a.slot) return 'Die Kante sitzt in der Mitte falsch (oder verdreht): Dieser Baustein holt sie nach unten, damit du sie neu einsetzen kannst.';
        if (a.slot === target) return 'Baustein „Kante nach ' + (a.tag === 'edge-right' ? 'rechts' : 'links') + ' einsetzen“: Die Kante ' + nm + ' rutscht in die mittlere Ebene.';
        return 'Zwischenschritt: Dieser Baustein verschiebt die Kante in eine günstigere Lage.';
      });
      advance(path);
      addStep(st3, 'Kante ' + nm, 'Schiebe die Kante ' + nm + ' in die mittlere Ebene.', items);
    });

    // ---- Stufe 4: gelbes Kreuz ----
    var lastEdges = [4, 5, 6, 7], lastCorners = [4, 5, 6, 7];
    var st4 = stage('Das gelbe Kreuz',
      'Jetzt drehst du deinen Blick auf die untere (gelbe) Ebene. Ziel: Die gelben Flächen der vier Kanten zeigen nach unten und bilden ein Kreuz. ' +
      'Du siehst anfangs einen Punkt, einen Winkel oder eine Linie. Der Baustein „Kreuz“ (Vorderseite, rechts rein, Ebene, rechts raus, Ebene zurück, Vorderseite zurück) ' +
      'wird mit passender Ausrichtung wiederholt, bis das Kreuz steht.');
    var alpha4 = TURNS.concat([macro("F R U R' U' F'", 'cross-alg')]);
    var goal4 = function (c) { for (var i = 0; i < 4; i++) if (c.eo[posOfEdge(c, lastEdges[i])] !== 0) return false; return true; };
    var path4 = dijkstra(cube, alpha4, edgeKey(lastEdges), goal4);
    advance(path4);
    addStep(st4, 'Gelbes Kreuz bilden', 'Forme auf der gelben Seite ein Kreuz.',
      runPath(path4, function (a) {
        return a.tag === 'align' ? 'Ausrichten: Drehe die untere Ebene, bis die gelben Kanten so liegen, dass der nächste Baustein sie weiterbringt (Winkel hinten links, Linie waagrecht).'
          : 'Baustein „Kreuz“: bringt mehr gelbe Kanten nach unten. Eventuell nötig: zweimal anwenden.';
      }));

    // ---- Stufe 5: gelbe Fläche ----
    var st5 = stage('Die gelbe Fläche',
      'Als Nächstes sollen auch die vier gelben Ecken nach unten zeigen, sodass die ganze untere Seite gelb ist. ' +
      'Der Baustein „Ecken drehen“ (rechts rein, Ebene, rechts raus, Ebene, rechts rein, Ebene zweimal, rechts raus) ' +
      'dreht die Ecken Schritt für Schritt. Dabei wird die untere Ebene zwischendurch ausgerichtet; die anderen Ebenen sind am Ende wieder in Ordnung.');
    var alpha5 = TURNS.concat([macro("R U R' U R U2 R'", 'sune')]);
    var goal5 = function (c) { for (var i = 0; i < 4; i++) if (c.co[posOfCorner(c, lastCorners[i])] !== 0) return false; return true; };
    var path5 = dijkstra(cube, alpha5, cornerKey(lastCorners), goal5);
    advance(path5);
    addStep(st5, 'Gelbe Ecken nach unten drehen', 'Drehe die Ecken so, dass die untere Seite komplett gelb ist.',
      runPath(path5, function (a) {
        return a.tag === 'align' ? 'Ausrichten: Drehe die untere Ebene, bis eine noch falsche Ecke an der passenden Stelle (vorne links unten) liegt.'
          : 'Baustein „Ecken drehen“: Wiederhole ihn, bis die gelbe Seite komplett gelb ist.';
      }));

    // ---- Stufe 6: gelbe Ecken platzieren ----
    var st6 = stage('Die gelben Ecken platzieren',
      'Alle gelben Flächen zeigen jetzt nach unten, aber die Ecken müssen noch an ihre richtigen Plätze: Jede Ecke gehört zwischen ihre drei Mittelfarben. ' +
      'Der Baustein „Ecken tauschen“ bewegt drei Ecken im Kreis und lässt eine stehen. Zwischendurch wird die untere Ebene ausgerichtet.');
    var alpha6 = TURNS.concat([macro("R' F R' B2 R F' R' B2 R2", 'cornerperm')]);
    var goal6 = function (c) { for (var i = 0; i < 4; i++) if (posOfCorner(c, lastCorners[i]) !== lastCorners[i]) return false; return true; };
    var path6 = dijkstra(cube, alpha6, cornerKey(lastCorners), goal6);
    advance(path6);
    addStep(st6, 'Ecken an die richtige Stelle', 'Bringe jede gelbe Ecke an ihren Platz.',
      runPath(path6, function (a) {
        return a.tag === 'align' ? 'Ausrichten: Drehe die untere Ebene in die passende Stellung für den nächsten Baustein.'
          : 'Baustein „Ecken tauschen“: Drei Ecken wandern im Kreis – eine bleibt, wo sie ist.';
      }));

    // ---- Stufe 7: Kanten ----
    var st7 = stage('Die letzten Kanten',
      'Zum Schluss fehlen nur noch die gelben Kanten: Sie müssen in die richtige Reihenfolge. Der Baustein „Kanten tauschen“ bewegt drei Kanten im Kreis, ' +
      'ohne die Ecken zu verändern. Nach höchstens zwei Anwendungen (mit passender Ausrichtung) ist der Würfel gelöst.');
    var alpha7 = TURNS.concat([macro("R U' R U R U R U' R' U' R2", 'edgeperm')]);
    var goal7 = function (c) {
      for (var i = 0; i < 8; i++) if (c.cp[i] !== i || c.co[i] !== 0) return false;
      for (var j = 0; j < 12; j++) if (c.ep[j] !== j || c.eo[j] !== 0) return false;
      return true;
    };
    var key7 = function (c) { return cornerKey(lastCorners)(c) * 331776 + edgeKey(lastEdges)(c); };
    var path7 = dijkstra(cube, alpha7, key7, goal7);
    advance(path7);
    addStep(st7, 'Kanten an die richtige Stelle', 'Bringe die letzten Kanten in die richtige Reihenfolge.',
      runPath(path7, function (a) {
        return a.tag === 'align' ? 'Ausrichten: Drehe die untere Ebene (Hinweis: Achte darauf, welche Kante schon passt).'
          : 'Baustein „Kanten tauschen“: Drei Kanten wandern im Kreis, die Ecken bleiben unverändert.';
      }));

    if (!goal7(cube)) throw new Error('Lernmodus: Würfel nicht gelöst');
    return flatten(stages);
  }

  function flatten(stages) {
    var moves = [], meta = [], si, pi, mi, k, step, mac;
    var macroCounter = 0;
    var outStages = [];
    for (si = 0; si < stages.length; si++) {
      var st = stages[si], first = moves.length;
      for (pi = 0; pi < st.steps.length; pi++) {
        step = st.steps[pi];
        for (mi = 0; mi < step.macros.length; mi++) {
          mac = step.macros[mi];
          for (k = 0; k < mac.moves.length; k++) {
            moves.push(mac.moves[k]);
            meta.push({ stage: si, step: pi, macro: macroCounter, pos: k, len: mac.moves.length, note: mac.note, tag: mac.tag });
          }
          macroCounter++;
        }
      }
      outStages.push({
        title: st.title, intro: st.intro, first: first, count: moves.length - first,
        steps: st.steps.map(function (s) { return { title: s.title, why: s.why }; })
      });
    }
    // Schritt-Texte je Zug
    var idx = 0;
    for (si = 0; si < stages.length; si++) {
      stages[si].steps.forEach(function (s, pIdx) {
        s.macros.forEach(function (m) {
          for (var q = 0; q < m.moves.length; q++) { meta[idx].stepTitle = s.title; meta[idx].why = s.why; idx++; }
        });
      });
    }
    return { moves: moves, meta: meta, stages: outStages };
  }

  root.LearnSolver = { solve: solveLearn };
  if (typeof module !== 'undefined' && module.exports) module.exports = root.LearnSolver;
})(typeof window !== 'undefined' ? window : (typeof self !== 'undefined' ? self : globalThis));
