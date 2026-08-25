import { describe, expect, test } from "bun:test";
import { normalizePlayerState } from "../src/player-state";

describe("normalizePlayerState", () => {
  test("clamps untrusted timing and volume data", () => {
    const state = normalizePlayerState({
      connected: true,
      playback: "playing",
      elapsed: -10,
      duration: "240",
      volume: 9,
      queuePosition: 1.9,
    });
    expect(state.connected).toBe(true);
    expect(state.playback).toBe("playing");
    expect(state.elapsed).toBe(0);
    expect(state.duration).toBe(240);
    expect(state.volume).toBe(1);
    expect(state.queuePosition).toBe(1);
  });

  test("normalizes a bounded queue", () => {
    const queue = Array.from({ length: 510 }, (_, id) => ({ id: String(id), title: `Track ${id}` }));
    const state = normalizePlayerState({ queue, current: queue[0] });
    expect(state.queue).toHaveLength(500);
    expect(state.current?.title).toBe("Track 0");
  });
});
