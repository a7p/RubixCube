//// Koordinaten für den Zwei-Phasen-Algorithmus: Teile des Würfelzustands als
//// kleine Zahlen, damit Züge als Tabellen berechnet werden können.
////
//// Phase 1 (alle 18 Züge): Ecken-Drehung (twist, 3^7), Kanten-Flip (flip, 2^11),
////   Lage der vier Mittelschicht-Kanten (slice, 495).
//// Phase 2 (nur U, D, R2, L2, F2, B2): Eckenpermutation (8!), Permutation der
////   acht U/D-Kanten (8!) und der vier Mittelschicht-Kanten (24).

import gleam/list
import rubixcube/arr
import rubixcube/cube.{type Cube, Cube}
import rubixcube/seq

/// Eine Koordinate: Größe des Wertebereichs, Auslesen und Rückwärts-Konstruktion.
pub type Coord {
  Coord(size: Int, get: fn(Cube) -> Int, set: fn(Int) -> Cube)
}

// ---------------------------------------------------------------- Hilfen

/// Ziffern von `n` zur Basis `base`, höchstwertige zuerst, immer `width` Stück.
fn digits(n: Int, base: Int, width: Int) -> List(Int) {
  seq.upto(width)
  |> list.map(fn(i) { { n / seq.pow(base, width - 1 - i) } % base })
}

fn from_digits(ds: List(Int), base: Int) -> Int {
  list.fold(ds, 0, fn(acc, d) { acc * base + d })
}

fn binomial(n: Int, k: Int) -> Int {
  case k < 0 || k > n {
    True -> 0
    False ->
      seq.between(1, k)
      |> list.fold(1, fn(acc, i) { acc * { n - k + i } / i })
  }
}

/// Rang einer Permutation (Lehmer-Code, 0 = Identität).
pub fn rank_perm(perm: List(Int)) -> Int {
  rank_loop(perm, 0)
}

fn rank_loop(perm: List(Int), acc: Int) -> Int {
  case perm {
    [] -> acc
    [x, ..rest] ->
      rank_loop(
        rest,
        acc * list.length(perm) + list.count(rest, fn(y) { y < x }),
      )
  }
}

/// Umkehrung von `rank_perm` für Permutationen von 0..n-1.
pub fn unrank_perm(rank: Int, n: Int) -> List(Int) {
  // Lehmer-Ziffern: letzte Stelle hat Basis 1, die vorletzte Basis 2, …
  let #(lehmer, _) =
    seq.between(0, n - 1)
    |> list.reverse
    |> list.fold(#([], rank), fn(acc, i) {
      let #(ds, r) = acc
      let base = n - i
      #([r % base, ..ds], r / base)
    })
  pick(lehmer, seq.upto(n), [])
}

fn pick(
  lehmer: List(Int),
  available: List(Int),
  picked: List(Int),
) -> List(Int) {
  case lehmer {
    [] -> list.reverse(picked)
    [d, ..rest] -> {
      let #(before, after) = list.split(available, d)
      case after {
        [x, ..others] -> pick(rest, list.append(before, others), [x, ..picked])
        [] -> list.reverse(picked)
      }
    }
  }
}

fn ints(values: List(Int)) -> arr.Arr(Int) {
  arr.from_list(values)
}

fn with(
  cp cp: List(Int),
  co co: List(Int),
  ep ep: List(Int),
  eo eo: List(Int),
) -> Cube {
  Cube(ints(cp), ints(co), ints(ep), ints(eo))
}

fn identity(n: Int) -> List(Int) {
  seq.upto(n)
}

fn zeros(n: Int) -> List(Int) {
  list.repeat(0, n)
}

// ---------------------------------------------------------------- Phase 1

pub fn twist() -> Coord {
  Coord(
    size: 2187,
    get: fn(c) { from_digits(list.take(arr.to_list(c.co), 7), 3) },
    set: fn(t) {
      let ds = digits(t, 3, 7)
      let last = { 3 - { list.fold(ds, 0, fn(a, b) { a + b }) % 3 } } % 3
      with(
        cp: identity(8),
        co: list.append(ds, [last]),
        ep: identity(12),
        eo: zeros(12),
      )
    },
  )
}

pub fn flip() -> Coord {
  Coord(
    size: 2048,
    get: fn(c) { from_digits(list.take(arr.to_list(c.eo), 11), 2) },
    set: fn(f) {
      let ds = digits(f, 2, 11)
      let last = list.fold(ds, 0, fn(a, b) { a + b }) % 2
      with(
        cp: identity(8),
        co: zeros(8),
        ep: identity(12),
        eo: list.append(ds, [last]),
      )
    },
  )
}

/// Lage der Mittelschicht-Kanten (Ids 8–11) ohne Beachtung ihrer Reihenfolge.
pub fn slice() -> Coord {
  Coord(
    size: 495,
    get: fn(c) {
      arr.to_list(c.ep)
      |> list.index_fold(#(0, 0), fn(acc, edge, position) {
        let #(rank, seen) = acc
        case edge >= 8 {
          True -> #(rank + binomial(position, seen + 1), seen + 1)
          False -> #(rank, seen)
        }
      })
      |> fn(pair) { pair.0 }
    },
    set: fn(rank) {
      let positions = slice_positions(rank)
      let #(ep, _, _) =
        seq.upto(12)
        |> list.fold(#([], 8, 0), fn(acc, position) {
          let #(out, next_slice, next_other) = acc
          case list.contains(positions, position) {
            True -> #([next_slice, ..out], next_slice + 1, next_other)
            False -> #([next_other, ..out], next_slice, next_other + 1)
          }
        })
      with(cp: identity(8), co: zeros(8), ep: list.reverse(ep), eo: zeros(12))
    },
  )
}

fn slice_positions(rank: Int) -> List(Int) {
  // Kombinatorisches Zahlensystem: größte Position p mit C(p,k) <= Rest, k = 4..1
  let #(positions, _) =
    [4, 3, 2, 1]
    |> list.fold(#([], rank), fn(acc, k) {
      let #(found, rest) = acc
      let position = largest_position(k, rest, 11)
      #([position, ..found], rest - binomial(position, k))
    })
  positions
}

fn largest_position(k: Int, limit: Int, from: Int) -> Int {
  case binomial(from, k) > limit {
    True -> largest_position(k, limit, from - 1)
    False -> from
  }
}

// ---------------------------------------------------------------- Phase 2

pub fn corner_perm() -> Coord {
  Coord(size: 40_320, get: fn(c) { rank_perm(arr.to_list(c.cp)) }, set: fn(r) {
    with(cp: unrank_perm(r, 8), co: zeros(8), ep: identity(12), eo: zeros(12))
  })
}

pub fn edge_perm() -> Coord {
  Coord(
    size: 40_320,
    get: fn(c) { rank_perm(list.take(arr.to_list(c.ep), 8)) },
    set: fn(r) {
      with(
        cp: identity(8),
        co: zeros(8),
        ep: list.append(unrank_perm(r, 8), [8, 9, 10, 11]),
        eo: zeros(12),
      )
    },
  )
}

pub fn slice_perm() -> Coord {
  Coord(
    size: 24,
    get: fn(c) {
      rank_perm(arr.to_list(c.ep) |> list.drop(8) |> list.map(fn(e) { e - 8 }))
    },
    set: fn(r) {
      with(
        cp: identity(8),
        co: zeros(8),
        ep: list.append(
          identity(8),
          unrank_perm(r, 4) |> list.map(fn(e) { e + 8 }),
        ),
        eo: zeros(12),
      )
    },
  )
}
