//// Lernmodus: die Anfängermethode (Schicht für Schicht) mit Erklärungen.
////
//// Weiß liegt oben (erste Ebene), Gelb unten (letzte Ebene); der Würfel muss nie
//// gedreht werden. Die klassischen Zugfolgen sind für "erste Ebene unten" notiert
//// und werden mit `cube.flip_x2` (U<->D, F<->B) übertragen.
////
//// Jede Stufe sucht die nötigen "Bausteine" (kurze, bekannte Zugfolgen plus
//// Drehungen der letzten Ebene) mit einer kleinen Kürzeste-Wege-Suche.

import gleam/dict.{type Dict}
import gleam/int
import gleam/list
import gleam/result
import gleam/string
import rubixcube/arr.{type Arr}
import rubixcube/cube.{type Cube, type Face, type Move}
import rubixcube/seq
import rubixcube/table.{type Bytes}

// ---------------------------------------------------------------- Datentypen

pub type Tag {
  CrossEdge
  Align
  CornerBlock
  EdgeRight
  EdgeLeft
  CrossBlock
  CornerTwist
  CornerCycle
  EdgeCycle
}

/// Ein Baustein: zusammengehörige Züge mit Erklärung.
pub type Block {
  Block(moves: List(Move), tag: Tag, note: String)
}

/// Ein Schritt = ein Teil, das an seinen Platz kommt (oder eine Aufgabe der Stufe).
pub type Step {
  Step(title: String, why: String, blocks: List(Block))
}

pub type Stage {
  Stage(title: String, intro: String, steps: List(Step))
}

/// Informationen zu einem einzelnen Zug – für die Anzeige.
pub type MoveInfo {
  MoveInfo(
    stage: Int,
    step_title: String,
    why: String,
    block: Int,
    position: Int,
    block_length: Int,
    note: String,
    tag: Tag,
  )
}

pub type StageSummary {
  StageSummary(title: String, intro: String, first: Int, count: Int)
}

/// Die fertige Anleitung: Züge, Infos je Zug, Übersicht der Stufen.
pub type Plan {
  Plan(moves: List(Move), infos: List(MoveInfo), stages: List(StageSummary))
}

/// Vorberechnete Tabellen (einmal aufbauen, dann beliebig oft lösen).
pub type Prepared {
  Prepared(cross: List(Bytes), cubes: Arr(Cube), edge_from: Arr(Arr(Int)))
}

// ---------------------------------------------------------------- Teile

fn faces_of(letters: String) -> List(Face) {
  letters
  |> string.to_graphemes
  |> list.filter_map(cube.face_from_string)
}

const corner_names = ["URF", "UFL", "ULB", "UBR", "DFR", "DLF", "DBL", "DRB"]

const edge_names = [
  "UR", "UF", "UL", "UB", "DR", "DF", "DL", "DB", "FR", "FL", "BL", "BR",
]

fn same_faces(a: List(Face), b: List(Face)) -> Bool {
  let order = fn(faces) {
    list.sort(faces, fn(x, y) {
      int.compare(cube.face_index(x), cube.face_index(y))
    })
  }
  order(a) == order(b)
}

