//// Die Darstellung: Eingabe (Würfelnetz) und Lösungsansicht (3D-Würfel + Anleitung).

import gleam/dynamic/decode.{type Decoder}
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import lustre/attribute.{type Attribute}
import lustre/element.{type Element, text}
import lustre/element/html
import lustre/event
import rubixcube/arr
import rubixcube/cube.{type Face, type Move, B, D, F, L, R, U}
import rubixcube/facelets.{type Facelets}
import rubixcube/learn
import rubixcube/seq
import rubixcube/ui/cube3d
import rubixcube/ui/model.{
  type Model, type Msg, type Session, Failure, Info, Learn, Short, Success,
}

pub fn view(m: Model) -> Element(Msg) {
  html.div([attribute.class("wrap")], [
    html.header([attribute.class("top")], [
      html.h1([], [text("🧩 Zauberwürfel-Löser")]),
      html.button(
        [
          attribute.class("hbtn"),
          attribute.aria_label("Hilfe"),
          event.on_click(model.HelpOpen),
        ],
        [text("?")],
      ),
    ]),
    html.p([attribute.class("sub")], [
      text(
        "Gib die Farben deines 3×3-Würfels ein – das Programm führt dich Zug für Zug zur Lösung. Alles läuft lokal in deinem Browser.",
      ),
    ]),
    case m.session {
      None -> input_view(m)
      Some(session) -> solve_view(m, session)
    },
    help_overlay(m),
    html.footer([], [
      text(
        "Geschrieben in Gleam · Zwei-Phasen-Algorithmus (Kociemba-Prinzip), vollständig clientseitig – keine Daten verlassen deinen Browser.",
      ),
    ]),
  ])
}

// ---------------------------------------------------------------- Hilfsfunktionen

fn colour(face: Face) -> String {
  "var(--c-" <> cube.face_to_string(face) <> ")"
}

fn number() -> Decoder(Float) {
  decode.one_of(decode.float, or: [decode.int |> decode.map(int.to_float)])
}

/// Mausposition aus einem Pointer-Event als Nachricht.
fn pointer(to_message: fn(Float, Float) -> Msg) -> Decoder(Msg) {
  use x <- decode.field("clientX", number())
  use y <- decode.field("clientY", number())
  decode.success(to_message(x, y))
}

fn on_pointer(
  name: String,
  to_message: fn(Float, Float) -> Msg,
) -> Attribute(Msg) {
  event.on(name, pointer(to_message))
}

fn on_plain(name: String, message: Msg) -> Attribute(Msg) {
  event.on(name, decode.success(message))
}

