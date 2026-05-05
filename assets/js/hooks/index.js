import { MapHook }            from './map'
import { EventScrollHook }    from './event-scroll'
import { TravelCompassHook }  from './travel-compass'
import { DuelChallengeHook }  from './duel-challenge'
import { BaseInteriorHook }   from './base-interior'
import { ExpeditionLogHook }  from './expedition-log'
import { SpellCircleHook }    from './spell-circle'
import { GrimoireShelfHook }  from './grimoire-shelf'
export const Hooks = {
  Map:            MapHook,
  EventScroll:    EventScrollHook,
  TravelCompass:  TravelCompassHook,
  DuelChallenge:  DuelChallengeHook,
  BaseInterior:   BaseInteriorHook,
  ExpeditionLog:  ExpeditionLogHook,
  SpellCircle:    SpellCircleHook,
  GrimoireShelf:  GrimoireShelfHook,
}