fn index_of(names: List(String), faces: List(Face)) -> Int {
  let found =
    names
    |> list.index_map(fn(name, i) { #(i, faces_of(name)) })
    |> list.find(fn(pair) { same_faces(pair.1, faces) })
  case found {
    Ok(#(i, _)) -> i
    Error(_) -> 0
  }
}

/// Ecke/Kante, die in der "Standardlage" (erste Ebene unten) an den Seiten `letters` sitzt,
/// als Teil-Nummer im tatsächlichen Würfel (erste Ebene oben).
fn real_corner(std_letters: String) -> Int {
  index_of(corner_names, faces_of(std_letters) |> list.map(cube.flip_x2))
}

fn real_edge(std_letters: String) -> Int {
  index_of(edge_names, faces_of(std_letters) |> list.map(cube.flip_x2))
}

fn name_of(names: List(String), id: Int) -> String {
  let assert Ok(letters) = names |> list.drop(id) |> list.first
  faces_of(letters) |> list.map(cube.colour_name) |> string.join("-")
}

fn corner_name(id: Int) -> String {
  name_of(corner_names, id)
}

fn edge_name(id: Int) -> String {
  name_of(edge_names, id)
}

fn corner_state(c: Cube, id: Int) -> #(Int, Int) {
  let p = cube.corner_position(c, id)
  #(p, arr.at(c.co, p))
}

fn edge_state(c: Cube, id: Int) -> #(Int, Int) {
  let p = cube.edge_position(c, id)
  #(p, arr.at(c.eo, p))
}

fn corner_key(ids: List(Int)) -> fn(Cube) -> Int {
  fn(c) {
    list.fold(ids, 0, fn(k, id) {
      let #(p, o) = corner_state(c, id)
      k * 24 + p * 3 + o
    })
  }
}

fn edge_key(ids: List(Int)) -> fn(Cube) -> Int {
  fn(c) {
    list.fold(ids, 0, fn(k, id) {
      let #(p, o) = edge_state(c, id)
      k * 24 + p * 2 + o
    })
  }
}

fn corner_home(c: Cube, id: Int) -> Bool {
  corner_state(c, id) == #(id, 0)
}

fn edge_home(c: Cube, id: Int) -> Bool {
  edge_state(c, id) == #(id, 0)
}

// ---------------------------------------------------------------- Stufe 1: Kreuz (Tabellen)

/// Die vier Kreuzkanten in der Reihenfolge, in der sie gelöst werden: UF, UR, UB, UL.
const cross_edges = [1, 0, 3, 2]

fn edge_piece_step(prepared: Prepared, state: Int, move: Int) -> Int {
  // state = Platz * 2 + Orientierung
  let position = state / 2
  let orientation = state % 2
  let new_position = arr.at(arr.at(prepared.edge_from, move), position)
  let flip = arr.at(arr.at(prepared.cubes, move).eo, new_position)
  new_position * 2 + { orientation + flip } % 2
}

/// Zustand der ersten n Kreuzkanten als Zahl (Basis 24, Kante 0 niedrigstwertig).
fn cross_step(prepared: Prepared, pieces: Int) -> fn(Int, Int) -> Int {
  fn(key, move) {
    seq.upto(pieces)
    |> list.fold(0, fn(acc, i) {
      let state = { key / seq.pow(24, i) } % 24
      acc + edge_piece_step(prepared, state, move) * seq.pow(24, i)
    })
  }
}

fn cross_goal(pieces: Int) -> Int {
  cross_edges
  |> list.take(pieces)
  |> list.index_fold(0, fn(acc, id, i) { acc + id * 2 * seq.pow(24, i) })
}

fn cross_state_key(c: Cube, pieces: Int) -> Int {
  cross_edges
  |> list.take(pieces)
  |> list.index_fold(0, fn(acc, id, i) {
    let #(p, o) = edge_state(c, id)
    acc + { p * 2 + o } * seq.pow(24, i)
  })
}

/// Tabellen aufbauen (ca. eine Sekunde).
pub fn prepare() -> Prepared {
  let cubes = cube.move_cubes()
  let edge_from =
    arr.generate(18, fn(m) {
      let move_cube = arr.at(cubes, m)
      arr.generate(12, fn(p) {
        arr.find_index(move_cube.ep, fn(from) { from == p })
      })
    })
  let base = Prepared(cross: [], cubes: cubes, edge_from: edge_from)
  let tables =
    [1, 2, 3, 4]
    |> list.map(fn(pieces) {
      table.bfs(
        size: seq.pow(24, pieces),
        goal: cross_goal(pieces),
        branching: 18,
        step: cross_step(base, pieces),
      )
    })
  Prepared(..base, cross: tables)
}

/// Kürzester Weg, um die Kreuzkante Nr. `k` (0..3) einzusetzen, ohne die vorigen zu stören.
fn solve_cross_edge(
  prepared: Prepared,
  c: Cube,
  k: Int,
) -> #(List(Move), Cube) {
  let pieces = k + 1
  let assert Ok(dist) = prepared.cross |> list.drop(k) |> list.first
  descend(prepared, dist, pieces, c, [])
}

