//// Die wenigen Browser-Funktionen, die Lustre nicht selbst anbietet.

import lustre/effect.{type Effect}

@external(javascript, "../../rubixcube_ffi.mjs", "after")
fn after_ffi(ms: Int, callback: fn() -> Nil) -> Nil

@external(javascript, "../../rubixcube_ffi.mjs", "onKey")
fn on_key_ffi(callback: fn(String) -> Nil) -> Nil

@external(javascript, "../../rubixcube_ffi.mjs", "stickerAt")
fn sticker_at_ffi(x: Float, y: Float) -> Result(Int, Nil)

@external(javascript, "../../rubixcube_ffi.mjs", "random")
pub fn random(n: Int) -> Int

/// Nach `ms` Millisekunden die Nachricht senden.
pub fn after(ms: Int, message: msg) -> Effect(msg) {
  effect.from(fn(dispatch) { after_ffi(ms, fn() { dispatch(message) }) })
}

/// Tastendrücke als Nachrichten.
pub fn keys(to_message: fn(String) -> msg) -> Effect(msg) {
  effect.from(fn(dispatch) { on_key_ffi(fn(key) { dispatch(to_message(key)) }) })
}

/// Welches Aufkleber-Feld liegt unter dem Punkt (x, y)? Dann `to_message(index)`.
pub fn sticker_under(
  x: Float,
  y: Float,
  to_message: fn(Int) -> msg,
) -> Effect(msg) {
  effect.from(fn(dispatch) {
    case sticker_at_ffi(x, y) {
      Ok(index) -> dispatch(to_message(index))
      Error(_) -> Nil
    }
  })
}
