//// Der Zwei-Phasen-Löser (nach Herbert Kociemba).
////
//// Phase 1 bringt den Würfel in die Untergruppe <U, D, R2, L2, F2, B2>
//// (alle Kanten richtig orientiert, Mittelschicht-Kanten in der Mittelschicht,
//// alle Ecken richtig gedreht). Phase 2 löst ihn dann nur noch mit diesen Zügen.
//// Beide Phasen sind IDA*-Suchen mit Abstandstabellen als Heuristik.

import gleam/bool
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import rubixcube/arr.{type Arr}
import rubixcube/clock
import rubixcube/coords.{type Coord}
import rubixcube/cube.{type Cube, type Move}
import rubixcube/seq
import rubixcube/table.{type Bytes, type Ints}

pub type Tables {
  Tables(
    twist: Ints,
    flip: Ints,
    slice: Ints,
    corner: Ints,
    edge: Ints,
    slice_perm: Ints,
    prune_twist_slice: Bytes,
    prune_flip_slice: Bytes,
    prune_corner_slice: Bytes,
    prune_edge_slice: Bytes,
    slice_goal: Int,
    phase2_moves: Arr(Int),
    move_cubes: Arr(Cube),
  )
}

pub type Solution {
  Solution(moves: List(Move), phase1_length: Int)
}

/// Erlaubte Züge in Phase 2 (Nummern aus `cube.move_index`): U, U2, U', R2, F2, D, D2, D', L2, B2.
const phase2_moves = [0, 1, 2, 4, 7, 9, 10, 11, 13, 16]

// ---------------------------------------------------------------- Tabellen

fn move_table(coord: Coord, cubes: Arr(Cube), moves: List(Int)) -> Ints {
  let moves = arr.from_list(moves)
  let m = arr.length(moves)
  // pro Koordinatenwert den Basiswürfel nur einmal konstruieren
  let rows =
    arr.generate(coord.size, fn(c) {
      let base = coord.set(c)
      arr.generate(m, fn(k) {
        coord.get(cube.multiply(base, arr.at(cubes, arr.at(moves, k))))
      })
    })
  table.ints_generate(coord.size * m, fn(i) {
    arr.at(arr.at(rows, i / m), i % m)
  })
}

/// Abstand zum gelösten Zustand für das Paar zweier Koordinaten.
fn pair_prune(
  n1: Int,
  n2: Int,
  t1: Ints,
  t2: Ints,
  m: Int,
  goal1: Int,
  goal2: Int,
) -> Bytes {
  table.bfs(
    size: n1 * n2,
    goal: goal2 * n1 + goal1,
    branching: m,
    step: fn(idx, k) {
      let a1 = idx % n1
      let a2 = idx / n1
      table.ints_get(t2, a2 * m + k) * n1 + table.ints_get(t1, a1 * m + k)
    },
  )
}

/// Baut alle Tabellen auf (dauert eine Sekunde; einmal pro Programmstart).
pub fn build() -> Tables {
  let cubes = cube.move_cubes()
  let all = seq.upto(18)
  let twist = coords.twist()
  let flip = coords.flip()
  let slice = coords.slice()
  let corner = coords.corner_perm()
  let edge = coords.edge_perm()
  let slice_perm = coords.slice_perm()
  let slice_goal = slice.get(cube.solved())
  let t_twist = move_table(twist, cubes, all)
  let t_flip = move_table(flip, cubes, all)
  let t_slice = move_table(slice, cubes, all)
  let t_corner = move_table(corner, cubes, phase2_moves)
  let t_edge = move_table(edge, cubes, phase2_moves)
  let t_sp = move_table(slice_perm, cubes, phase2_moves)
  Tables(
    twist: t_twist,
    flip: t_flip,
    slice: t_slice,
    corner: t_corner,
    edge: t_edge,
    slice_perm: t_sp,
    prune_twist_slice: pair_prune(
      2187,
      495,
      t_twist,
      t_slice,
      18,
      0,
      slice_goal,
    ),
    prune_flip_slice: pair_prune(2048, 495, t_flip, t_slice, 18, 0, slice_goal),
    prune_corner_slice: pair_prune(40_320, 24, t_corner, t_sp, 10, 0, 0),
    prune_edge_slice: pair_prune(40_320, 24, t_edge, t_sp, 10, 0, 0),
    slice_goal: slice_goal,
    phase2_moves: arr.from_list(phase2_moves),
    move_cubes: cubes,
  )
}