fn descend(
  prepared: Prepared,
  dist: Bytes,
  pieces: Int,
  c: Cube,
  moves: List(Move),
) -> #(List(Move), Cube) {
  let d = table.bytes_get(dist, cross_state_key(c, pieces))
  case d {
    0 -> #(list.reverse(moves), c)
    _ -> {
      let next =
        seq.upto(18)
        |> list.find_map(fn(m) {
          let candidate = cube.multiply(c, arr.at(prepared.cubes, m))
          case
            table.bytes_get(dist, cross_state_key(candidate, pieces)) == d - 1
          {
            True -> Ok(#(cube.move_from_index(m), candidate))
            False -> Error(Nil)
          }
        })
      case next {
        Ok(#(move, candidate)) ->
          descend(prepared, dist, pieces, candidate, [move, ..moves])
        // kann bei gültigen Würfeln nicht vorkommen
        Error(_) -> #(list.reverse(moves), c)
      }
    }
  }
}

// ---------------------------------------------------------------- Kürzeste-Wege-Suche über Bausteine

/// Ein Baustein im Suchalphabet: Zugfolge, ihre Wirkung, Art und Platz ("slot"), den er betrifft.
type Alpha {
  Alpha(moves: List(Move), effect: Cube, tag: Tag, slot: Int)
}

/// Ein angewendeter Baustein samt Würfelzustand davor (für die Erklärungstexte).
type Applied {
  Applied(alpha: Alpha, before: Cube)
}

type Node {
  Node(cube: Cube, cost: Int, key: Int, trail: List(Applied))
}

/// Baustein aus klassischer Notation ("erste Ebene unten") für unseren Würfel.
fn alpha(std_alg: String, tag: Tag, slot: Int) -> Alpha {
  let moves = cube.parse_alg(std_alg) |> list.map(cube.flip_move)
  Alpha(moves, cube.from_moves(moves), tag, slot)
}

/// Die drei Drehungen der letzten Ebene zum Ausrichten.
fn turns() -> List(Alpha) {
  ["U", "U'", "U2"] |> list.map(alpha(_, Align, -1))
}

fn pop_min(nodes: List(Node)) -> Result(#(Node, List(Node)), Nil) {
  case nodes {
    [] -> Error(Nil)
    [first, ..rest] ->
      Ok(
        list.fold(rest, #(first, []), fn(acc, node) {
          let #(min, others) = acc
          case node.cost < min.cost {
            True -> #(node, [min, ..others])
            False -> #(min, [node, ..others])
          }
        }),
      )
  }
}

const search_limit = 60_000

/// Dijkstra mit Kosten = Anzahl Züge. Findet die günstigste Baustein-Folge
/// vom Start zu einem Zustand, der `goal` erfüllt. Zustände gelten als gleich,
/// wenn `key` übereinstimmt (nur die für das Ziel wichtigen Teile).
fn shortest_blocks(
  start: Cube,
  alphabet: List(Alpha),
  key: fn(Cube) -> Int,
  goal: fn(Cube) -> Bool,
) -> Result(List(Applied), Nil) {
  let first = Node(start, 0, key(start), [])
  search(alphabet, key, goal, [first], dict.from_list([#(first.key, 0)]), 0)
}

fn search(
  alphabet: List(Alpha),
  key: fn(Cube) -> Int,
  goal: fn(Cube) -> Bool,
  open: List(Node),
  best: Dict(Int, Int),
  visited: Int,
) -> Result(List(Applied), Nil) {
  use #(node, rest) <- result.try(pop_min(open))
  let stale = case dict.get(best, node.key) {
    Ok(cost) -> node.cost > cost
    Error(_) -> False
  }
  case stale, goal(node.cube), visited > search_limit {
    _, _, True -> Error(Nil)
    True, _, _ -> search(alphabet, key, goal, rest, best, visited)
    False, True, _ -> Ok(list.reverse(node.trail))
    False, False, _ -> {
      let #(open, best) =
        list.fold(alphabet, #(rest, best), fn(acc, a) {
          let #(open, best) = acc
          let next = cube.multiply(node.cube, a.effect)
          let next_key = key(next)
          let cost = node.cost + list.length(a.moves)
          let improves = case dict.get(best, next_key) {
            Ok(known) -> cost < known
            Error(_) -> True
          }
          case improves {
            False -> acc
            True -> #(
              [
                Node(next, cost, next_key, [Applied(a, node.cube), ..node.trail]),
                ..open
              ],
              dict.insert(best, next_key, cost),
            )
          }
        })
      search(alphabet, key, goal, open, best, visited + 1)
    }
  }
}

fn to_blocks(
  path: List(Applied),
  note: fn(Alpha, Cube) -> String,
) -> List(Block) {
  list.map(path, fn(applied) {
    Block(
      applied.alpha.moves,
      applied.alpha.tag,
      note(applied.alpha, applied.before),
    )
  })
}

fn advance(c: Cube, path: List(Applied)) -> Cube {
  list.fold(path, c, fn(c, applied) { cube.multiply(c, applied.alpha.effect) })
}

/// Einen Schritt lösen: Baustein-Folge suchen, Cube fortschreiben, Step bauen.
fn run_step(
  c: Cube,
  alphabet: List(Alpha),
  key: fn(Cube) -> Int,
  goal: fn(Cube) -> Bool,
  title: String,
  why: String,
  note: fn(Alpha, Cube) -> String,
) -> #(Step, Cube) {
  let assert Ok(path) = shortest_blocks(c, alphabet, key, goal)
  #(Step(title, why, to_blocks(path, note)), advance(c, path))
}

