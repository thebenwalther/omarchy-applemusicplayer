import { afterEach, describe, expect, test } from "bun:test";
import { chmodSync, existsSync, lstatSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, readlinkSync, rmSync, writeFileSync } from "node:fs";
import { join, resolve } from "node:path";
import { tmpdir } from "node:os";

const repo = resolve(import.meta.dir, "..");
const fixtures: string[] = [];

afterEach(() => {
  for (const fixture of fixtures.splice(0)) rmSync(fixture, { recursive: true, force: true });
});

function stub(directory: string, name: string, body = "exit 0") {
  const path = join(directory, name);
  writeFileSync(path, `#!/usr/bin/env bash\n${body}\n`);
  chmodSync(path, 0o755);
}

function fixture() {
  const home = mkdtempSync(join(tmpdir(), "omarchy-applemusicplayer-"));
  fixtures.push(home);
  const config = join(home, "config");
  const data = join(home, "data");
  const state = join(home, "state");
  const bin = join(home, "bin");
  const stubs = join(home, "stubs");
  mkdirSync(join(config, "hypr"), { recursive: true });
  mkdirSync(join(config, "omarchy", "plugins", "bmw.media"), { recursive: true });
  mkdirSync(join(config, "omarchy", "plugins", "bmw.media.bak.omarchy-applemusicplayer-old"), { recursive: true });
  mkdirSync(stubs);
  writeFileSync(join(config, "hypr", "bindings.lua"), `before\n-- omarchy-applemusicplayer:start\nold alt binding\n-- omarchy-applemusicplayer:end\nafter\n`);
  writeFileSync(join(config, "hypr", "hyprland.lua"), `base\n-- omarchy-applemusicplayer:start\nold mini rule\n-- omarchy-applemusicplayer:end\n`);
  writeFileSync(join(config, "omarchy", "shell.json"), JSON.stringify({ bar: { layout: { left: [], center: [{
    id: "bmw.media",
    dynamicArtworkColor: false,
    barProgress: false,
    motionEnabled: false,
    trackChangeOsd: true,
    rememberSessionHistory: false,
  }, { id: "omarchy.clock" }], right: [] } } }));
  writeFileSync(join(config, "omarchy", "plugins", "bmw.media", "user-file"), "preserve me");
  writeFileSync(join(config, "omarchy", "plugins", "bmw.media.bak.omarchy-applemusicplayer-old", "old-backup"), "preserve me too");
  mkdirSync(join(config, "omarchy-applemusicplayer"), { recursive: true });
  writeFileSync(join(config, "omarchy-applemusicplayer", "config.json"), "credential sentinel");

  stub(stubs, "systemctl", 'printf "systemctl %s\\n" "$*" >> "$CALL_LOG"');
  stub(stubs, "omarchy", 'printf "omarchy %s\\n" "$*" >> "$CALL_LOG"');
  stub(stubs, "hyprctl", '[[ ${1:-} == configerrors ]] || printf "hyprctl %s\\n" "$*" >> "$CALL_LOG"');
  stub(stubs, "update-desktop-database");

  const env = {
    ...process.env,
    HOME: home,
    XDG_CONFIG_HOME: config,
    XDG_DATA_HOME: data,
    XDG_STATE_HOME: state,
    XDG_BIN_HOME: bin,
    CALL_LOG: join(home, "calls.log"),
    PATH: `${stubs}:${process.env.PATH}`,
  };
  return { home, config, data, state, bin, env };
}

function run(script: string, env: Record<string, string | undefined>) {
  return Bun.spawnSync(["bash", join(repo, "scripts", script)], { cwd: repo, env, stdout: "pipe", stderr: "pipe" });
}

