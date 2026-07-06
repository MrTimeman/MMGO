import { MapHook }            from './map'
import { PlayMapHook }        from './play-map'
import { HexMapHook }         from './hex-map'
import { EventScrollHook }    from './event-scroll'
import { StudyDeskHook }      from './study-desk'
import { TravelCompassHook }  from './travel-compass'
import { DuelChallengeHook }  from './duel-challenge'
import { BaseInteriorHook }   from './base-interior'
import { ExpeditionLogHook }  from './expedition-log'
import { WantedBoardHook }    from './wanted-board'
import { GuildHallHook }      from './guild-hall'
import { SpellCircleHook }    from './spell-circle'
import { GrimoireShelfHook }  from './grimoire-shelf'
import { MapEditorHook }      from './map-editor'

export const Hooks = {
  Map:            MapHook,
  PlayMap:        PlayMapHook,
  HexMap:         HexMapHook,
  EventScroll:    EventScrollHook,
  StudyDesk:      StudyDeskHook,
  TravelCompass:  TravelCompassHook,
  DuelChallenge:  DuelChallengeHook,
  BaseInterior:   BaseInteriorHook,
  ExpeditionLog:  ExpeditionLogHook,
  WantedBoard:    WantedBoardHook,
  GuildHall:      GuildHallHook,
  SpellCircle:    SpellCircleHook,
  GrimoireShelf:  GrimoireShelfHook,
  MapEditor:      MapEditorHook,
}