fn non_empty(steps: List(Step)) -> List(Step) {
  list.filter(steps, fn(step) {
    step.blocks |> list.any(fn(b) { b.moves != [] })
  })
}

/// Mehrere Schritte nacheinander ausführen; liefert die Schritte und den Endzustand.
fn run_steps(
  c: Cube,
  inputs: List(a),
  f: fn(Cube, Int, a) -> #(Step, Cube),
) -> #(List(Step), Cube) {
  let #(steps, final) =
    list.index_fold(inputs, #([], c), fn(acc, input, i) {
      let #(steps, c) = acc
      let #(step, c) = f(c, i, input)
      #([step, ..steps], c)
    })
  #(steps |> list.reverse |> non_empty, final)
}

// ---------------------------------------------------------------- Stufen

fn stage1(prepared: Prepared, c: Cube) -> #(Stage, Cube) {
  let #(steps, c) =
    run_steps(c, cross_edges, fn(c, k, id) {
      let #(moves, c) = solve_cross_edge(prepared, c, k)
      let name = edge_name(id)
      let block =
        Block(
          moves,
          CrossEdge,
          "Kürzester Weg für die Kante "
            <> name
            <> ". Die schon fertigen Kreuz-Kanten bleiben am Ende erhalten.",
        )
      #(
        Step(
          "Kante " <> name,
          "Bringe die Kante "
            <> name
            <> " an ihren Platz oben: Weiß auf der weißen Seite, die zweite Farbe an der passenden Mittelfarbe.",
          [block],
        ),
        c,
      )
    })
  #(
    Stage(
      "Das weiße Kreuz",
      "Wir beginnen oben mit den vier weißen Kanten. Sie bilden ein Kreuz auf der weißen Seite. "
        <> "Wichtig: Die zweite Farbe jeder Kante muss zur Mittelfarbe der Seitenfläche passen "
        <> "(Grün vorne, Rot rechts, Blau hinten, Orange links). Hier gibt es noch keine feste Zugfolge – "
        <> "das Programm zeigt dir den kürzesten Weg für jede Kante, ohne die schon fertigen zu zerstören.",
      steps,
    ),
    c,
  )
}