// ---------------------------------------------------------------- Suche

/// Warum eine Teilsuche ohne Ergebnis endet: erschöpft oder Zeit abgelaufen.
/// Ein Timeout bricht die gesamte Suche sofort ab.
type Failure {
  NoSolution
  Timeout
}

/// Gleiche Seite nie zweimal hintereinander; gegenüberliegende Seiten nur in einer Reihenfolge.
fn allowed(face: Int, last_face: Int) -> Bool {
  last_face < 0
  || { face != last_face && !{ face % 3 == last_face % 3 && face < last_face } }
}

fn lookup(t: Ints, index: Int) -> Int {
  table.ints_get(t, index)
}

/// Phase-2-Zustand: Koordinaten, Rest-Tiefe, zuletzt gedrehte Seite, bisheriger Weg (rückwärts).
type State2 {
  State2(cp: Int, ep: Int, sp: Int, depth: Int, last_face: Int, path: List(Int))
}

fn search2(t: Tables, deadline: Int, s: State2) -> Result(List(Int), Failure) {
  case s.depth {
    0 ->
      case s.cp == 0 && s.ep == 0 && s.sp == 0 {
        True -> Ok(list.reverse(s.path))
        False -> Error(NoSolution)
      }
    depth -> {
      let h =
        int.max(
          table.bytes_get(t.prune_corner_slice, s.sp * 40_320 + s.cp),
          table.bytes_get(t.prune_edge_slice, s.sp * 40_320 + s.ep),
        )
      use <- bool.guard(depth == 3 && clock.now_ms() > deadline, Error(Timeout))
      use <- bool.guard(h > depth, Error(NoSolution))
      try_phase2(t, deadline, s, 0)
    }
  }
}

fn try_phase2(
  t: Tables,
  deadline: Int,
  s: State2,
  k: Int,
) -> Result(List(Int), Failure) {
  use <- bool.guard(k >= 10, Error(NoSolution))
  let move = arr.at(t.phase2_moves, k)
  let face = move / 3
  case allowed(face, s.last_face) {
    False -> try_phase2(t, deadline, s, k + 1)
    True -> {
      let child =
        State2(
          cp: lookup(t.corner, s.cp * 10 + k),
          ep: lookup(t.edge, s.ep * 10 + k),
          sp: lookup(t.slice_perm, s.sp * 10 + k),
          depth: s.depth - 1,
          last_face: face,
          path: [move, ..s.path],
        )
      case search2(t, deadline, child) {
        Error(NoSolution) -> try_phase2(t, deadline, s, k + 1)
        found_or_timeout -> found_or_timeout
      }
    }
  }
}

/// Suchkontext für Phase 1: Tabellen, Ausgangswürfel, Tiefe der Phase 1,
/// maximale Gesamtlänge und Zeitpunkt, ab dem abgebrochen wird.
type Context {
  Context(t: Tables, start: Cube, d1: Int, limit: Int, deadline: Int)
}

/// Phase-1-Zustand: Koordinaten, Rest-Tiefe, zuletzt gedrehte Seite, Weg (rückwärts).
type State1 {
  State1(tw: Int, fl: Int, sl: Int, depth: Int, last_face: Int, path: List(Int))
}

fn search1(ctx: Context, s: State1) -> Result(List(Int), Failure) {
  let t = ctx.t
  case s.depth {
    0 ->
      case s.tw == 0 && s.fl == 0 && s.sl == t.slice_goal {
        True -> phase2(ctx, list.reverse(s.path))
        False -> Error(NoSolution)
      }
    depth -> {
      let h =
        int.max(
          table.bytes_get(t.prune_twist_slice, s.sl * 2187 + s.tw),
          table.bytes_get(t.prune_flip_slice, s.sl * 2048 + s.fl),
        )
      use <- bool.guard(
        depth == 4 && clock.now_ms() > ctx.deadline,
        Error(Timeout),
      )
      use <- bool.guard(h > depth, Error(NoSolution))
      try_phase1(ctx, s, 0)
    }
  }
}

