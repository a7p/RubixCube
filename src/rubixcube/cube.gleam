//// Das Würfelmodell: Seiten, Züge und der Zustand als Permutation + Orientierung
//// der 8 Ecken und 12 Kanten ("Cubie-Level"-Darstellung).

import gleam/int
import gleam/list
import gleam/result
import gleam/string
import rubixcube/arr.{type Arr}
import rubixcube/seq

// ---------------------------------------------------------------- Seiten

pub type Face {
  U
  R
  F
  D
  L
  B
}

/// Reihenfolge, wie sie auch im Facelet-String und bei den Zugnummern gilt.
pub const faces = [U, R, F, D, L, B]

pub fn face_index(face: Face) -> Int {
  case face {
    U -> 0
    R -> 1
    F -> 2
    D -> 3
    L -> 4
    B -> 5
  }
}

pub fn face_from_index(index: Int) -> Face {
  case index {
    0 -> U
    1 -> R
    2 -> F
    3 -> D
    4 -> L
    _ -> B
  }
}

pub fn face_to_string(face: Face) -> String {
  case face {
    U -> "U"
    R -> "R"
    F -> "F"
    D -> "D"
    L -> "L"
    B -> "B"
  }
}

pub fn face_from_string(s: String) -> Result(Face, Nil) {
  case s {
    "U" -> Ok(U)
    "R" -> Ok(R)
    "F" -> Ok(F)
    "D" -> Ok(D)
    "L" -> Ok(L)
    "B" -> Ok(B)
    _ -> Error(Nil)
  }
}

/// Deutscher Farbname der Seite (Standard-Farbschema: Weiß oben, Grün vorne).
pub fn colour_name(face: Face) -> String {
  case face {
    U -> "Weiß"
    R -> "Rot"
    F -> "Grün"
    D -> "Gelb"
    L -> "Orange"
    B -> "Blau"
  }
}

pub fn face_name(face: Face) -> String {
  case face {
    U -> "obere Seite"
    D -> "untere Seite"
    F -> "vordere Seite"
    B -> "hintere Seite"
    L -> "linke Seite"
    R -> "rechte Seite"
  }
}

/// Drehung des ganzen Würfels um 180° um die Links-Rechts-Achse: tauscht oben/unten
/// und vorne/hinten. So lassen sich klassische Zugfolgen ("erste Ebene unten") auf
/// "erste Ebene oben" übertragen.
pub fn flip_x2(face: Face) -> Face {
  case face {
    U -> D
    D -> U
    F -> B
    B -> F
    other -> other
  }
}

// ---------------------------------------------------------------- Züge

pub type Turn {
  Clockwise
  Half
  CounterClockwise
}

pub type Move {
  Move(face: Face, turn: Turn)
}

fn turn_index(turn: Turn) -> Int {
  case turn {
    Clockwise -> 0
    Half -> 1
    CounterClockwise -> 2
  }
}

/// Nummer 0..17: drei Züge je Seite.
pub fn move_index(move: Move) -> Int {
  3 * face_index(move.face) + turn_index(move.turn)
}

pub fn move_from_index(index: Int) -> Move {
  let turn = case index % 3 {
    0 -> Clockwise
    1 -> Half
    _ -> CounterClockwise
  }
  Move(face_from_index(index / 3), turn)
}

pub fn all_moves() -> List(Move) {
  seq.upto(18) |> list.map(move_from_index)
}

pub fn move_to_string(move: Move) -> String {
  face_to_string(move.face)
  <> case move.turn {
    Clockwise -> ""
    Half -> "2"
    CounterClockwise -> "'"
  }
}

pub fn parse_move(s: String) -> Result(Move, Nil) {
  use #(first, rest) <- result.try(string.pop_grapheme(s))
  use face <- result.try(face_from_string(first))
  case rest {
    "" -> Ok(Move(face, Clockwise))
    "2" -> Ok(Move(face, Half))
    "'" -> Ok(Move(face, CounterClockwise))
    _ -> Error(Nil)
  }
}

/// "R U R' U'" -> Liste von Zügen. Ungültige Eingaben sind ein Programmierfehler.
pub fn parse_alg(alg: String) -> List(Move) {
  alg
  |> string.split(" ")
  |> list.filter(fn(token) { token != "" })
  |> list.map(fn(token) {
    let assert Ok(move) = parse_move(token)
    move
  })
}

pub fn invert(move: Move) -> Move {
  let turn = case move.turn {
    Clockwise -> CounterClockwise
    Half -> Half
    CounterClockwise -> Clockwise
  }
  Move(move.face, turn)
}

pub fn invert_alg(moves: List(Move)) -> List(Move) {
  moves |> list.reverse |> list.map(invert)
}

pub fn flip_move(move: Move) -> Move {
  Move(flip_x2(move.face), move.turn)
}

// ---------------------------------------------------------------- Zustand

/// cp/ep: welches Teil sitzt auf Platz i; co/eo: wie ist es gedreht.
pub type Cube {
  Cube(cp: Arr(Int), co: Arr(Int), ep: Arr(Int), eo: Arr(Int))
}

fn ints(values: List(Int)) -> Arr(Int) {
  arr.from_list(values)
}