/// Ecken-Plätze der ersten Ebene (klassische Notation): Eckplatz und die Seite des Bausteins.
const corner_slots = [#("DFR", "R"), #("DRB", "B"), #("DBL", "L"), #("DLF", "F")]

fn stage2(c: Cube) -> #(Stage, Cube) {
  let slots =
    corner_slots
    |> list.map(fn(slot) {
      let #(corner, side) = slot
      #(
        real_corner(corner),
        alpha(side <> " U " <> side <> "' U'", CornerBlock, real_corner(corner)),
      )
    })
  let #(steps, c) =
    run_steps(c, seq.upto(4), fn(c, j, _) {
      let assert Ok(#(target, _)) = slots |> list.drop(j) |> list.first
      let name = corner_name(target)
      let blocks = slots |> list.drop(j) |> list.map(fn(slot) { slot.1 })
      run_step(
        c,
        list.append(turns(), blocks),
        corner_key([target]),
        corner_home(_, target),
        "Ecke " <> name,
        "Setze die Ecke " <> name <> " an ihren Platz in der weißen Ebene.",
        fn(a, before) {
          case a.tag {
            Align ->
              "Ausrichten: Drehe die untere (gelbe) Ebene, bis die Ecke "
              <> name
              <> " im passenden Winkel unter ihrem Zielplatz steht."
            _ ->
              case
                cube.corner_position(before, target) == a.slot,
                a.slot == target
              {
                True, _ ->
                  "Die Ecke steckt noch im falschen Platz bzw. falsch gedreht: Der Baustein hebt sie heraus. Wiederholt man ihn, setzt er sie am Ende richtig ein."
                _, True ->
                  "Baustein „Ecke einsetzen“: Wiederhole ihn so lange, bis die Ecke "
                  <> name
                  <> " richtig oben sitzt (maximal 5-mal)."
                _, _ ->
                  "Zwischenschritt: Dieser Baustein bringt die Ecke in eine günstigere Lage."
              }
          }
        },
      )
    })
  #(
    Stage(
      "Die weißen Ecken (erste Ebene)",
      "Jetzt kommen die vier weißen Ecken an ihren Platz oben. Jede Ecke wird zuerst in der unteren (gelben) Ebene so ausgerichtet, "
        <> "dass sie genau unter ihrem Zielplatz liegt. Dann hebt ein kurzer Baustein (rechts rein – Ebene drehen – rechts raus – Ebene zurück) "
        <> "sie nach oben. Diesen Baustein wiederholst du, bis die Ecke richtig sitzt. Steckt eine Ecke oben im falschen Platz, "
        <> "holt derselbe Baustein sie zuerst nach unten.",
      steps,
    ),
    c,
  )
}

/// Kanten-Plätze der mittleren Ebene (klassische Notation), im Kreis angeordnet.
const edge_slots = [#("F", "R"), #("R", "B"), #("B", "L"), #("L", "F")]

fn stage3(c: Cube) -> #(Stage, Cube) {
  let slots =
    edge_slots
    |> list.map(fn(slot) {
      let #(a, b) = slot
      let id = real_edge(a <> b)
      [
        alpha(
          "U " <> b <> " U' " <> b <> "' U' " <> a <> "' U " <> a,
          EdgeRight,
          id,
        ),
        alpha(
          "U' " <> a <> "' U " <> a <> " U " <> b <> " U' " <> b <> "'",
          EdgeLeft,
          id,
        ),
      ]
      |> fn(blocks) { #(id, blocks) }
    })
  let #(steps, c) =
    run_steps(c, seq.upto(4), fn(c, j, _) {
      let assert Ok(#(target, _)) = slots |> list.drop(j) |> list.first
      let name = edge_name(target)
      let blocks = slots |> list.drop(j) |> list.flat_map(fn(slot) { slot.1 })
      run_step(
        c,
        list.append(turns(), blocks),
        edge_key([target]),
        edge_home(_, target),
        "Kante " <> name,
        "Schiebe die Kante " <> name <> " in die mittlere Ebene.",
        fn(a, before) {
          case a.tag {
            Align ->
              "Ausrichten: Drehe die untere (gelbe) Ebene, bis die Kante "
              <> name
              <> " mit ihrer Frontfarbe vor der passenden Mittelfarbe steht."
            _ ->
              case
                cube.edge_position(before, target) == a.slot,
                a.slot == target
              {
                True, _ ->
                  "Die Kante sitzt in der Mitte falsch (oder verdreht): Dieser Baustein holt sie nach unten, damit du sie neu einsetzen kannst."
                _, True ->
                  "Baustein „Kante nach "
                  <> case a.tag {
                    EdgeRight -> "rechts"
                    _ -> "links"
                  }
                  <> " einsetzen“: Die Kante "
                  <> name
                  <> " rutscht in die mittlere Ebene."
                _, _ ->
                  "Zwischenschritt: Dieser Baustein verschiebt die Kante in eine günstigere Lage."
              }
          }
        },
      )
    })
  #(
    Stage(
      "Die mittlere Ebene",
      "Die Ebene oben (weiß) ist fertig. Jetzt fehlen die vier Kanten der mittleren Ebene – das sind die Kanten ohne Gelb und ohne Weiß. "
        <> "Du drehst die untere (gelbe) Ebene so, dass die Kante mit ihrer Frontfarbe vor der passenden Mitte steht, und schiebst sie dann "
        <> "mit einem Baustein nach links oder rechts in die Mittelschicht. Sitzt eine Kante in der Mitte falsch, holt der Baustein sie zuerst heraus.",
      steps,
    ),
    c,
  )
}

/// Die vier Kanten bzw. Ecken der letzten (gelben) Ebene.
const last_layer = [4, 5, 6, 7]

/// Eine Stufe der letzten Ebene: ein einziger Schritt mit einem Baustein-Typ.
fn last_layer_stage(
  c: Cube,
  title: String,
  intro: String,
  step_title: String,
  why: String,
  block: Alpha,
  key: fn(Cube) -> Int,
  goal: fn(Cube) -> Bool,
  align_note: String,
  block_note: String,
) -> #(Stage, Cube) {
  let #(step, c) =
    run_step(c, [block, ..turns()], key, goal, step_title, why, fn(a, _) {
      case a.tag {
        Align -> align_note
        _ -> block_note
      }
    })
  #(Stage(title, intro, non_empty([step])), c)
}

