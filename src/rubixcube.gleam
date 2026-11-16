//// Zauberwürfel-Löser – Einstiegspunkt: startet die Lustre-Anwendung im Browser.

import lustre
import rubixcube/ui/update
import rubixcube/ui/view

pub fn main() -> Nil {
  let app = lustre.application(update.init, update.update, view.view)
  let assert Ok(_) = lustre.start(app, "#app", Nil)
  Nil
}
