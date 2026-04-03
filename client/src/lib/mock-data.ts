import type {
  AccountSummary,
  CharacterSummary,
  ClientSession,
  EntryMode,
  EntryState,
  LocationAction,
  LogEvent,
  MapMarker,
  RealmSummary,
  ShellState
} from "./types";

const realm: RealmSummary = {
  slug: "canonical",
  name: "[Realm name]",
  description: "[Realm description placeholder]"
};

const account: AccountSummary = {
  displayName: "[Display name]",
  handle: "player-handle",
  locale: "en"
};

const character: CharacterSummary = {
  name: "[Character name]",
  level: 7,
  status: "active",
  schoolPair: ["Fire", "Death"],
  currentLocationName: "Kamnedol",
  title: "[Character title]"
};

function buildActionPlaceholders(count: number): LocationAction[] {
  return Array.from({ length: count }, (_, index) => ({
    label: index === 0 ? "[Primary action placeholder]" : `[Secondary action placeholder ${index}]`,
    detail: `[Action detail placeholder ${index + 1}]`,
    emphasis: index === 0 ? "primary" : "secondary"
  }));
}

function buildIntelPlaceholders(): string[] {
  return ["[Location note placeholder 1]", "[Location note placeholder 2]"];
}

function buildFeedPlaceholders(prefix: string): LogEvent[] {
  return [
    {
      id: `${prefix}-feed-1`,
      kind: "narrative",
      text: "[Feed line placeholder 1]"
    },
    {
      id: `${prefix}-feed-2`,
      kind: "reward",
      text: "[Feed line placeholder 2]"
    }
  ];
}

const markers: MapMarker[] = [
  {
    id: "kamnedol",
    name: "Kamnedol",
    kind: "city",
    x: 47.5,
    y: 50.5,
    region: "Crown Roads",
    summary: "[Location summary placeholder]",
    entryBody: "[Entered location text placeholder]",
    travelLabel: "[Travel text placeholder]",
    accent: "amber",
    localActions: buildActionPlaceholders(3),
    intel: buildIntelPlaceholders(),
    localFeed: buildFeedPlaceholders("kam")
  },
  {
    id: "academy",
    name: "Academy Quarter",
    kind: "city",
    x: 29,
    y: 39,
    region: "Mountain Archive",
    summary: "[Location summary placeholder]",
    entryBody: "[Entered location text placeholder]",
    travelLabel: "[Travel text placeholder]",
    accent: "ivory",
    localActions: buildActionPlaceholders(3),
    intel: buildIntelPlaceholders(),
    localFeed: buildFeedPlaceholders("aca")
  },
  {
    id: "tower",
    name: "Tower of Order",
    kind: "tower",
    x: 46,
    y: 19,
    region: "Northern Highline",
    summary: "[Location summary placeholder]",
    entryBody: "[Entered location text placeholder]",
    travelLabel: "[Travel text placeholder]",
    accent: "cyan",
    localActions: buildActionPlaceholders(2),
    intel: buildIntelPlaceholders(),
    localFeed: buildFeedPlaceholders("tow")
  },
  {
    id: "wilds",
    name: "Glasswind Expanse",
    kind: "wilderness",
    x: 83,
    y: 77,
    region: "Bog Frontier",
    summary: "[Location summary placeholder]",
    entryBody: "[Entered location text placeholder]",
    travelLabel: "[Travel text placeholder]",
    accent: "sage",
    localActions: buildActionPlaceholders(2),
    intel: buildIntelPlaceholders(),
    localFeed: buildFeedPlaceholders("wil")
  },
  {
    id: "crypt",
    name: "Hollow Crypt",
    kind: "dungeon_entrance",
    x: 82.5,
    y: 49.5,
    region: "Eastern Rings",
    summary: "[Location summary placeholder]",
    entryBody: "[Entered location text placeholder]",
    travelLabel: "[Travel text placeholder]",
    accent: "red",
    localActions: buildActionPlaceholders(2),
    intel: buildIntelPlaceholders(),
    localFeed: buildFeedPlaceholders("cry")
  },
  {
    id: "ash-home",
    name: "Ash Home",
    kind: "base",
    x: 43.5,
    y: 84,
    region: "Southern Basin",
    summary: "[Location summary placeholder]",
    entryBody: "[Entered location text placeholder]",
    travelLabel: "[Travel text placeholder]",
    accent: "rose",
    localActions: buildActionPlaceholders(2),
    intel: buildIntelPlaceholders(),
    localFeed: buildFeedPlaceholders("base")
  }
];