fn stage4(c: Cube) -> #(Stage, Cube) {
  last_layer_stage(
    c,
    "Das gelbe Kreuz",
    "Jetzt richtest du den Blick auf die untere (gelbe) Ebene. Ziel: Die gelben Flächen der vier Kanten zeigen nach unten und bilden ein Kreuz. "
      <> "Du siehst anfangs einen Punkt, einen Winkel oder eine Linie. Der Baustein „Kreuz“ (Vorderseite, rechts rein, Ebene, rechts raus, Ebene zurück, Vorderseite zurück) "
      <> "wird mit passender Ausrichtung wiederholt, bis das Kreuz steht.",
    "Gelbes Kreuz bilden",
    "Forme auf der gelben Seite ein Kreuz.",
    alpha("F R U R' U' F'", CrossBlock, -1),
    edge_key(last_layer),
    fn(c) { list.all(last_layer, fn(id) { edge_state(c, id).1 == 0 }) },
    "Ausrichten: Drehe die untere Ebene, bis die gelben Kanten so liegen, dass der nächste Baustein sie weiterbringt (Winkel hinten links, Linie waagrecht).",
    "Baustein „Kreuz“: bringt mehr gelbe Kanten nach unten. Eventuell nötig: zweimal anwenden.",
  )
}

fn stage5(c: Cube) -> #(Stage, Cube) {
  last_layer_stage(
    c,
    "Die gelbe Fläche",
    "Als Nächstes sollen auch die vier gelben Ecken nach unten zeigen, sodass die ganze untere Seite gelb ist. "
      <> "Der Baustein „Ecken drehen“ (rechts rein, Ebene, rechts raus, Ebene, rechts rein, Ebene zweimal, rechts raus) "
      <> "dreht die Ecken Schritt für Schritt. Dabei wird die untere Ebene zwischendurch ausgerichtet; die anderen Ebenen sind am Ende wieder in Ordnung.",
    "Gelbe Ecken nach unten drehen",
    "Drehe die Ecken so, dass die untere Seite komplett gelb ist.",
    alpha("R U R' U R U2 R'", CornerTwist, -1),
    corner_key(last_layer),
    fn(c) { list.all(last_layer, fn(id) { corner_state(c, id).1 == 0 }) },
    "Ausrichten: Drehe die untere Ebene, bis eine noch falsche Ecke an der passenden Stelle (vorne links unten) liegt.",
    "Baustein „Ecken drehen“: Wiederhole ihn, bis die gelbe Seite komplett gelb ist.",
  )
}