fn zeros(n: Int) -> Arr(Int) {
  arr.generate(n, fn(_) { 0 })
}

pub fn solved() -> Cube {
  Cube(
    cp: arr.generate(8, fn(i) { i }),
    co: zeros(8),
    ep: arr.generate(12, fn(i) { i }),
    eo: zeros(12),
  )
}

/// Hintereinanderausführung: erst `a`, dann `b`.
pub fn multiply(a: Cube, b: Cube) -> Cube {
  Cube(
    cp: arr.generate(8, fn(i) { arr.at(a.cp, arr.at(b.cp, i)) }),
    co: arr.generate(8, fn(i) {
      { arr.at(a.co, arr.at(b.cp, i)) + arr.at(b.co, i) } % 3
    }),
    ep: arr.generate(12, fn(i) { arr.at(a.ep, arr.at(b.ep, i)) }),
    eo: arr.generate(12, fn(i) {
      { arr.at(a.eo, arr.at(b.ep, i)) + arr.at(b.eo, i) } % 2
    }),
  )
}

pub fn equal(a: Cube, b: Cube) -> Bool {
  arr.to_list(a.cp) == arr.to_list(b.cp)
  && arr.to_list(a.co) == arr.to_list(b.co)
  && arr.to_list(a.ep) == arr.to_list(b.ep)
  && arr.to_list(a.eo) == arr.to_list(b.eo)
}

pub fn is_solved(cube: Cube) -> Bool {
  equal(cube, solved())
}

/// Die Viertelzüge der sechs Seiten als Würfelzustände.
fn quarter_turn(face: Face) -> Cube {
  case face {
    U ->
      Cube(
        ints([3, 0, 1, 2, 4, 5, 6, 7]),
        zeros(8),
        ints([3, 0, 1, 2, 4, 5, 6, 7, 8, 9, 10, 11]),
        zeros(12),
      )
    R ->
      Cube(
        ints([4, 1, 2, 0, 7, 5, 6, 3]),
        ints([2, 0, 0, 1, 1, 0, 0, 2]),
        ints([8, 1, 2, 3, 11, 5, 6, 7, 4, 9, 10, 0]),
        zeros(12),
      )
    F ->
      Cube(
        ints([1, 5, 2, 3, 0, 4, 6, 7]),
        ints([1, 2, 0, 0, 2, 1, 0, 0]),
        ints([0, 9, 2, 3, 4, 8, 6, 7, 1, 5, 10, 11]),
        ints([0, 1, 0, 0, 0, 1, 0, 0, 1, 1, 0, 0]),
      )
    D ->
      Cube(
        ints([0, 1, 2, 3, 5, 6, 7, 4]),
        zeros(8),
        ints([0, 1, 2, 3, 5, 6, 7, 4, 8, 9, 10, 11]),
        zeros(12),
      )
    L ->
      Cube(
        ints([0, 2, 6, 3, 4, 1, 5, 7]),
        ints([0, 1, 2, 0, 0, 2, 1, 0]),
        ints([0, 1, 10, 3, 4, 5, 9, 7, 8, 2, 6, 11]),
        zeros(12),
      )
    B ->
      Cube(
        ints([0, 1, 3, 7, 4, 5, 2, 6]),
        ints([0, 0, 1, 2, 0, 0, 2, 1]),
        ints([0, 1, 2, 11, 4, 5, 6, 10, 8, 9, 3, 7]),
        ints([0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 1, 1]),
      )
  }
}

/// Der Würfelzustand, den ein einzelner Zug bewirkt.
pub fn move_cube(move: Move) -> Cube {
  let quarter = quarter_turn(move.face)
  case move.turn {
    Clockwise -> quarter
    Half -> multiply(quarter, quarter)
    CounterClockwise -> multiply(multiply(quarter, quarter), quarter)
  }
}

/// Alle 18 Züge als Array (Index = `move_index`), für schnelle Tabellenberechnung.
pub fn move_cubes() -> Arr(Cube) {
  arr.generate(18, fn(i) { move_cube(move_from_index(i)) })
}

pub fn apply_move(cube: Cube, move: Move) -> Cube {
  multiply(cube, move_cube(move))
}

pub fn apply(cube: Cube, moves: List(Move)) -> Cube {
  list.fold(moves, cube, apply_move)
}

/// Der Zustand, den eine ganze Zugfolge bewirkt.
pub fn from_moves(moves: List(Move)) -> Cube {
  apply(solved(), moves)
}

// ---------------------------------------------------------------- Teile suchen

/// Auf welchem Platz sitzt Ecke `id`?
pub fn corner_position(cube: Cube, id: Int) -> Int {
  arr.find_index(cube.cp, fn(p) { p == id })
}

pub fn edge_position(cube: Cube, id: Int) -> Int {
  arr.find_index(cube.ep, fn(p) { p == id })
}

/// Parität einer Permutation (0 gerade, 1 ungerade).
pub fn parity(perm: List(Int)) -> Int {
  case perm {
    [] -> 0
    [x, ..rest] -> { list.count(rest, fn(y) { y < x }) + parity(rest) } % 2
  }
}

pub fn sum(values: Arr(Int)) -> Int {
  arr.to_list(values) |> int.sum
}
