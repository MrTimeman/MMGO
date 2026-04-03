export type DataSource = "api" | "mock";
export type EntryMode = "first_open" | "resume" | "deep_link" | "recovery";
export type LocationKind = "city" | "tower" | "wilderness" | "base" | "dungeon_entrance";
export type RouteKind = "road" | "wilds" | "expedition";

export interface RealmSummary {
  slug: string;
  name: string;
  description: string;
}

export interface AccountSummary {
  displayName: string;
  handle: string;
  locale: string;
}

export interface CharacterSummary {
  name: string;
  level: number;
  status: "new" | "active" | "frozen" | "retired";
  schoolPair: [string, string];
  currentLocationName: string;
  title: string;
}

export interface EntryRecovery {
  title: string;
  body: string;
}

export interface EntryState {
  mode: EntryMode;
  realm: RealmSummary;
  account: AccountSummary | null;
  character: CharacterSummary | null;
  notice?: string;
  recovery?: EntryRecovery;
  targetLabel?: string;
}

export interface MapMarker {
  id: string;
  name: string;
  kind: LocationKind;
  x: number;
  y: number;
  region: string;
  summary: string;
  entryBody: string;
  travelLabel: string;
  accent: string;
  localActions: LocationAction[];
  intel: string[];
  localFeed: LogEvent[];
}

export interface MapRoute {
  id: string;
  from: string;
  to: string;
  kind: RouteKind;
}

export interface MapState {
  title: string;
  subtitle: string;
  markers: MapMarker[];
  routes: MapRoute[];
  playerMarkerId: string;
  imageUrl?: string;
  imageCredit?: string;
}

export interface LocationAction {
  label: string;
  detail: string;
  emphasis?: "primary" | "secondary";
}

export interface GrimoireSummary {
  id: string;
  name: string;
  status: "draft" | "sealed" | "active";
  capacity: number;
  prepared: number;
  school: string;
}

export interface StudySummary {
  program: string;
  track: string;
  schools: string[];
  progress: number;
  etaLabel: string;
}

export interface OrganizationSummary {
  name: string;
  kind: string;
  role: string;
  fastTravelEnabled: boolean;
  linkedLocations: string[];
}

export interface LogEvent {
  id: string;
  kind: "narrative" | "encounter" | "reward";
  text: string;
}

export interface ShellState {
  realm: RealmSummary;
  account: AccountSummary;
  character: CharacterSummary;
  notice?: string;
  currentLocationId: string;
  selectedLocationId: string;
  timerLabel: string;
  supplyLabel: string;
  weightLabel: string;
  map: MapState;
  grimoires: GrimoireSummary[];
  study: StudySummary;
  organization: OrganizationSummary;
  log: LogEvent[];
}

export interface ClientSession {
  source: DataSource;
  view: "entry" | "shell";
  entry: EntryState | null;
  shell: ShellState | null;
}
