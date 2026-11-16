//// Veränderliche Zahlenfelder für die Suchtabellen (Int32Array / Uint8Array).
//// Mutation passiert nur beim Aufbau der Tabellen; danach werden sie nur noch gelesen.

pub type Ints

pub type Bytes

@external(javascript, "../rubixcube_ffi.mjs", "intsGenerate")
pub fn ints_generate(size: Int, with: fn(Int) -> Int) -> Ints

@external(javascript, "../rubixcube_ffi.mjs", "intsNew")
pub fn ints_new(size: Int) -> Ints

@external(javascript, "../rubixcube_ffi.mjs", "intsGet")
pub fn ints_get(table: Ints, index: Int) -> Int

@external(javascript, "../rubixcube_ffi.mjs", "intsSet")
pub fn ints_set(table: Ints, index: Int, value: Int) -> Nil

@external(javascript, "../rubixcube_ffi.mjs", "bytesNew")
pub fn bytes_new(size: Int, fill: Int) -> Bytes

@external(javascript, "../rubixcube_ffi.mjs", "bytesGet")
pub fn bytes_get(table: Bytes, index: Int) -> Int

@external(javascript, "../rubixcube_ffi.mjs", "bytesSet")
pub fn bytes_set(table: Bytes, index: Int, value: Int) -> Nil

/// Wert für „noch nicht besucht“ in Abstandstabellen.
pub const unvisited = 255

/// Breitensuche über einen Zustandsraum der Größe `size`.
/// `step(zustand, zug)` liefert den Folgezustand; `branching` ist die Zahl der Züge.
/// Ergebnis: Abstand jedes Zustands vom Ziel (`unvisited`, falls nicht erreichbar).
pub fn bfs(
  size size: Int,
  goal goal: Int,
  branching branching: Int,
  step step: fn(Int, Int) -> Int,
) -> Bytes {
  let dist = bytes_new(size, unvisited)
  let queue = ints_new(size)
  bytes_set(dist, goal, 0)
  ints_set(queue, 0, goal)
  bfs_loop(dist, queue, 0, 1, branching, step)
  dist
}

fn bfs_loop(
  dist: Bytes,
  queue: Ints,
  head: Int,
  tail: Int,
  branching: Int,
  step: fn(Int, Int) -> Int,
) -> Nil {
  case head < tail {
    False -> Nil
    True -> {
      let state = ints_get(queue, head)
      let depth = bytes_get(dist, state) + 1
      let tail = expand(dist, queue, tail, state, depth, 0, branching, step)
      bfs_loop(dist, queue, head + 1, tail, branching, step)
    }
  }
}

fn expand(
  dist: Bytes,
  queue: Ints,
  tail: Int,
  state: Int,
  depth: Int,
  move: Int,
  branching: Int,
  step: fn(Int, Int) -> Int,
) -> Int {
  case move < branching {
    False -> tail
    True -> {
      let next = step(state, move)
      case bytes_get(dist, next) == unvisited {
        False ->
          expand(dist, queue, tail, state, depth, move + 1, branching, step)
        True -> {
          bytes_set(dist, next, depth)
          ints_set(queue, tail, next)
          expand(dist, queue, tail + 1, state, depth, move + 1, branching, step)
        }
      }
    }
  }
}