describe("installer lifecycle", () => {
  test("migrates, reinstalls idempotently, and uninstalls cleanly", () => {
    const f = fixture();
    const first = run("install.sh", f.env);
    expect(first.exitCode, first.stderr.toString()).toBe(0);

    const plugin = join(f.config, "omarchy", "plugins", "bmw.media");
    expect(lstatSync(plugin).isSymbolicLink()).toBe(true);
    expect(readlinkSync(plugin)).toBe(join(repo, "integration", "omarchy-plugin"));
    expect(existsSync(join(f.bin, "omarchy-music-mini"))).toBe(false);
    expect(existsSync(join(f.config, "systemd", "user", "omarchy-applemusicplayer.service"))).toBe(false);
    expect(existsSync(join(f.config, "omarchy", "plugins", "bmw.media.bak.omarchy-applemusicplayer-old"))).toBe(false);

    const bindings = readFileSync(join(f.config, "hypr", "bindings.lua"), "utf8");
    expect(bindings.match(/omarchy-applemusicplayer:start/g)).toHaveLength(1);
    expect(bindings).toContain("SUPER + SHIFT + M");
    expect(bindings).not.toContain("SUPER + ALT + M");
    expect(readFileSync(join(f.config, "hypr", "hyprland.lua"), "utf8")).not.toContain("omarchy-applemusicplayer:start");

    const shell = JSON.parse(readFileSync(join(f.config, "omarchy", "shell.json"), "utf8"));
    expect(shell.bar.layout.center.map((item: { id: string }) => item.id)).toEqual(["bmw.media", "omarchy.clock"]);
    expect(shell.bar.layout.center[0]).toEqual({
      id: "bmw.media",
      dynamicArtworkColor: false,
      barProgress: false,
      barDisplayMode: "full",
      motionEnabled: false,
      trackChangeOsd: true,
      rememberSessionHistory: false,
    });
    const backups = join(f.state, "omarchy-applemusicplayer", "backups");
    expect(existsSync(backups)).toBe(true);
    const backupEntries = readdirSync(backups, { recursive: true }).map(String);
    expect(backupEntries.some(entry => entry.endsWith("bmw.media/user-file"))).toBe(true);
    expect(backupEntries.some(entry => entry.includes("bmw.media.bak.omarchy-applemusicplayer-old"))).toBe(true);

    const second = run("install.sh", f.env);
    expect(second.exitCode, second.stderr.toString()).toBe(0);
    const bindingsAgain = readFileSync(join(f.config, "hypr", "bindings.lua"), "utf8");
    expect(bindingsAgain.match(/omarchy-applemusicplayer:start/g)).toHaveLength(1);
    const shellAgain = JSON.parse(readFileSync(join(f.config, "omarchy", "shell.json"), "utf8"));
    expect(shellAgain.bar.layout.center.filter((item: { id: string }) => item.id === "bmw.media")).toHaveLength(1);
    expect(shellAgain.bar.layout.center[0].dynamicArtworkColor).toBe(false);
    expect(shellAgain.bar.layout.center[0].barProgress).toBe(false);
    expect(shellAgain.bar.layout.center[0].barDisplayMode).toBe("full");
    expect(shellAgain.bar.layout.center[0].motionEnabled).toBe(false);
    expect(shellAgain.bar.layout.center[0].trackChangeOsd).toBe(true);
    expect(shellAgain.bar.layout.center[0].rememberSessionHistory).toBe(false);

    const uninstall = run("uninstall.sh", f.env);
    expect(uninstall.exitCode, uninstall.stderr.toString()).toBe(0);
    expect(existsSync(plugin)).toBe(false);
    expect(existsSync(join(f.bin, "omarchy-music"))).toBe(false);
    expect(readFileSync(join(f.config, "hypr", "bindings.lua"), "utf8")).not.toContain("omarchy-applemusicplayer:start");
    const shellAfter = JSON.parse(readFileSync(join(f.config, "omarchy", "shell.json"), "utf8"));
    expect(shellAfter.bar.layout.center.some((item: { id: string }) => item.id === "bmw.media")).toBe(false);
    expect(readFileSync(join(f.config, "omarchy-applemusicplayer", "config.json"), "utf8")).toBe("credential sentinel");
  });
});

describe("launcher", () => {
  test("uses a browser-neutral class suffix that matches common Chromium app ids", () => {
    const f = fixture();
    stub(join(f.home, "stubs"), "omarchy", 'printf "%s\\n" "$@" > "$CALL_LOG"');
    const result = Bun.spawnSync(["bash", join(repo, "bin", "omarchy-music")], { env: f.env, stdout: "pipe", stderr: "pipe" });
    expect(result.exitCode, result.stderr.toString()).toBe(0);
    const args = readFileSync(f.env.CALL_LOG!, "utf8").trim().split("\n");
    expect(args.slice(0, 4)).toEqual(["launch", "or", "focus", "webapp"]);
    const expression = new RegExp(`\\b${args[4]}\\b`, "i");
    expect(expression.test("chrome-music.apple.com__-Default")).toBe(true);
    expect(expression.test("chromium-music.apple.com__-Default")).toBe(true);
    expect(expression.test("brave-music.apple.com__-Default")).toBe(true);
  });
});
