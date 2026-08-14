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
import { GrimoireBookHook }   from './grimoire-book'
import { MapEditorHook }      from './map-editor'
import { CombatLogHook }      from './combat-log'
import { TelegramAuthHook }   from './telegram-auth'
import { AtmosphereAudioHook } from './atmosphere-audio'

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
  GrimoireBook:   GrimoireBookHook,
  MapEditor:      MapEditorHook,
  CombatLog:      CombatLogHook,
  TelegramAuth:   TelegramAuthHook,
  AtmosphereAudio: AtmosphereAudioHook,
}
