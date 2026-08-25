export type PlaybackStatus = "stopped" | "paused" | "playing" | "loading";

export interface TrackSummary {
  id: string;
  type: string;
  title: string;
  artist: string;
  album: string;
  artwork: string;
  duration: number;
}

export interface PlayerState {
  version: 1;
  updatedAt: number;
  connected: boolean;
  authorized: boolean;
  playback: PlaybackStatus;
  current: TrackSummary | null;
  elapsed: number;
  duration: number;
  volume: number;
  shuffle: boolean;
  repeat: "none" | "one" | "all";
  queuePosition: number;
  queue: TrackSummary[];
  error: string;
}

export const emptyPlayerState = (): PlayerState => ({
  version: 1,
  updatedAt: Date.now(),
  connected: false,
  authorized: false,
  playback: "stopped",
  current: null,
  elapsed: 0,
  duration: 0,
  volume: 1,
  shuffle: false,
  repeat: "none",
  queuePosition: -1,
  queue: [],
  error: "",
});

const string = (value: unknown, fallback = "") =>
  typeof value === "string" ? value.slice(0, 4096) : fallback;

const number = (value: unknown, fallback = 0) => {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : fallback;
};

export function normalizeTrack(value: unknown): TrackSummary | null {
  if (!value || typeof value !== "object") return null;
  const track = value as Record<string, unknown>;
  return {
    id: string(track.id),
    type: string(track.type, "songs"),
    title: string(track.title, "Unknown track"),
    artist: string(track.artist, "Unknown artist"),
    album: string(track.album),
    artwork: string(track.artwork),
    duration: Math.max(0, number(track.duration)),
  };
}

export function normalizePlayerState(value: unknown): PlayerState {
  const input = value && typeof value === "object" ? value as Record<string, unknown> : {};
  const playbackValues = new Set<PlaybackStatus>(["stopped", "paused", "playing", "loading"]);
  const repeatValues = new Set(["none", "one", "all"]);
  const playback = string(input.playback) as PlaybackStatus;
  const repeat = string(input.repeat);
  const queue = Array.isArray(input.queue)
    ? input.queue.slice(0, 500).map(normalizeTrack).filter((item): item is TrackSummary => item !== null)
    : [];

  return {
    version: 1,
    updatedAt: Date.now(),
    connected: Boolean(input.connected),
    authorized: Boolean(input.authorized),
    playback: playbackValues.has(playback) ? playback : "stopped",
    current: normalizeTrack(input.current),
    elapsed: Math.max(0, number(input.elapsed)),
    duration: Math.max(0, number(input.duration)),
    volume: Math.max(0, Math.min(1, number(input.volume, 1))),
    shuffle: Boolean(input.shuffle),
    repeat: repeatValues.has(repeat) ? repeat as PlayerState["repeat"] : "none",
    queuePosition: Math.trunc(number(input.queuePosition, -1)),
    queue,
    error: string(input.error),
  };
}
