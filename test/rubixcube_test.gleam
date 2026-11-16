import gleam/list
import gleeunit
import rubixcube/arr
import rubixcube/coords
import rubixcube/cube.{type Move}
import rubixcube/facelets
import rubixcube/learn
import rubixcube/seq
import rubixcube/twophase

pub fn main() -> Nil {
  gleeunit.main()
}

/// Deterministischer Pseudo-Zufall (LCG) für reproduzierbare Mischungen.
fn scramble(seed: Int, length: Int) -> List(Move) {
  let #(moves, _) =
    seq.upto(length)
    |> list.fold(#([], seed), fn(acc, _) {
      let #(moves, state) = acc
      let state = { state * 1_103_515_245 + 12_345 } % 2_147_483_648
      #([cube.move_from_index({ state / 65_536 } % 18), ..moves], state)
    })
  moves
}

// ---------------------------------------------------------------- Würfelmodell

pub fn every_move_has_order_four_test() {
  cube.faces
  |> list.each(fn(face) {
    let quarter = cube.Move(face, cube.Clockwise)
    assert cube.is_solved(cube.from_moves([quarter, quarter, quarter, quarter]))
  })
}

pub fn inverse_undoes_move_test() {
  let moves = scramble(3, 25)
  assert cube.is_solved(
    cube.from_moves(list.append(moves, cube.invert_alg(moves))),
  )
}

pub fn parse_and_print_moves_test() {
  let alg = "R U R' U' F2 D' L B2"
  assert cube.parse_alg(alg)
    |> list.map(cube.move_to_string)
    |> list.fold("", fn(acc, m) {
      case acc {
        "" -> m
        _ -> acc <> " " <> m
      }
    })
    == alg
}

// ---------------------------------------------------------------- Aufkleber

pub fn u_move_moves_the_top_rows_test() {
  // Obere Reihe von F wandert nach L, von R nach F, von B nach R, von L nach B.
  let after =
    facelets.apply_move(facelets.solved(), cube.Move(cube.U, cube.Clockwise))
  assert facelets.to_string(after)
    == "UUUUUUUUU"
    <> "BBBRRRRRR"
    <> "RRRFFFFFF"
    <> "DDDDDDDDD"
    <> "FFFLLLLLL"
    <> "LLLBBBBBB"
}

pub fn facelets_round_trip_test() {
  let c = cube.from_moves(scramble(7, 30))
  let assert Ok(back) = facelets.to_cube(facelets.from_cube(c))
  assert cube.equal(c, back)
}

pub fn wrong_colour_count_is_rejected_test() {
  let stickers = arr.set(facelets.solved(), 0, cube.R)
  assert facelets.to_cube(stickers)
    == Error(facelets.WrongColourCount(cube.U, 8))
}

pub fn single_twisted_corner_is_rejected_test() {
  // Eine Ecke auf der Stelle URF verdrehen: Aufkleber (U9, R1, F3) rotieren.
  let stickers =
    facelets.solved()
    |> arr.set(8, cube.R)
    |> arr.set(9, cube.F)
    |> arr.set(20, cube.U)
  assert facelets.to_cube(stickers) == Error(facelets.TwistedCorner)
}

pub fn swapped_edges_are_rejected_test() {
  // Zwei Kanten vertauscht (UF <-> UR), sonst nichts: unlösbar (Parität).
  let stickers =
    facelets.solved()
    |> arr.set(7, cube.U)
    |> arr.set(19, cube.R)
    |> arr.set(5, cube.U)
    |> arr.set(10, cube.F)
  assert facelets.to_cube(stickers) == Error(facelets.SwappedPieces)
}

// ---------------------------------------------------------------- Koordinaten

pub fn permutation_rank_round_trip_test() {
  seq.upto(24)
  |> list.each(fn(rank) {
    assert coords.rank_perm(coords.unrank_perm(rank, 4)) == rank
  })
}

pub fn coordinates_round_trip_test() {
  let c = cube.from_moves(scramble(11, 30))
  let twist = coords.twist()
  let flip = coords.flip()
  let slice = coords.slice()
  assert twist.get(twist.set(twist.get(c))) == twist.get(c)
  assert flip.get(flip.set(flip.get(c))) == flip.get(c)
  assert slice.get(slice.set(slice.get(c))) == slice.get(c)
  assert slice.get(cube.solved()) == 494
}

// ---------------------------------------------------------------- Löser

pub fn two_phase_solves_random_cubes_test() {
  let tables = twophase.build()
  seq.upto(12)
  |> list.each(fn(i) {
    let start = cube.from_moves(scramble(i * 7919 + 1, 40))
    let assert Ok(solution) = twophase.solve(tables, start, 200)
    assert cube.is_solved(cube.apply(start, solution.moves))
    assert list.length(solution.moves) <= 30
  })
}

pub fn two_phase_on_solved_cube_needs_no_moves_test() {
  let tables = twophase.build()
  let assert Ok(solution) = twophase.solve(tables, cube.solved(), 0)
  assert solution.moves == []
}

pub fn learn_mode_solves_random_cubes_test() {
  let prepared = learn.prepare()
  seq.upto(25)
  |> list.each(fn(i) {
    let start = cube.from_moves(scramble(i * 104_729 + 5, 40))
    let assert Ok(plan) = learn.solve(prepared, start)
    assert cube.is_solved(cube.apply(start, plan.moves))
    // jeder Zug hat Hinweise, und die Stufen decken alle Züge ab
    assert list.length(plan.infos) == list.length(plan.moves)
    assert list.fold(plan.stages, 0, fn(acc, s) { acc + s.count })
      == list.length(plan.moves)
  })
}

pub fn learn_mode_on_solved_cube_has_no_moves_test() {
  let assert Ok(plan) = learn.solve(learn.prepare(), cube.solved())
  assert plan.moves == []
}
