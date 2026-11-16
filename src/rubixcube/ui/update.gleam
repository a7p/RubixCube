//// Die Update-Funktion: reagiert auf Nachrichten und liefert den neuen Zustand.

import gleam/list
import gleam/option.{type Option, None, Some}
import lustre/effect.{type Effect}
import rubixcube/arr
import rubixcube/cube.{type Cube, type Move}
import rubixcube/facelets
import rubixcube/learn
import rubixcube/seq
import rubixcube/twophase
import rubixcube/ui/browser
import rubixcube/ui/cube3d
import rubixcube/ui/model.{
  type Model, type Msg, type Session, Anim, Failure, Info, Learn, Model, Session,
  Short, Success,
}

pub fn init(_flags: Nil) -> #(Model, Effect(Msg)) {
  #(model.initial(), browser.keys(model.KeyPressed))
}

pub fn update(m: Model, msg: Msg) -> #(Model, Effect(Msg)) {
  case msg {
    // ---------------------------------------------------------- Eingabe
    model.PickBrush(face) -> #(Model(..m, brush: face), effect.none())
    model.PaintAt(x, y) -> #(
      Model(..m, painting: True),
      browser.sticker_under(x, y, model.Paint),
    )
    model.PaintMoved(x, y) ->
      case m.painting {
        True -> #(m, browser.sticker_under(x, y, model.Paint))
        False -> #(m, effect.none())
      }
    model.Paint(index) -> #(paint(m, index), effect.none())
    model.PaintEnd -> #(Model(..m, painting: False), effect.none())
    model.SetMode(mode) -> #(Model(..m, mode: mode), effect.none())
    model.Scramble -> #(
      Model(..m, stickers: random_scramble(30), notice: None),
      effect.none(),
    )
    model.Reset -> #(
      Model(..m, stickers: facelets.solved(), notice: None),
      effect.none(),
    )
    model.Solve -> solve(m)
    model.Compute -> #(compute(m), effect.none())

    // ---------------------------------------------------------- Lösungsansicht
    model.Back -> #(
      Model(..m, session: None, notice: None, help_open: False),
      effect.none(),
    )
    model.Next -> with_session(m, fn(s) { step(m, stop_play(s), True) })
    model.Prev -> with_session(m, fn(s) { step(m, stop_play(s), False) })
    model.First -> with_session(m, fn(s) { jump(m, stop_play(s), 0) })
    model.Last ->
      with_session(m, fn(s) { jump(m, stop_play(s), arr.length(s.moves)) })
    model.JumpToMove(i) -> with_session(m, fn(s) { jump(m, stop_play(s), i) })
    model.JumpToStage(i) ->
      with_session(m, fn(s) {
        case list.drop(s.stages, i) {
          [stage, ..] if stage.count > 0 -> jump(m, stop_play(s), stage.first)
          _ -> #(m, effect.none())
        }
      })
    model.TogglePlay ->
      with_session(m, fn(s) {
        case s.playing {
          True -> #(put(m, Session(..s, playing: False)), effect.none())
          False ->
            case s.index < arr.length(s.moves) {
              True -> step(m, Session(..s, playing: True), True)
              False -> #(m, effect.none())
            }
        }
      })
    model.AnimStarted(token) ->
      with_session(m, fn(s) {
        case s.anim {
          Some(a) if a.token == token -> #(
            put(m, Session(..s, anim: Some(Anim(..a, started: True)))),
            effect.none(),
          )
          _ -> #(m, effect.none())
        }
      })
    model.AnimFinished(token) -> with_session(m, finish_animation(m, _, token))
    model.PlayTick(token) ->
      with_session(m, fn(s) {
        case s.playing && s.token == token && s.anim == None {
          True -> step(m, s, True)
          False -> #(m, effect.none())
        }
      })

    // ---------------------------------------------------------- Ansicht
    model.DragStart(x, y) -> #(Model(..m, drag: Some(#(x, y))), effect.none())
    model.DragMove(x, y) ->
      case m.drag {
        Some(#(x0, y0)) -> {
          let #(rx, ry) = m.angle
          let rx = float_clamp(rx -. { y -. y0 } *. 0.6, -89.0, 89.0)
          let ry = ry +. { x -. x0 } *. 0.6
          #(Model(..m, angle: #(rx, ry), drag: Some(#(x, y))), effect.none())
        }
        None -> #(m, effect.none())
      }
    model.DragEnd -> #(Model(..m, drag: None), effect.none())
    model.FlipView -> {
      let #(rx, ry) = m.angle
      #(Model(..m, angle: #(rx, ry +. 180.0)), effect.none())
    }
    model.SetFollow(on) -> #(Model(..m, follow: on), effect.none())
    model.SetSpeed(speed) -> #(Model(..m, speed: speed), effect.none())
    model.HelpOpen -> #(Model(..m, help_open: True), effect.none())
    model.HelpClose -> #(Model(..m, help_open: False), effect.none())
    model.KeyPressed(key) -> key_pressed(m, key)
  }
}