fn try_phase1(
  ctx: Context,
  s: State1,
  move: Int,
) -> Result(List(Int), Failure) {
  use <- bool.guard(move >= 18, Error(NoSolution))
  let t = ctx.t
  let face = move / 3
  case allowed(face, s.last_face) {
    False -> try_phase1(ctx, s, move + 1)
    True -> {
      let child =
        State1(
          tw: lookup(t.twist, s.tw * 18 + move),
          fl: lookup(t.flip, s.fl * 18 + move),
          sl: lookup(t.slice, s.sl * 18 + move),
          depth: s.depth - 1,
          last_face: face,
          path: [move, ..s.path],
        )
      case search1(ctx, child) {
        Error(NoSolution) -> try_phase1(ctx, s, move + 1)
        found_or_timeout -> found_or_timeout
      }
    }
  }
}

/// Am Ende von Phase 1: Phase 2 mit wachsender Tiefe versuchen.
fn phase2(ctx: Context, path1: List(Int)) -> Result(List(Int), Failure) {
  use <- bool.guard(clock.now_ms() > ctx.deadline, Error(Timeout))
  let c =
    list.fold(path1, ctx.start, fn(c, m) {
      cube.multiply(c, arr.at(ctx.t.move_cubes, m))
    })
  let start =
    State2(
      cp: coords.corner_perm().get(c),
      ep: coords.edge_perm().get(c),
      sp: coords.slice_perm().get(c),
      depth: 0,
      last_face: case list.last(path1) {
        Ok(m) -> m / 3
        Error(_) -> -1
      },
      path: [],
    )
  deepen_phase2(ctx, start, path1, 0)
}

fn deepen_phase2(
  ctx: Context,
  start: State2,
  path1: List(Int),
  d2: Int,
) -> Result(List(Int), Failure) {
  use <- bool.guard(d2 > ctx.limit - ctx.d1, Error(NoSolution))
  case search2(ctx.t, ctx.deadline, State2(..start, depth: d2)) {
    Ok(p2) -> Ok(list.append(path1, p2))
    Error(NoSolution) -> deepen_phase2(ctx, start, path1, d2 + 1)
    Error(Timeout) -> Error(Timeout)
  }
}

const max_total = 30

const no_deadline = 1_000_000_000_000_000

/// Löst einen (gültigen) Würfel. Nach der ersten Lösung wird noch `extra_ms`
/// Millisekunden lang nach kürzeren gesucht.
pub fn solve(t: Tables, start: Cube, extra_ms: Int) -> Result(Solution, Nil) {
  let tw = coords.twist().get(start)
  let fl = coords.flip().get(start)
  let sl = coords.slice().get(start)
  deepen(t, start, State1(tw, fl, sl, 0, -1, []), None, no_deadline, extra_ms)
}

/// Phase-1-Tiefe schrittweise erhöhen; jede gefundene Lösung verkürzt die Obergrenze.
fn deepen(
  t: Tables,
  start: Cube,
  root: State1,
  best: Option(#(List(Int), Int)),
  deadline: Int,
  extra_ms: Int,
) -> Result(Solution, Nil) {
  let best_length = case best {
    Some(#(path, _)) -> list.length(path)
    None -> max_total + 1
  }
  let d1 = root.depth
  case d1 >= best_length || d1 > 20 || clock.now_ms() > deadline {
    True ->
      case best {
        Some(#(path, phase1)) ->
          Ok(Solution(list.map(path, cube.move_from_index), phase1))
        None -> Error(Nil)
      }
    False -> {
      let ctx = Context(t, start, d1, best_length - 1, deadline)
      case search1(ctx, root) {
        // gefunden: bei gleicher Tiefe nach noch kürzeren suchen
        Ok(path) -> {
          let deadline = case best {
            None -> clock.now_ms() + extra_ms
            Some(_) -> deadline
          }
          deepen(t, start, root, Some(#(path, d1)), deadline, extra_ms)
        }
        Error(NoSolution) ->
          deepen(
            t,
            start,
            State1(..root, depth: d1 + 1),
            best,
            deadline,
            extra_ms,
          )
        Error(Timeout) -> deepen(t, start, root, best, 0, extra_ms)
      }
    }
  }
}