const routes = [
  { id: "road-capital-archive", from: "kamnedol", to: "academy", kind: "road" },
  { id: "road-capital-tower", from: "kamnedol", to: "tower", kind: "road" },
  { id: "road-capital-home", from: "kamnedol", to: "ash-home", kind: "road" },
  { id: "road-capital-crypt", from: "kamnedol", to: "crypt", kind: "road" },
  { id: "wilds-capital-bog", from: "kamnedol", to: "wilds", kind: "wilds" },
  { id: "wilds-home-bog", from: "ash-home", to: "wilds", kind: "wilds" }
] as const;

function buildShellState(selectedLocationId: string, notice?: string): ShellState {
  return {
    realm,
    account,
    character,
    notice,
    currentLocationId: "kamnedol",
    selectedLocationId,
    timerLabel: "[Journey timer placeholder]",
    supplyLabel: "[Supply placeholder]",
    weightLabel: "[Carry load placeholder]",
    map: {
      title: "Atlas",
      subtitle: "[Atlas subtitle placeholder]",
      markers,
      routes: [...routes],
      playerMarkerId: "kamnedol",
      imageUrl: "/realm-atlas.jpg",
      imageCredit: "[Atlas credit placeholder]"
    },
    grimoires: [
      {
        id: "ember-codex",
        name: "[Grimoire placeholder 1]",
        status: "active",
        capacity: 8,
        prepared: 6,
        school: "Fire"
      },
      {
        id: "velvet-nocturne",
        name: "[Grimoire placeholder 2]",
        status: "sealed",
        capacity: 6,
        prepared: 2,
        school: "Death"
      },
      {
        id: "ash-ledger",
        name: "[Grimoire placeholder 3]",
        status: "draft",
        capacity: 5,
        prepared: 1,
        school: "Chaos"
      }
    ],
    study: {
      program: "[Study program placeholder]",
      track: "[Study track placeholder]",
      schools: ["Fire", "Death"],
      progress: 61,
      etaLabel: "[Study ETA placeholder]"
    },
    organization: {
      name: "[Organization placeholder]",
      kind: "[Organization kind placeholder]",
      role: "[Organization role placeholder]",
      fastTravelEnabled: true,
      linkedLocations: ["Kamnedol", "Tower of Order", "Ash Home"]
    },
    log: [
      {
        id: "log-1",
        kind: "narrative",
        text: "[Global log placeholder 1]"
      },
      {
        id: "log-2",
        kind: "encounter",
        text: "[Global log placeholder 2]"
      },
      {
        id: "log-3",
        kind: "reward",
        text: "[Global log placeholder 3]"
      }
    ]
  };
}

function buildEntryState(mode: EntryMode): EntryState {
  if (mode === "recovery") {
    return {
      mode,
      realm,
      account: null,
      character: null,
      recovery: {
        title: "[Recovery title placeholder]",
        body: "[Recovery body placeholder]"
      }
    };
  }

  if (mode === "deep_link") {
    return {
      mode,
      realm,
      account,
      character,
      targetLabel: "[Deep-link target placeholder]"
    };
  }

  return {
    mode,
    realm,
    account,
    character
  };
}

export function buildMockSession(mode: string | null): ClientSession {
  switch (mode) {
    case "first_open":
      return {
        source: "mock",
        view: "entry",
        entry: buildEntryState("first_open"),
        shell: buildShellState("kamnedol")
      };
    case "deep_link":
      return {
        source: "mock",
        view: "shell",
        entry: buildEntryState("deep_link"),
        shell: buildShellState("crypt", "[Deep-link notice placeholder]")
      };
    case "invalid_target":
      return {
        source: "mock",
        view: "shell",
        entry: buildEntryState("resume"),
        shell: buildShellState("kamnedol", "[Invalid-target notice placeholder]")
      };
    case "recovery":
      return {
        source: "mock",
        view: "entry",
        entry: buildEntryState("recovery"),
        shell: null
      };
    case "resume":
    default:
      return {
        source: "mock",
        view: "entry",
        entry: buildEntryState("resume"),
        shell: buildShellState("kamnedol")
      };
  }
}