fn stage6(c: Cube) -> #(Stage, Cube) {
  last_layer_stage(
    c,
    "Die gelben Ecken platzieren",
    "Alle gelben Flächen zeigen jetzt nach unten, aber die Ecken müssen noch an ihre richtigen Plätze: Jede Ecke gehört zwischen ihre drei Mittelfarben. "
      <> "Der Baustein „Ecken tauschen“ bewegt drei Ecken im Kreis und lässt eine stehen. Zwischendurch wird die untere Ebene ausgerichtet.",
    "Ecken an die richtige Stelle",
    "Bringe jede gelbe Ecke an ihren Platz.",
    alpha("R' F R' B2 R F' R' B2 R2", CornerCycle, -1),
    corner_key(last_layer),
    fn(c) { list.all(last_layer, fn(id) { cube.corner_position(c, id) == id }) },
    "Ausrichten: Drehe die untere Ebene in die passende Stellung für den nächsten Baustein.",
    "Baustein „Ecken tauschen“: Drei Ecken wandern im Kreis – eine bleibt, wo sie ist.",
  )
}

fn stage7(c: Cube) -> #(Stage, Cube) {
  last_layer_stage(
    c,
    "Die letzten Kanten",
    "Zum Schluss fehlen nur noch die gelben Kanten: Sie müssen in die richtige Reihenfolge. Der Baustein „Kanten tauschen“ bewegt drei Kanten im Kreis, "
      <> "ohne die Ecken zu verändern. Nach höchstens zwei Anwendungen (mit passender Ausrichtung) ist der Würfel gelöst.",
    "Kanten an die richtige Stelle",
    "Bringe die letzten Kanten in die richtige Reihenfolge.",
    alpha("R U' R U R U R U' R' U' R2", EdgeCycle, -1),
    fn(c) { corner_key(last_layer)(c) * 331_776 + edge_key(last_layer)(c) },
    cube.is_solved,
    "Ausrichten: Drehe die untere Ebene (Hinweis: Achte darauf, welche Kante schon passt).",
    "Baustein „Kanten tauschen“: Drei Kanten wandern im Kreis, die Ecken bleiben unverändert.",
  )
}

// ---------------------------------------------------------------- Zusammensetzen

/// Löst den Würfel in sieben Stufen. `Error`, falls der Würfel ungültig ist.
pub fn solve(prepared: Prepared, start: Cube) -> Result(Plan, Nil) {
  let #(s1, c) = stage1(prepared, start)
  let #(s2, c) = stage2(c)
  let #(s3, c) = stage3(c)
  let #(s4, c) = stage4(c)
  let #(s5, c) = stage5(c)
  let #(s6, c) = stage6(c)
  let #(s7, c) = stage7(c)
  case cube.is_solved(c) {
    True -> Ok(flatten([s1, s2, s3, s4, s5, s6, s7]))
    False -> Error(Nil)
  }
}

/// Stufen -> flache Zugliste mit Infos je Zug.
pub fn flatten(stages: List(Stage)) -> Plan {
  let #(moves, infos, summaries, _) =
    stages
    |> list.index_fold(#([], [], [], 0), fn(acc, stage, stage_index) {
      let #(moves, infos, summaries, block_counter) = acc
      let first = list.length(moves)
      let #(moves, infos, block_counter) =
        list.fold(stage.steps, #(moves, infos, block_counter), fn(acc, step) {
          list.fold(step.blocks, acc, fn(acc, block) {
            let #(moves, infos, block_counter) = acc
            let length = list.length(block.moves)
            let new_infos =
              list.index_map(block.moves, fn(_, position) {
                MoveInfo(
                  stage: stage_index,
                  step_title: step.title,
                  why: step.why,
                  block: block_counter,
                  position: position,
                  block_length: length,
                  note: block.note,
                  tag: block.tag,
                )
              })
            #(
              list.append(moves, block.moves),
              list.append(infos, new_infos),
              block_counter + 1,
            )
          })
        })
      let summary =
        StageSummary(
          stage.title,
          stage.intro,
          first,
          list.length(moves) - first,
        )
      #(moves, infos, list.append(summaries, [summary]), block_counter)
    })
  Plan(moves, infos, summaries)
}
