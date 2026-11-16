# 🧩 Zauberwürfel-Löser (Gleam)

Ein Zauberwürfel-Löser für den 3×3×3, der komplett im Browser läuft: Farben eintragen,
dann Zug für Zug (mit 3D-Animation) zur Lösung geführt werden. Geschrieben in
[Gleam](https://gleam.run), Oberfläche mit [Lustre](https://hexdocs.pm/lustre/).

Zwei Lösungswege:

- **Lernmodus** – Anfängermethode in 7 Stufen (Kreuz, Ecken, Mittelschicht, gelbes Kreuz,
  gelbe Fläche, Ecken, Kanten) mit Erklärungen zu jeder Stufe und jedem Baustein.
- **Kurze Lösung** – Zwei-Phasen-Algorithmus nach Kociemba, meist 18–22 Züge.

## Bauen und testen

```sh
gleam test        # Tests (JavaScript-Ziel, braucht Node)
./build.sh        # erzeugt app.js (gleam build + esbuild)
```

`index.html`, `style.css` und `app.js` bilden die fertige Seite (statisch, z. B. GitHub Pages).
Lokal ausprobieren: `python3 -m http.server` und <http://localhost:8000> öffnen
(ES-Module laufen nicht über `file://`).

## Aufbau

| Modul | Aufgabe |
|---|---|
| `rubixcube/cube` | Seiten, Züge, Würfelzustand (Permutation + Orientierung von Ecken und Kanten) |
| `rubixcube/facelets` | 54 Aufkleber ↔ Würfelzustand, Prüfung auf Lösbarkeit (typisierte Fehler) |
| `rubixcube/coords` | Koordinaten für den Zwei-Phasen-Algorithmus (Twist, Flip, Slice, Permutationen) |
| `rubixcube/twophase` | Zugtabellen, Abstandstabellen (BFS), IDA*-Suche in zwei Phasen |
| `rubixcube/learn` | Anfängermethode: Kürzeste-Wege-Suche über bekannte Bausteine |
| `rubixcube/ui/*` | Lustre-App: `model`, `update`, `view`, 3D-Würfel (`cube3d`) |
| `rubixcube_ffi.mjs` | Dünne JS-Schicht: schnelle Arrays, Timer, Tastatur |

Der Kern ist rein funktional; veränderliche Arrays gibt es nur beim Aufbau der
Suchtabellen (`rubixcube/table`), danach werden sie nur gelesen.
