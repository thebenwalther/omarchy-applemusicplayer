import { describe, expect, test } from "bun:test";
import { readFileSync } from "node:fs";

const source = readFileSync(new URL("../integration/omarchy-plugin/MediaController.js", import.meta.url), "utf8");
const qmlModule = { exports: {} as Record<string, (...args: any[]) => any> };
new Function("module", source)(qmlModule);
const controller = qmlModule.exports;

function player(pid: number, overrides: Record<string, unknown> = {}) {
  return {
    dbusName: `org.mpris.MediaPlayer2.chromium.instance${pid}`,
    identity: "Chromium",
    isPlaying: false,
    ...overrides,
  };
}

describe("Apple Music source detection", () => {
  test("matches the web-app PID to Chromium's MPRIS instance", () => {
    const pids = controller.appleMusicPids(JSON.stringify([
      { class: "firefox", pid: 9 },
      { class: "chrome-music.apple.com__-Default", pid: 5173 },
    ]));
    expect(pids).toEqual([5173]);
    expect(controller.applePlayerKey([player(5173)], pids)).toEndWith("instance5173");
  });

  test("prefers a playing manual source, then playing Apple Music", () => {
    const apple = player(10, { isPlaying: true });
    const spotify = { dbusName: "org.mpris.MediaPlayer2.spotify", identity: "Spotify", isPlaying: true };
    expect(controller.choosePlayerKey([apple, spotify], [10], spotify.dbusName, apple.dbusName)).toBe(spotify.dbusName);
    spotify.isPlaying = false;
    expect(controller.choosePlayerKey([apple, spotify], [10], spotify.dbusName, spotify.dbusName)).toBe(apple.dbusName);
  });

  test("falls back cleanly when PID correlation is unavailable", () => {
    const fallback = player(20);
    expect(controller.choosePlayerKey([fallback], [], "", fallback.dbusName)).toBe(fallback.dbusName);
  });
});

describe("formatting and timers", () => {
  test("formats track and long-form countdown times", () => {
    expect(controller.formatTime(65)).toBe("1:05");
    expect(controller.formatTime(3661)).toBe("1:01:01");
    expect(controller.timerDeadline(15, 1000)).toBe(901000);
    expect(controller.timerRemaining(61000, 1000)).toBe("1:00");
  });

  test("ends on either the track boundary or a track change", () => {
    const track = player(30, { trackTitle: "A", trackArtist: "B", length: 180, position: 179 });
    const signature = controller.trackSignature(track);
    expect(controller.endOfTrackReached(track, signature, 1.5)).toBe(true);
    track.position = 10;
    expect(controller.endOfTrackReached(track, signature, 1.5)).toBe(false);
    track.trackTitle = "Next";
    expect(controller.endOfTrackReached(track, signature, 1.5)).toBe(true);
  });

  test("builds useful source labels", () => {
    const apple = player(40, { trackTitle: "Song", trackArtist: "Artist" });
    expect(controller.sourceName(apple, apple.dbusName)).toBe("Apple Music");
    expect(controller.sourceDetail(apple)).toBe("Song — Artist");
  });

  test("only advertises source-supported playback modes", () => {
    expect(controller.capabilities({ shuffleSupported: false, loopSupported: false })).toEqual({ shuffle: false, loop: false });
    expect(controller.capabilities({ shuffleSupported: true, loopSupported: false })).toEqual({ shuffle: true, loop: false });
  });
});