fn cls(names: List(#(String, Bool))) -> Attribute(Msg) {
  attribute.classes(names)
}

// ---------------------------------------------------------------- Würfelnetz

fn face_offset(face: Face) -> Int {
  9 * cube.face_index(face)
}

/// Das aufgeklappte Netz. `interactive` bestimmt, ob die Felder angetippt werden können.
fn net(
  id: String,
  stickers: Facelets,
  interactive: Bool,
  extra: List(Attribute(Msg)),
) -> Element(Msg) {
  html.div(
    [attribute.id(id), attribute.class("net"), ..extra],
    [U, L, F, R, B, D]
      |> list.map(fn(face) {
        html.div([attribute.class("face pos-" <> cube.face_to_string(face))], [
          html.div([attribute.class("lbl")], [text(face_label(face))]),
          ..seq.upto(9)
          |> list.map(fn(i) {
            let index = face_offset(face) + i
            let is_centre = i == 4
            html.button(
              [
                cls([
                  #("st", True),
                  #("center", is_centre),
                  #("ro", !interactive),
                ]),
                attribute.style("background", colour(arr.at(stickers, index))),
                attribute.data("idx", int.to_string(index)),
                attribute.tabindex(case interactive && !is_centre {
                  True -> 0
                  False -> -1
                }),
                attribute.aria_label(
                  face_label(face) <> " Feld " <> int.to_string(i + 1),
                ),
                ..case interactive && !is_centre {
                  True -> [event.on_click(model.Paint(index))]
                  False -> []
                }
              ],
              [],
            )
          })
        ])
      }),
  )
}

fn face_label(face: Face) -> String {
  case face {
    U -> "Oben"
    D -> "Unten"
    F -> "Vorne"
    B -> "Hinten"
    L -> "Links"
    R -> "Rechts"
  }
}

// ---------------------------------------------------------------- Eingabe

fn input_view(m: Model) -> Element(Msg) {
  html.section([attribute.id("inputView")], [
    html.div([attribute.class("card")], [
      html.div([attribute.class("input-grid")], [
        html.div([], [
          html.h2([], [text("1. Farben eingeben")]),
          net("inputNet", m.stickers, True, [
            on_pointer("pointerdown", model.PaintAt),
            on_pointer("pointermove", model.PaintMoved),
            on_plain("pointerup", model.PaintEnd),
            on_plain("pointercancel", model.PaintEnd),
            on_plain("pointerleave", model.PaintEnd),
          ]),
        ]),
        html.div([], [
          html.h2([], [text("Farbe wählen")]),
          palette(m),
          html.p([attribute.class("hint")], [
            text(
              "Wähle eine Farbe und tippe dann auf die Felder im Würfelnetz (oder wische darüber), um sie zu färben. Die Mittelfelder sind fest.",
            ),
          ]),
          html.p([attribute.class("hint")], [
            html.b([], [text("Ausrichtung: ")]),
            text(
              "Halte den Würfel so, dass die weiße Mitte oben und die grüne Mitte vorne ist. Das Netz zeigt die Seiten wie ein aufgeklappter Karton – jeweils so, als würdest du direkt auf diese Seite schauen (bei Oben liegt die Hinterkante oben, bei Unten die Vorderkante oben).",
            ),
          ]),
          mode_selector(m),
          html.div(
            [attribute.class("row"), attribute.style("margin-top", "12px")],
            [
              html.button(
                [
                  attribute.class("primary"),
                  attribute.id("btnSolve"),
                  attribute.disabled(m.calculating),
                  event.on_click(model.Solve),
                ],
                [text("Lösung berechnen")],
              ),
              html.button(
                [attribute.id("btnScramble"), event.on_click(model.Scramble)],
                [
                  text("Zufällig mischen"),
                ],
              ),
              html.button(
                [attribute.id("btnReset"), event.on_click(model.Reset)],
                [
                  text("Gelöst-Zustand"),
                ],
              ),
            ],
          ),
          notice(m.notice),
        ]),
      ]),
    ]),
  ])
}

fn palette(m: Model) -> Element(Msg) {
  html.div(
    [attribute.class("palette")],
    list.map(cube.faces, fn(face) {
      let count = arr.count(m.stickers, fn(f) { f == face })
      html.button(
        [
          cls([#("sw", True), #("sel", face == m.brush)]),
          attribute.style("background", colour(face)),
          attribute.title(cube.colour_name(face)),
          event.on_click(model.PickBrush(face)),
        ],
        [
          html.span([cls([#("bad", count != 9)])], [
            text(int.to_string(count) <> "/9"),
          ]),
        ],
      )
    }),
  )
}

fn mode_selector(m: Model) -> Element(Msg) {
  let option = fn(mode, title, description) {
    html.label([], [
      html.input([
        attribute.type_("radio"),
        attribute.name("mode"),
        attribute.value(case mode {
          Learn -> "learn"
          Short -> "short"
        }),
        attribute.checked(m.mode == mode),
        event.on_click(model.SetMode(mode)),
      ]),
      html.span([], [
        html.b([], [text(title)]),
        html.small([], [text(description)]),
      ]),
    ])
  }
  html.fieldset([attribute.class("modes")], [
    html.legend([], [text("2. Lösungsweg")]),
    option(
      Learn,
      "Lernmodus",
      " – Anfängermethode in 7 Stufen mit Erklärungen (ca. 100–190 Züge)",
    ),
    option(Short, "Kurze Lösung", " – nur Züge, dafür meist unter 25"),
  ])
}

fn notice(n: Option(model.Notice)) -> Element(Msg) {
  case n {
    None -> html.div([attribute.id("inputMsg")], [])
    Some(notice) -> {
      let #(kind, message) = case notice {
        Info(s) -> #("info", s)
        Failure(s) -> #("err", s)
        Success(s) -> #("ok", s)
      }
      html.div([attribute.id("inputMsg")], [
        html.div([attribute.class("msg " <> kind)], [text(message)]),
      ])
    }
  }
}

// ---------------------------------------------------------------- Lösung

fn solve_view(m: Model, s: Session) -> Element(Msg) {
  let n = arr.length(s.moves)
  let learning = option.is_some(s.infos)
  html.section([attribute.id("solveView")], [
    html.div(
      [attribute.class("row"), attribute.style("margin-bottom", "12px")],
      [
        html.button([attribute.id("btnBack"), event.on_click(model.Back)], [
          text("← Eingabe ändern"),
        ]),
        html.span([attribute.class("info"), attribute.id("solInfo")], [
          text(
            int.to_string(n)
            <> " Züge"
            <> case learning {
              True -> " · Lernmodus"
              False -> " · Kurze Lösung"
            },
          ),
        ]),
      ],
    ),
    html.div([attribute.class("solve-grid")], [
      scene_card(m, s),
      instruction_card(m, s, n, learning),
    ]),
  ])
}

fn scene_card(m: Model, s: Session) -> Element(Msg) {
  let state = arr.at(s.states, s.index)
  html.div([attribute.class("card")], [
    cube3d.view(
      state,
      s.anim,
      m.angle,
      option.is_some(m.drag),
      model.duration(m.speed),
      [
        on_pointer("pointerdown", model.DragStart),
        on_pointer("pointermove", model.DragMove),
        on_plain("pointerup", model.DragEnd),
        on_plain("pointercancel", model.DragEnd),
        on_plain("pointerleave", model.DragEnd),
      ],
      [
        html.div([attribute.class("drag-hint")], [text("Ziehen zum Drehen")]),
        html.button(
          [
            attribute.id("btnFlip"),
            attribute.title("Ansicht um 180° drehen"),
            event.on_click(model.FlipView),
          ],
          [text("↻ Rückseite")],
        ),
      ],
    ),
    html.div(
      [
        attribute.class("row"),
        attribute.style("justify-content", "space-between"),
        attribute.style("margin-top", "8px"),
      ],
      [
        html.label([attribute.class("chk")], [
          html.input([
            attribute.type_("checkbox"),
            attribute.id("follow"),
            attribute.checked(m.follow),
            event.on_check(model.SetFollow),
          ]),
          text(" Ansicht automatisch zur gedrehten Seite wenden"),
        ]),
      ],
    ),
    html.div([attribute.class("mininet")], [
      net("miniNet", state, False, [attribute.style("--sz", "20px")]),
    ]),
  ])
}

fn instruction_card(
  m: Model,
  s: Session,
  n: Int,
  learning: Bool,
) -> Element(Msg) {
  let finished = s.index >= n
  let info = case s.infos {
    Some(infos) if !finished -> Some(arr.at(infos, s.index))
    _ -> None
  }
  html.div([attribute.class("card instr")], [
    case learning {
      True -> stage_box(s, info, finished)
      False -> element.none()
    },
    html.div([attribute.class("stepno")], [text(step_label(s, n, info))]),
    html.div([attribute.class("bar")], [
      html.div(
        [
          attribute.id("barFill"),
          attribute.style(
            "width",
            int.to_string(s.index * 100 / int.max(n, 1)) <> "%",
          ),
        ],
        [],
      ),
    ]),
    move_display(s, n),
    case info {
      Some(i) ->
        html.div([attribute.class("note"), attribute.id("noteBox")], [
          text(i.note),
          text(case i.block_length > 1 {
            True ->
              " (Baustein: Zug "
              <> int.to_string(i.position + 1)
              <> " von "
              <> int.to_string(i.block_length)
              <> ")"
            False -> ""
          }),
        ])
      None -> element.none()
    },
    case info {
      Some(i) -> stage_details(s, i)
      None -> element.none()
    },
    html.div([attribute.class("next")], [text(next_moves(s, n))]),
    controls(s, n),
    html.div([attribute.class("speed")], [
      text("langsam "),
      html.input([
        attribute.type_("range"),
        attribute.min("0"),
        attribute.max("100"),
        attribute.value(int.to_string(m.speed)),
        event.on_input(fn(v) {
          model.SetSpeed(case int.parse(v) {
            Ok(n) -> n
            Error(_) -> 55
          })
        }),
      ]),
      text(" schnell"),
    ]),
    html.h2(
      [
        attribute.style("margin-top", "16px"),
        attribute.style("text-align", "left"),
      ],
      [
        text("Alle Züge"),
      ],
    ),
    chips(s, info),
    case learning {
      True -> element.none()
      False -> legend()
    },
  ])
}

fn step_label(s: Session, n: Int, info: Option(learn.MoveInfo)) -> String {
  case info {
    Some(i) ->
      i.step_title
      <> " · Zug "
      <> int.to_string(s.index + 1)
      <> " von "
      <> int.to_string(n)
    None ->
      case s.index >= n {
        True -> "Fertig nach " <> int.to_string(n) <> " Zügen"
        False ->
          "Schritt "
          <> int.to_string(s.index + 1)
          <> " von "
          <> int.to_string(n)
          <> case s.index < s.phase1 {
            True -> " · Phase 1"
            False -> " · Phase 2"
          }
      }
  }
}

fn stage_box(
  s: Session,
  info: Option(learn.MoveInfo),
  finished: Bool,
) -> Element(Msg) {
  let n = list.length(s.stages)
  let current = case info {
    Some(i) -> i.stage
    None -> -1
  }
  html.div([attribute.id("stageBox")], [
    html.div(
      [attribute.class("stages"), attribute.id("stagePills")],
      s.stages
        |> list.index_map(fn(stage, i) {
          let done =
            s.index >= stage.first + stage.count
            && { stage.count > 0 || s.index >= stage.first }
          html.button(
            [
              cls([
                #("stg", True),
                #("done", done),
                #("cur", i == current),
                #("empty", stage.count == 0),
              ]),
              attribute.title(stage.title),
              event.on_click(model.JumpToStage(i)),
            ],
            [
              text(case done {
                True -> "✓"
                False -> int.to_string(i + 1)
              }),
            ],
          )
        }),
    ),
    html.div([attribute.class("stagename"), attribute.id("stageName")], [
      text(case info, finished {
        Some(i), _ ->
          "Stufe "
          <> int.to_string(i.stage + 1)
          <> " von "
          <> int.to_string(n)
          <> ": "
          <> stage_title(s, i.stage)
        None, True -> "Geschafft!"
        None, False -> ""
      }),
    ]),
  ])
}

fn stage_title(s: Session, index: Int) -> String {
  case list.drop(s.stages, index) {
    [stage, ..] -> stage.title
    [] -> ""
  }
}

fn stage_details(s: Session, i: learn.MoveInfo) -> Element(Msg) {
  html.details([attribute.class("sinfo")], [
    html.summary([], [text("Was passiert in dieser Stufe?")]),
    html.p([], [
      text(case list.drop(s.stages, i.stage) {
        [stage, ..] -> stage.intro
        [] -> ""
      }),
    ]),
  ])
}

fn move_display(s: Session, n: Int) -> Element(Msg) {
  case s.index < n {
    False ->
      html.div([], [
        html.div([attribute.class("move-big"), attribute.id("moveBig")], [
          text("🎉"),
        ]),
        html.div([attribute.class("move-text"), attribute.id("moveText")], [
          html.b([], [text("Der Würfel ist gelöst!")]),
          case list.length(s.stages) {
            0 -> element.none()
            k ->
              html.span([attribute.class("hint")], [
                html.br([]),
                text(
                  "Alle "
                  <> int.to_string(k)
                  <> " Stufen geschafft – gut gemacht!",
                ),
              ])
          },
        ]),
      ])
    True -> {
      let move = arr.at(s.moves, s.index)
      html.div([], [
        html.div(
          [
            attribute.class("move-big"),
            attribute.id("moveBig"),
            attribute.style("color", case move.face {
              U -> "#fff"
              other -> colour(other)
            }),
          ],
          [text(cube.move_to_string(move))],
        ),
        html.div(
          [attribute.class("move-text"), attribute.id("moveText")],
          describe(move),
        ),
      ])
    }
  }
}

fn describe(move: Move) -> List(Element(Msg)) {
  let direction = case move.turn {
    cube.Clockwise -> [
      text("eine Vierteldrehung "),
      html.b([], [text("im Uhrzeigersinn")]),
    ]
    cube.Half -> [html.b([], [text("eine halbe Drehung (180°)")])]
    cube.CounterClockwise -> [
      text("eine Vierteldrehung "),
      html.b([], [text("gegen den Uhrzeigersinn")]),
    ]
  }
  list.flatten([
    [
      text("Drehe die "),
      html.b([], [text(cube.face_name(move.face))]),
      text(" (Mitte: "),
      html.span([attribute.style("color", colour(move.face))], [text("●")]),
      text(" " <> cube.colour_name(move.face) <> "): "),
    ],
    direction,
    [text(".")],
    case move.turn {
      cube.Half -> []
      _ -> [
        html.br([]),
        html.span([attribute.class("hint")], [
          text("Blick direkt auf diese Seite."),
        ]),
      ]
    },
  ])
}

fn next_moves(s: Session, n: Int) -> String {
  case s.index + 1 < n {
    False -> "Das ist der letzte Zug!"
    True ->
      "Danach: "
      <> list.map(seq.between(s.index + 1, int.min(s.index + 3, n - 1)), fn(i) {
        cube.move_to_string(arr.at(s.moves, i))
      })
      |> list.fold("", fn(acc, mv) {
        case acc {
          "" -> mv
          _ -> acc <> "  " <> mv
        }
      })
      <> case s.index + 4 < n {
        True -> " …"
        False -> ""
      }
  }
}

fn controls(s: Session, n: Int) -> Element(Msg) {
  let busy = option.is_some(s.anim)
  html.div([attribute.class("ctrl")], [
    html.button(
      [
        attribute.title("Zum Anfang"),
        attribute.disabled(s.index == 0 || busy),
        event.on_click(model.First),
      ],
      [text("⏮")],
    ),
    html.button(
      [
        attribute.title("Zurück"),
        attribute.disabled(s.index == 0 || busy),
        event.on_click(model.Prev),
      ],
      [text("◀")],
    ),
    html.button(
      [
        attribute.class("primary"),
        attribute.title("Automatisch abspielen"),
        attribute.disabled(s.index >= n && !s.playing),
        event.on_click(model.TogglePlay),
      ],
      [
        text(case s.playing {
          True -> "⏸ Pause"
          False -> "▶ Auto"
        }),
      ],
    ),
    html.button(
      [
        attribute.class("primary"),
        attribute.title("Weiter"),
        attribute.disabled(s.index >= n || busy),
        event.on_click(model.Next),
      ],
      [text("Weiter")],
    ),
    html.button(
      [
        attribute.title("Zum Ende"),
        attribute.disabled(s.index >= n || busy),
        event.on_click(model.Last),
      ],
      [text("⏭")],
    ),
  ])
}

fn chips(s: Session, info: Option(learn.MoveInfo)) -> Element(Msg) {
  let current_block = case info {
    Some(i) -> i.block
    None -> -1
  }
  html.div(
    [attribute.class("chips"), attribute.id("chips")],
    seq.upto(arr.length(s.moves))
      |> list.map(fn(i) {
        let move = arr.at(s.moves, i)
        let #(extra, title) = case s.infos {
          Some(infos) -> {
            let mi = arr.at(infos, i)
            let first_of_block =
              i == 0 || arr.at(infos, i - 1).block != mi.block
            #(
              [
                #(
                  case mi.stage % 2 {
                    1 -> "sb"
                    _ -> "sa"
                  },
                  True,
                ),
                #("m0", first_of_block),
                #("inmacro", mi.block == current_block),
              ],
              "Stufe " <> int.to_string(mi.stage + 1) <> ": " <> mi.step_title,
            )
          }
          None -> #([#("p2", i >= s.phase1)], "")
        }
        html.span(
          [
            cls([
              #("chip", True),
              #("done", i < s.index),
              #("cur", i == s.index),
              ..extra
            ]),
            attribute.title(title),
            event.on_click(model.JumpToMove(i)),
          ],
          [text(cube.move_to_string(move))],
        )
      }),
  )
}

fn legend() -> Element(Msg) {
  html.div([attribute.class("legend")], [
    html.span([], [
      html.i([attribute.style("background", "var(--accent)")], []),
      text("Phase 1: Würfel „vorbereiten“"),
    ]),
    html.span([], [
      html.i([attribute.style("border", "1px dashed var(--muted)")], []),
      text("Phase 2 (gestrichelt): fertig lösen"),
    ]),
  ])
}

// ---------------------------------------------------------------- Hilfe

fn help_overlay(m: Model) -> Element(Msg) {
  case m.help_open {
    False -> element.none()
    True ->
      html.div([attribute.class("overlay"), attribute.id("help")], [
        html.div(
          [attribute.class("backdrop"), event.on_click(model.HelpClose)],
          [],
        ),
        html.div([attribute.class("sheet")], [
          html.button(
            [
              attribute.class("x"),
              attribute.aria_label("Schließen"),
              event.on_click(model.HelpClose),
            ],
            [text("✕")],
          ),
          current_help(m),
          html.h3([], [text("Eingabe")]),
          html.p([], [
            text(
              "Farbe unten wählen, dann Felder antippen oder mit dem Finger darüberwischen. Die Mittelfelder sind fest.",
            ),
          ]),
          html.p([], [
            html.b([], [text("Ausrichtung: ")]),
            text(
              "Weiß oben, Grün vorne. Das Netz zeigt die Seiten wie einen aufgeklappten Karton: oben Weiß, in der Mitte Links, Vorne, Rechts, Hinten, unten Gelb – jeweils mit Blick direkt auf die Seite.",
            ),
          ]),
          html.h3([], [text("Notation")]),
          html.p([], [
            html.b([], [text("U")]),
            text(" oben, "),
            html.b([], [text("D")]),
            text(" unten, "),
            html.b([], [text("F")]),
            text(" vorne, "),
            html.b([], [text("B")]),
            text(" hinten, "),
            html.b([], [text("L")]),
            text(" links, "),
            html.b([], [text("R")]),
            text(
              " rechts. Ohne Zeichen = Vierteldrehung im Uhrzeigersinn (Blick auf diese Seite), ",
            ),
            html.b([], [text("'")]),
            text(" = gegen den Uhrzeigersinn, "),
            html.b([], [text("2")]),
            text(" = halbe Drehung."),
          ]),
          html.h3([], [text("Bedienung")]),
          html.p([], [
            text(
              "Würfel mit dem Finger ziehen = drehen. Die Kreise oben (Lernmodus) springen zur jeweiligen Stufe.",
            ),
          ]),
        ]),
      ])
  }
}

/// Im Lernmodus: Erklärung der aktuellen Stufe und des aktuellen Bausteins.
fn current_help(m: Model) -> Element(Msg) {
  case m.session {
    Some(s) ->
      case s.infos, s.index < arr.length(s.moves) {
        Some(infos), True -> {
          let i = arr.at(infos, s.index)
          let intro = case list.drop(s.stages, i.stage) {
            [stage, ..] -> stage.intro
            [] -> ""
          }
          html.div([], [
            html.h3([], [
              text(
                "Stufe "
                <> int.to_string(i.stage + 1)
                <> ": "
                <> stage_title(s, i.stage),
              ),
            ]),
            html.p([], [text(intro)]),
            html.h3([], [text("Aktueller Hinweis")]),
            html.p([], [text(i.note)]),
          ])
        }
        _, _ -> element.none()
      }
    None -> element.none()
  }
}
