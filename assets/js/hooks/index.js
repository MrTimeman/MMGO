// External LiveView hooks — add new hooks here and they're automatically registered.
// Each hook is a plain JS object with at least a mounted() method.
// See: https://hexdocs.pm/phoenix_live_view/js-interop.html
//
// Hook naming convention: PascalCase, matches phx-hook="HookName" in templates.
// All hooks call pushEvent("hook_mounted", {hook: "HookName"}) on mount so the
// LiveView knows when to push the initial state.

import { MapHook }            from './map'
import { EventScrollHook }    from './event-scroll'
import { StudyDeskHook }      from './study-desk'
import { TravelCompassHook }  from './travel-compass'
import { DuelChallengeHook }  from './duel-challenge'
import { BaseInteriorHook }   from './base-interior'
import { ExpeditionLogHook }  from './expedition-log'
import { WantedBoardHook }    from './wanted-board'
import { GuildHallHook }      from './guild-hall'

export const Hooks = {
  Map:            MapHook,
  EventScroll:    EventScrollHook,
  StudyDesk:      StudyDeskHook,
  TravelCompass:  TravelCompassHook,
  DuelChallenge:  DuelChallengeHook,
  BaseInterior:   BaseInteriorHook,
  ExpeditionLog:  ExpeditionLogHook,
  WantedBoard:    WantedBoardHook,
  GuildHall:      GuildHallHook,
}
