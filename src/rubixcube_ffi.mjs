// Dünne JavaScript-Schicht: schnelle Arrays und ein paar Browser-Funktionen.
// Die Gleam-Seite behandelt Arr als unveränderlich; mutiert wird nur beim Aufbau
// der Suchtabellen (Ints/Bytes) in rubixcube/table.gleam.
import { List } from "./gleam.mjs";

export function arrGenerate(size, f) {
  const a = new Array(size);
  for (let i = 0; i < size; i++) a[i] = f(i);
  return a;
}
export const arrAt = (a, i) => a[i];
export const arrLength = (a) => a.length;
export const arrFromList = (list) => list.toArray();
export const arrToList = (a) => List.fromArray(a);

export const intsGenerate = (size, f) => {
  const a = new Int32Array(size);
  for (let i = 0; i < size; i++) a[i] = f(i);
  return a;
};
export const intsNew = (size) => new Int32Array(size);
export const intsGet = (a, i) => a[i];
export const intsSet = (a, i, v) => { a[i] = v; };

export const bytesNew = (size, fill) => new Uint8Array(size).fill(fill);
export const bytesGet = (a, i) => a[i];
export const bytesSet = (a, i, v) => { a[i] = v; };

export const nowMs = () => Math.floor(performance.now());

// ---- Browser ---------------------------------------------------------------
import { Ok, Error as GError } from "./gleam.mjs";

export const after = (ms, callback) => { setTimeout(() => callback(), ms); };

export const onKey = (callback) => {
  document.addEventListener("keydown", (e) => {
    const tag = e.target && e.target.tagName;
    if (e.key === " " && tag === "BUTTON") return; // Leertaste auf Buttons nicht abfangen
    if (["ArrowLeft", "ArrowRight", " "].includes(e.key)) e.preventDefault();
    callback(e.key);
  });
};

/// Aufkleber-Index (data-idx) des Feldes unter einem Bildschirmpunkt.
export const stickerAt = (x, y) => {
  const el = document.elementFromPoint(x, y);
  if (!el || !el.classList.contains("st") || el.classList.contains("center")) return new GError(undefined);
  const idx = Number(el.dataset.idx);
  return Number.isNaN(idx) ? new GError(undefined) : new Ok(idx);
};

export const random = (n) => Math.floor(Math.random() * n);