fn float_clamp(x: Float, low: Float, high: Float) -> Float {
  case x <. low, x >. high {
    True, _ -> low
    _, True -> high
    _, _ -> x
  }
}

// ---------------------------------------------------------------- Eingabe

fn paint(m: Model, index: Int) -> Model {
  // Mittelfelder (4, 13, 22, …) sind fest
  case index % 9 == 4 || arr.at(m.stickers, index) == m.brush {
    True -> m
    False ->
      Model(..m, stickers: arr.set(m.stickers, index, m.brush), notice: None)
  }
}

/// Ein zufällig gemischter Würfel (keine zwei gleichen Seiten hintereinander).
fn random_scramble(length: Int) -> facelets.Facelets {
  let #(moves, _) =
    seq.upto(length)
    |> list.fold(#([], -1), fn(acc, _) {
      let #(moves, last_face) = acc
      let candidate = browser.random(18)
      case candidate / 3 == last_face {
        True -> #(moves, last_face)
        False -> #([cube.move_from_index(candidate), ..moves], candidate / 3)
      }
    })
  facelets.from_cube(cube.from_moves(moves))
}

fn solve(m: Model) -> #(Model, Effect(Msg)) {
  case facelets.to_cube(m.stickers) {
    Error(error) -> #(
      Model(..m, notice: Some(Failure("⚠️ " <> facelets.describe(error)))),
      effect.none(),
    )
    Ok(c) ->
      case cube.is_solved(c) {
        True -> #(
          Model(..m, notice: Some(Success("Der Würfel ist bereits gelöst. 🎉"))),
          effect.none(),
        )
        False -> #(
          Model(
            ..m,
            calculating: True,
            notice: Some(Info(
              "⏳ Berechne Lösung … (beim ersten Mal baut das Programm Suchtabellen auf, das dauert ein bis zwei Sekunden)",
            )),
          ),
          // kurz warten, damit die Meldung gezeichnet wird, bevor gerechnet wird
          browser.after(60, model.Compute),
        )
      }
  }
}

/// Die eigentliche Berechnung (blockiert kurz). Tabellen werden beim ersten Mal aufgebaut.
fn compute(m: Model) -> Model {
  let assert Ok(start) = facelets.to_cube(m.stickers)
  case m.mode {
    Learn -> {
      let tables = option.lazy_unwrap(m.learn_tables, learn.prepare)
      let m = Model(..m, learn_tables: Some(tables), calculating: False)
      case learn.solve(tables, start) {
        Ok(plan) -> {
          let session =
            make_session(
              start,
              plan.moves,
              Some(arr.from_list(plan.infos)),
              plan.stages,
              0,
            )
          open_session(m, session)
        }
        Error(_) -> failed(m)
      }
    }
    Short -> {
      let tables = option.lazy_unwrap(m.solver_tables, twophase.build)
      let m = Model(..m, solver_tables: Some(tables), calculating: False)
      case twophase.solve(tables, start, 800) {
        Ok(solution) ->
          open_session(
            m,
            make_session(
              start,
              solution.moves,
              None,
              [],
              solution.phase1_length,
            ),
          )
        Error(_) -> failed(m)
      }
    }
  }
}

fn failed(m: Model) -> Model {
  Model(..m, notice: Some(Failure("⚠️ Keine Lösung gefunden.")))
}

