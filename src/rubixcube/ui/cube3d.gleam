//// Der 3D-Würfel: 27 Teilwürfel mit CSS-Transformationen, Schicht-Drehung per Transition.
////
//// Koordinaten: x nach rechts, y nach oben, z zum Betrachter. Die Größe kommt aus der
//// CSS-Variable `--s` (Kantenlänge eines Teilwürfels), damit sich der Würfel an den
//// verfügbaren Platz anpasst.

import gleam/float
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import lustre/attribute.{type Attribute}
import lustre/element.{type Element}
import lustre/element/html
import lustre/element/keyed
import rubixcube/arr
import rubixcube/cube.{type Face, B, D, F, L, R, U}
import rubixcube/facelets.{type Facelets}
import rubixcube/ui/model.{type Anim}

type Cubie {
  Cubie(x: Int, y: Int, z: Int)
}

fn cubies() -> List(Cubie) {
  let range = [-1, 0, 1]
  use x <- list.flat_map(range)
  use y <- list.flat_map(range)
  use z <- list.map(range)
  Cubie(x, y, z)
}

/// Welcher Aufkleber (0..53) liegt auf Seite `face` des Teilwürfels?
fn sticker_index(face: Face, c: Cubie) -> Int {
  case face {
    U -> 0 + { c.z + 1 } * 3 + { c.x + 1 }
    R -> 9 + { 1 - c.y } * 3 + { 1 - c.z }
    F -> 18 + { 1 - c.y } * 3 + { c.x + 1 }
    D -> 27 + { 1 - c.z } * 3 + { c.x + 1 }
    L -> 36 + { 1 - c.y } * 3 + { c.z + 1 }
    B -> 45 + { 1 - c.y } * 3 + { 1 - c.x }
  }
}

/// Liegt der Teilwürfel in der Schicht, die `face` dreht?
fn in_layer(face: Face, c: Cubie) -> Bool {
  case face {
    U -> c.y == 1
    D -> c.y == -1
    R -> c.x == 1
    L -> c.x == -1
    F -> c.z == 1
    B -> c.z == -1
  }
}

/// Ist die Seite `face` dieses Teilwürfels eine Außenfläche?
fn is_outer(face: Face, c: Cubie) -> Bool {
  case face {
    U -> c.y == 1
    D -> c.y == -1
    R -> c.x == 1
    L -> c.x == -1
    F -> c.z == 1
    B -> c.z == -1
  }
}

fn face_transform(face: Face) -> String {
  let out = "translateZ(calc(var(--s) / 2))"
  case face {
    F -> out
    B -> "rotateY(180deg) " <> out
    R -> "rotateY(90deg) " <> out
    L -> "rotateY(-90deg) " <> out
    U -> "rotateX(90deg) " <> out
    D -> "rotateX(-90deg) " <> out
  }
}

fn colour(face: Face) -> String {
  "var(--c-" <> cube.face_to_string(face) <> ")"
}

fn cubie_element(state: Facelets, c: Cubie) -> #(String, Element(msg)) {
  let key =
    int.to_string(c.x) <> "," <> int.to_string(c.y) <> "," <> int.to_string(c.z)
  let scale = fn(n: Int) { "calc(var(--s) * " <> int.to_string(n) <> ")" }
  let position =
    "translate3d("
    <> scale(c.x)
    <> ", "
    <> scale(-c.y)
    <> ", "
    <> scale(c.z)
    <> ")"
  let sides =
    cube.faces
    |> list.map(fn(face) {
      let outer = is_outer(face, c)
      let colour_style = case outer {
        True -> [
          attribute.style(
            "background",
            colour(arr.at(state, sticker_index(face, c))),
          ),
        ]
        False -> []
      }
      html.div(
        [
          attribute.class(case outer {
            True -> "fc col"
            False -> "fc"
          }),
          attribute.style("transform", face_transform(face)),
          ..colour_style
        ],
        [],
      )
    })
  #(
    key,
    html.div(
      [attribute.class("cubie"), attribute.style("transform", position)],
      sides,
    ),
  )
}

/// Drehung einer Schicht in CSS (Vierteldrehung im Uhrzeigersinn mit Blick auf die Seite).
fn rotation(move: cube.Move) -> String {
  let #(axis, sign) = case move.face {
    U -> #("rotateY", -1)
    D -> #("rotateY", 1)
    R -> #("rotateX", 1)
    L -> #("rotateX", -1)
    F -> #("rotateZ", 1)
    B -> #("rotateZ", -1)
  }
  let turns = case move.turn {
    cube.Clockwise -> 1
    cube.Half -> 2
    cube.CounterClockwise -> -1
  }
  axis <> "(" <> int.to_string(sign * turns * 90) <> "deg)"
}

pub fn view(
  state: Facelets,
  anim: Option(Anim),
  angle: #(Float, Float),
  dragging: Bool,
  duration_ms: Int,
  extra: List(Attribute(msg)),
  overlay: List(Element(msg)),
) -> Element(msg) {
  let turning = case anim {
    Some(a) -> Some(a.move.face)
    None -> None
  }
  let #(in_layer_cubies, others) =
    list.partition(cubies(), fn(c) {
      case turning {
        Some(face) -> in_layer(face, c)
        None -> False
      }
    })
  let layer_style = case anim {
    Some(a) if a.started -> [attribute.style("transform", rotation(a.move))]
    _ -> []
  }
  let layer =
    keyed.div(
      [
        attribute.class("layer"),
        attribute.style("--dur", int.to_string(duration_ms) <> "ms"),
        ..layer_style
      ],
      list.map(in_layer_cubies, cubie_element(state, _)),
    )
  let cube_children =
    list.append(list.map(others, cubie_element(state, _)), [#("layer", layer)])
  let #(rx, ry) = angle
  let cube_attrs = [
    attribute.id("cube"),
    attribute.classes([#("drag", dragging)]),
    attribute.style(
      "transform",
      "rotateX("
        <> float.to_string(rx)
        <> "deg) rotateY("
        <> float.to_string(ry)
        <> "deg)",
    ),
  ]
  html.div([attribute.class("scene"), attribute.id("scene"), ..extra], [
    keyed.div(cube_attrs, cube_children),
    ..overlay
  ])
}

/// Blickwinkel, aus dem man die Schicht der Seite `face` gut sieht.
pub fn view_for_face(face: Face) -> #(Float, Float) {
  case face {
    U -> #(-38.0, -30.0)
    F -> #(-18.0, -28.0)
    R -> #(-18.0, -62.0)
    L -> #(-18.0, 40.0)
    B -> #(-18.0, 150.0)
    D -> #(34.0, -30.0)
  }
}

/// Zielwinkel wählen, der am nächsten am aktuellen liegt (modulo 360°).
pub fn nearest_angle(current: Float, target: Float) -> Float {
  let turns = float.round({ current -. target } /. 360.0)
  target +. int.to_float(turns) *. 360.0
}
