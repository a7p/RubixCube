//// Umrechnung zwischen den 54 Aufklebern ("Facelets") und dem Würfelzustand.
////
//// Reihenfolge der Aufkleber: U1–U9, R1–R9, F1–F9, D1–D9, L1–L9, B1–B9.
//// Jeder Aufkleber trägt als Wert die Seite, zu deren Mittelfarbe er gehört.

import gleam/int
import gleam/list
import gleam/result
import gleam/string
import rubixcube/arr.{type Arr}
import rubixcube/cube.{type Cube, type Face, B, Cube, D, F, L, R, U}
import rubixcube/seq

pub type Facelets =
  Arr(Face)

pub type CubeError {
  /// Eine Farbe kommt nicht genau neunmal vor.
  WrongColourCount(face: Face, count: Int)
  /// Eine Ecke zeigt keine Weiß-/Gelb-Fläche.
  CornerWithoutUpDown
  ImpossibleCorner
  ImpossibleEdge
  DuplicateCorner
  DuplicateEdge
  TwistedEdge
  TwistedCorner
  SwappedPieces
}

pub fn describe(error: CubeError) -> String {
  case error {
    WrongColourCount(face, count) ->
      "Jede Farbe muss genau 9-mal vorkommen ("
      <> cube.colour_name(face)
      <> " kommt "
      <> int.to_string(count)
      <> "-mal vor)."
    CornerWithoutUpDown ->
      "Eine Ecke enthält weder Weiß noch Gelb – das gibt es nicht."
    ImpossibleCorner ->
      "Eine Ecke hat eine Farbkombination, die es an einem echten Würfel nicht gibt."
    ImpossibleEdge ->
      "Eine Kante hat eine Farbkombination, die es an einem echten Würfel nicht gibt."
    DuplicateCorner -> "Eine Ecke kommt doppelt vor (und eine andere fehlt)."
    DuplicateEdge -> "Eine Kante kommt doppelt vor (und eine andere fehlt)."
    TwistedEdge ->
      "Eine Kante ist falsch herum gedreht (Kanten-Orientierung ungültig)."
    TwistedCorner -> "Eine Ecke ist verdreht (Ecken-Orientierung ungültig)."
    SwappedPieces ->
      "Zwei Steine sind vertauscht – ein echter Würfel lässt sich so nicht erreichen."
  }
}

// ---------------------------------------------------------------- Tabellen

/// Aufkleber-Positionen der 8 Ecken (URF, UFL, ULB, UBR, DFR, DLF, DBL, DRB).
const corner_facelets = [
  [8, 9, 20],
  [6, 18, 38],
  [0, 36, 47],
  [2, 45, 11],
  [29, 26, 15],
  [27, 44, 24],
  [33, 53, 42],
  [35, 17, 51],
]

/// Aufkleber-Positionen der 12 Kanten
/// (UR, UF, UL, UB, DR, DF, DL, DB, FR, FL, BL, BR).
const edge_facelets = [
  [5, 10],
  [7, 19],
  [3, 37],
  [1, 46],
  [32, 16],
  [28, 25],
  [30, 43],
  [34, 52],
  [23, 12],
  [21, 41],
  [50, 39],
  [48, 14],
]

const corner_colours = [
  [U, R, F],
  [U, F, L],
  [U, L, B],
  [U, B, R],
  [D, F, R],
  [D, L, F],
  [D, B, L],
  [D, R, B],
]

const edge_colours = [
  [U, R],
  [U, F],
  [U, L],
  [U, B],
  [D, R],
  [D, F],
  [D, L],
  [D, B],
  [F, R],
  [F, L],
  [B, L],
  [B, R],
]

// ---------------------------------------------------------------- Konstruktion

pub fn solved() -> Facelets {
  arr.generate(54, fn(i) { cube.face_from_index(i / 9) })
}

/// Facelets -> Würfelzustand, mit Prüfung auf Lösbarkeit.
pub fn to_cube(facelets: Facelets) -> Result(Cube, CubeError) {
  use _ <- result.try(check_counts(facelets))
  use corners <- result.try(
    seq.upto(8) |> list.try_map(read_corner(facelets, _)),
  )
  use edges <- result.try(seq.upto(12) |> list.try_map(read_edge(facelets, _)))
  let #(cp, co) = list.unzip(corners)
  let #(ep, eo) = list.unzip(edges)
  use _ <- result.try(all_different(cp, 8, DuplicateCorner))
  use _ <- result.try(all_different(ep, 12, DuplicateEdge))
  let cube =
    Cube(
      arr.from_list(cp),
      arr.from_list(co),
      arr.from_list(ep),
      arr.from_list(eo),
    )
  verify(cube) |> result.replace(cube)
}

fn check_counts(facelets: Facelets) -> Result(Nil, CubeError) {
  cube.faces
  |> list.try_each(fn(face) {
    let count = arr.count(facelets, fn(f) { f == face })
    case count == 9 {
      True -> Ok(Nil)
      False -> Error(WrongColourCount(face, count))
    }
  })
}