fn make_session(
  start: Cube,
  moves: List(Move),
  infos: Option(arr.Arr(learn.MoveInfo)),
  stages: List(learn.StageSummary),
  phase1: Int,
) -> Session {
  let states =
    moves
    |> list.scan(start, cube.apply_move)
    |> list.prepend(start)
    |> list.map(facelets.from_cube)
  Session(
    moves: arr.from_list(moves),
    states: arr.from_list(states),
    infos: infos,
    stages: stages,
    phase1: phase1,
    index: 0,
    anim: None,
    playing: False,
    token: 0,
  )
}

fn open_session(m: Model, session: Session) -> Model {
  let m =
    Model(..m, session: Some(session), notice: None, angle: #(-28.0, -36.0))
  focus(m, session.index)
}

// ---------------------------------------------------------------- Schritte

fn with_session(
  m: Model,
  f: fn(Session) -> #(Model, Effect(Msg)),
) -> #(Model, Effect(Msg)) {
  case m.session {
    Some(s) -> f(s)
    None -> #(m, effect.none())
  }
}

fn put(m: Model, s: Session) -> Model {
  Model(..m, session: Some(s))
}

fn stop_play(s: Session) -> Session {
  Session(..s, playing: False)
}

/// Ansicht zur Seite des Zuges Nr. `index` wenden (wenn „automatisch wenden“ an ist).
fn focus(m: Model, index: Int) -> Model {
  case m.session, m.follow {
    Some(s), True ->
      case index < arr.length(s.moves) {
        True -> face_view(m, arr.at(s.moves, index).face)
        False -> m
      }
    _, _ -> m
  }
}

fn face_view(m: Model, face: cube.Face) -> Model {
  case m.follow {
    False -> m
    True -> {
      let #(_, ry) = m.angle
      let #(target_rx, target_ry) = cube3d.view_for_face(face)
      Model(..m, angle: #(target_rx, cube3d.nearest_angle(ry, target_ry)))
    }
  }
}

/// Direkt zu Zug Nr. `index` springen (ohne Animation).
fn jump(m: Model, s: Session, index: Int) -> #(Model, Effect(Msg)) {
  case s.anim {
    Some(_) -> #(m, effect.none())
    None -> {
      let s = Session(..s, index: index)
      #(focus(put(m, s), index), effect.none())
    }
  }
}

/// Einen Zug animiert vor- oder zurückgehen.
fn step(m: Model, s: Session, forward: Bool) -> #(Model, Effect(Msg)) {
  let n = arr.length(s.moves)
  let possible = case forward {
    True -> s.index < n
    False -> s.index > 0
  }
  case s.anim, possible {
    None, True -> {
      let move = case forward {
        True -> arr.at(s.moves, s.index)
        False -> cube.invert(arr.at(s.moves, s.index - 1))
      }
      let token = s.token + 1
      let s =
        Session(
          ..s,
          anim: Some(Anim(move, forward, False, token)),
          token: token,
        )
      let m = face_view(put(m, s), move.face)
      let duration = model.duration(m.speed)
      #(
        m,
        effect.batch([
          effect.after_paint(fn(dispatch, _) {
            dispatch(model.AnimStarted(token))
          }),
          browser.after(duration + 60, model.AnimFinished(token)),
        ]),
      )
    }
    _, _ -> #(put(m, Session(..s, playing: False)), effect.none())
  }
}

fn finish_animation(m: Model, s: Session, token: Int) -> #(Model, Effect(Msg)) {
  case s.anim {
    Some(a) if a.token == token -> {
      let n = arr.length(s.moves)
      let index = case a.forward {
        True -> s.index + 1
        False -> s.index - 1
      }
      let playing = s.playing && a.forward && index < n
      let s = Session(..s, index: index, anim: None, playing: playing)
      let pause = int_max(120, model.duration(m.speed) * 35 / 100)
      let next = case playing {
        True -> browser.after(pause, model.PlayTick(token))
        False -> effect.none()
      }
      #(put(m, s), next)
    }
    _ -> #(m, effect.none())
  }
}

fn int_max(a: Int, b: Int) -> Int {
  case a > b {
    True -> a
    False -> b
  }
}

fn key_pressed(m: Model, key: String) -> #(Model, Effect(Msg)) {
  case m.session, m.help_open {
    Some(_), False ->
      case key {
        "ArrowRight" -> update(m, model.Next)
        "ArrowLeft" -> update(m, model.Prev)
        " " -> update(m, model.TogglePlay)
        _ -> #(m, effect.none())
      }
    _, _ -> #(m, effect.none())
  }
}
