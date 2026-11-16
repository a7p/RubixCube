//// Kleine Hilfen für Zahlenfolgen.

import gleam/int
import gleam/list

/// [0, 1, …, n-1] (leer für n <= 0)
pub fn upto(n: Int) -> List(Int) {
  case n <= 0 {
    True -> []
    False ->
      int.range(from: 0, to: n, with: [], run: fn(acc, i) { [i, ..acc] })
      |> list.reverse
  }
}

/// [a, a+1, …, b] (leer für b < a)
pub fn between(a: Int, b: Int) -> List(Int) {
  upto(b - a + 1) |> list.map(fn(i) { i + a })
}

pub fn pow(base: Int, exponent: Int) -> Int {
  case exponent <= 0 {
    True -> 1
    False -> base * pow(base, exponent - 1)
  }
}
