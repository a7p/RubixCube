//// Unveränderliche Arrays mit O(1)-Zugriff (JavaScript-Arrays).
//// Gleam-Listen sind verkettet – für Würfelzustände und Tabellen brauchen wir Indexzugriff.

import gleam/list

pub type Arr(a)

@external(javascript, "../rubixcube_ffi.mjs", "arrGenerate")
pub fn generate(size: Int, with: fn(Int) -> a) -> Arr(a)

@external(javascript, "../rubixcube_ffi.mjs", "arrAt")
pub fn at(array: Arr(a), index: Int) -> a

@external(javascript, "../rubixcube_ffi.mjs", "arrLength")
pub fn length(array: Arr(a)) -> Int

@external(javascript, "../rubixcube_ffi.mjs", "arrFromList")
pub fn from_list(list: List(a)) -> Arr(a)

@external(javascript, "../rubixcube_ffi.mjs", "arrToList")
pub fn to_list(array: Arr(a)) -> List(a)

/// Index des ersten Elements, das `predicate` erfüllt.
pub fn find_index(array: Arr(a), predicate: fn(a) -> Bool) -> Int {
  find_from(array, predicate, 0)
}

fn find_from(array: Arr(a), predicate: fn(a) -> Bool, i: Int) -> Int {
  case i >= length(array) || predicate(at(array, i)) {
    True -> i
    False -> find_from(array, predicate, i + 1)
  }
}

pub fn map(array: Arr(a), f: fn(a) -> b) -> Arr(b) {
  generate(length(array), fn(i) { f(at(array, i)) })
}

pub fn set(array: Arr(a), index: Int, value: a) -> Arr(a) {
  generate(length(array), fn(i) {
    case i == index {
      True -> value
      False -> at(array, i)
    }
  })
}

pub fn count(array: Arr(a), predicate: fn(a) -> Bool) -> Int {
  array |> to_list |> list.count(predicate)
}
