// External LiveView hooks — add new hooks here and they're automatically registered.
// Each hook is a plain JS object with at least a mounted() method.
// See: https://hexdocs.pm/phoenix_live_view/js-interop.html
//
// Hook naming convention: PascalCase, matches phx-hook="HookName" in templates.

import { MapHook } from "./map"
import { CharacterCounter, ClickCounter, DropZone, Typewriter } from "./showcase"

export const Hooks = {
  Map: MapHook,
  CharacterCounter,
  ClickCounter,
  DropZone,
  Typewriter,
}
