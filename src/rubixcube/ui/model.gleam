//// Zustand und Nachrichten der Oberfläche (Model-View-Update).

import gleam/option.{type Option, None}
import rubixcube/arr.{type Arr}
import rubixcube/cube.{type Face, type Move}
import rubixcube/facelets.{type Facelets}
import rubixcube/learn
import rubixcube/twophase

pub type Mode {
  Learn
  Short
}

pub type Notice {
  Info(String)
  Failure(String)
  Success(String)
}

/// Eine laufende Drehanimation. `forward = False` bedeutet: Zug rückgängig machen.
pub type Anim {
  Anim(move: Move, forward: Bool, started: Bool, token: Int)
}

/// Eine berechnete Lösung, durch die man Schritt für Schritt geht.
pub type Session {
  Session(
    moves: Arr(Move),
    /// Zustand vor Zug 0, nach Zug 1, … (Länge = Züge + 1)
    states: Arr(Facelets),
    /// Nur im Lernmodus: Hinweise zu jedem Zug und Übersicht der Stufen.
    infos: Option(Arr(learn.MoveInfo)),
    stages: List(learn.StageSummary),
    /// Nur bei der kurzen Lösung: Länge der Phase 1.
    phase1: Int,
    index: Int,
    anim: Option(Anim),
    playing: Bool,
    token: Int,
  )
}

pub type Model {
  Model(
    stickers: Facelets,
    brush: Face,
    mode: Mode,
    notice: Option(Notice),
    calculating: Bool,
    painting: Bool,
    session: Option(Session),
    help_open: Bool,
    /// Blickwinkel auf den Würfel in Grad: (um X, um Y)
    angle: #(Float, Float),
    drag: Option(#(Float, Float)),
    follow: Bool,
    speed: Int,
    solver_tables: Option(twophase.Tables),
    learn_tables: Option(learn.Prepared),
  )
}

pub type Msg {
  // Eingabe
  PickBrush(Face)
  PaintAt(Float, Float)
  PaintMoved(Float, Float)
  Paint(Int)
  PaintEnd
  SetMode(Mode)
  Scramble
  Reset
  Solve
  Compute
  // Lösungsansicht
  Back
  Next
  Prev
  First
  Last
  TogglePlay
  JumpToMove(Int)
  JumpToStage(Int)
  AnimStarted(Int)
  AnimFinished(Int)
  PlayTick(Int)
  // Ansicht
  DragStart(Float, Float)
  DragMove(Float, Float)
  DragEnd
  FlipView
  SetFollow(Bool)
  SetSpeed(Int)
  HelpOpen
  HelpClose
  KeyPressed(String)
}

pub fn initial() -> Model {
  Model(
    stickers: facelets.solved(),
    brush: cube.U,
    mode: Learn,
    notice: None,
    calculating: False,
    painting: False,
    session: None,
    help_open: False,
    angle: #(-28.0, -36.0),
    drag: None,
    follow: True,
    speed: 55,
    solver_tables: None,
    learn_tables: None,
  )
}

/// Dauer einer Drehanimation in Millisekunden.
pub fn duration(speed: Int) -> Int {
  1300 - speed * 115 / 10
}