fn all_different(
  ids: List(Int),
  n: Int,
  error: CubeError,
) -> Result(Nil, CubeError) {
  case list.sort(ids, int.compare) == seq.upto(n) {
    True -> Ok(Nil)
    False -> Error(error)
  }
}

fn colour_at(facelets: Facelets, position: Int) -> Face {
  arr.at(facelets, position)
}

fn is_up_down(face: Face) -> Bool {
  face == U || face == D
}

/// Ecke auf Platz `slot`: (welche Ecke, Orientierung)
fn read_corner(
  facelets: Facelets,
  slot: Int,
) -> Result(#(Int, Int), CubeError) {
  let positions = nth(corner_facelets, slot)
  let colours = list.map(positions, colour_at(facelets, _))
  // Orientierung = Index des Aufklebers mit Weiß/Gelb
  use orientation <- result.try(
    colours
    |> list.index_map(fn(c, i) { #(c, i) })
    |> list.find(fn(pair) { is_up_down(pair.0) })
    |> result.map(fn(pair) { pair.1 })
    |> result.replace_error(CornerWithoutUpDown),
  )
  let second = nth(colours, { orientation + 1 } % 3)
  let third = nth(colours, { orientation + 2 } % 3)
  corner_colours
  |> list.index_map(fn(cs, id) { #(cs, id) })
  |> list.find(fn(pair) { nth(pair.0, 1) == second && nth(pair.0, 2) == third })
  |> result.map(fn(pair) { #(pair.1, orientation) })
  |> result.replace_error(ImpossibleCorner)
}

fn read_edge(facelets: Facelets, slot: Int) -> Result(#(Int, Int), CubeError) {
  let positions = nth(edge_facelets, slot)
  let a = colour_at(facelets, nth(positions, 0))
  let b = colour_at(facelets, nth(positions, 1))
  edge_colours
  |> list.index_map(fn(cs, id) { #(cs, id) })
  |> list.find_map(fn(pair) {
    let #(cs, id) = pair
    case
      nth(cs, 0) == a && nth(cs, 1) == b,
      nth(cs, 0) == b && nth(cs, 1) == a
    {
      True, _ -> Ok(#(id, 0))
      _, True -> Ok(#(id, 1))
      _, _ -> Error(Nil)
    }
  })
  |> result.replace_error(ImpossibleEdge)
}

fn nth(items: List(a), index: Int) -> a {
  let assert Ok(item) = items |> list.drop(index) |> list.first
  item
}

/// Ist der Würfelzustand physikalisch erreichbar?
pub fn verify(cube: Cube) -> Result(Nil, CubeError) {
  case
    cube.sum(cube.eo) % 2,
    cube.sum(cube.co) % 3,
    cube.parity(arr.to_list(cube.ep)) == cube.parity(arr.to_list(cube.cp))
  {
    1, _, _ -> Error(TwistedEdge)
    _, c, _ if c != 0 -> Error(TwistedCorner)
    _, _, False -> Error(SwappedPieces)
    _, _, _ -> Ok(Nil)
  }
}

// ---------------------------------------------------------------- Rückweg

/// Würfelzustand -> Aufkleber.
pub fn from_cube(cube: Cube) -> Facelets {
  let centres =
    seq.upto(6) |> list.map(fn(i) { #(9 * i + 4, cube.face_from_index(i)) })
  let corner_stickers =
    seq.upto(8)
    |> list.flat_map(fn(slot) {
      let piece = arr.at(cube.cp, slot)
      let twist = arr.at(cube.co, slot)
      seq.upto(3)
      |> list.map(fn(n) {
        #(
          nth(nth(corner_facelets, slot), { n + twist } % 3),
          nth(nth(corner_colours, piece), n),
        )
      })
    })
  let edge_stickers =
    seq.upto(12)
    |> list.flat_map(fn(slot) {
      let piece = arr.at(cube.ep, slot)
      let flip = arr.at(cube.eo, slot)
      seq.upto(2)
      |> list.map(fn(n) {
        #(
          nth(nth(edge_facelets, slot), { n + flip } % 2),
          nth(nth(edge_colours, piece), n),
        )
      })
    })
  let placed =
    list.flatten([centres, corner_stickers, edge_stickers])
    |> list.sort(fn(a, b) { int.compare(a.0, b.0) })
    |> list.map(fn(pair) { pair.1 })
  arr.from_list(placed)
}

/// Einen Zug auf Aufkleber anwenden (nur für gültige Zustände).
pub fn apply_move(facelets: Facelets, move: cube.Move) -> Facelets {
  case to_cube(facelets) {
    Ok(c) -> from_cube(cube.apply_move(c, move))
    Error(_) -> facelets
  }
}

pub fn from_string(s: String) -> Result(Facelets, Nil) {
  use faces <- result.try(
    s
    |> string.to_graphemes
    |> list.try_map(cube.face_from_string),
  )
  case list.length(faces) {
    54 -> Ok(arr.from_list(faces))
    _ -> Error(Nil)
  }
}

pub fn to_string(facelets: Facelets) -> String {
  facelets |> arr.to_list |> list.map(cube.face_to_string) |> string.concat
}
