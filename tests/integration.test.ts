import { afterEach, describe, expect, test } from "bun:test";
import {
  chmodSync, cpSync, existsSync, lstatSync, mkdirSync, mkdtempSync, readFileSync,
  readdirSync, readlinkSync, realpathSync, rmSync, symlinkSync, writeFileSync,
} from "node:fs";
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

function runAt(root: string, script: string, env: Record<string, string | undefined>, args: string[] = []) {
  return Bun.spawnSync(["bash", join(root, "scripts", script), ...args], { cwd: root, env, stdout: "pipe", stderr: "pipe" });
}

function copyCheckout(destination: string) {
  cpSync(repo, destination, {
    recursive: true,
    filter: source => ![".git", "node_modules"].includes(source.split("/").at(-1) || ""),
  });
}

function runtimeDirectories(data: string) {
  const releases = join(data, "omarchy-applemusicplayer", "releases");
  if (!existsSync(releases)) return [];
  return readdirSync(releases, { recursive: true, withFileTypes: true })
    .filter(entry => entry.isDirectory() && /^\d{8}-\d{6}-\d+$/.test(entry.name))
    .map(entry => entry.name);
}

describe("release metadata", () => {
  test("keeps package, plugin, installer, and changelog versions synchronized", () => {
    const version = readFileSync(join(repo, "VERSION"), "utf8").trim();
    expect(JSON.parse(readFileSync(join(repo, "package.json"), "utf8")).version).toBe(version);
    expect(JSON.parse(readFileSync(join(repo, "integration", "omarchy-plugin", "manifest.json"), "utf8")).version).toBe(version);
    const defaults = JSON.parse(readFileSync(join(repo, "integration", "preferences.json"), "utf8"));
    const controllerSource = readFileSync(join(repo, "integration", "omarchy-plugin", "MediaController.js"), "utf8");
    const qmlModule = { exports: {} as Record<string, () => unknown> };
    new Function("module", controllerSource)(qmlModule);
    expect(qmlModule.exports.preferenceDefaults()).toEqual(defaults);
    expect(readFileSync(join(repo, "CHANGELOG.md"), "utf8")).toContain(`## [${version}]`);
    expect(readFileSync(join(repo, "scripts", "install.sh"), "utf8")).toContain('VERSION=$(tr -d');
  });
});

describe("installer lifecycle", () => {
  test("migrates a v3.2.1 copied runtime to v3.3 and keeps it as rollback", () => {
    const f = fixture();
    const installRoot = join(f.data, "omarchy-applemusicplayer");
    const previous = join(installRoot, "releases", "3.2.1", "20260826-120000-321");
    mkdirSync(join(previous, "plugin"), { recursive: true });
    mkdirSync(join(previous, "bin"), { recursive: true });
    writeFileSync(join(previous, "plugin", "legacy-runtime"), "v3.2.1");
    symlinkSync(previous, join(installRoot, "current"));
    writeFileSync(join(installRoot, "install.json"), JSON.stringify({
      mode: "copy", version: "3.2.1", sourceRepo: "/deleted/v3.2.1/checkout", runtime: previous,
    }));

    const plugin = join(f.config, "omarchy", "plugins", "bmw.media");
    rmSync(plugin, { recursive: true, force: true });
    symlinkSync(join(installRoot, "current", "plugin"), plugin);

    const result = runAt(repo, "install.sh", f.env);
    expect(result.exitCode, result.stderr.toString()).toBe(0);
    expect(realpathSync(join(installRoot, "current"))).toStartWith(join(installRoot, "releases", "3.3.0"));
    expect(existsSync(join(previous, "plugin", "legacy-runtime"))).toBe(true);
    expect(runtimeDirectories(f.data)).toHaveLength(2);

    const shell = JSON.parse(readFileSync(join(f.config, "omarchy", "shell.json"), "utf8"));
    expect(shell.bar.layout.center[0]).toMatchObject({
      id: "bmw.media",
      barDisplayMode: "full",
      dynamicArtworkColor: false,
      motionEnabled: false,
      trackChangeOsd: true,
    });
  });

  test("migrates to copied runtimes, preserves preferences, and retains one rollback", () => {
    const f = fixture();
    const first = runAt(repo, "install.sh", f.env);
    expect(first.exitCode, first.stderr.toString()).toBe(0);

    const installRoot = join(f.data, "omarchy-applemusicplayer");
    const current = join(installRoot, "current");
    const plugin = join(f.config, "omarchy", "plugins", "bmw.media");
    expect(lstatSync(plugin).isSymbolicLink()).toBe(true);
    expect(readlinkSync(plugin)).toBe(join(current, "plugin"));
    expect(realpathSync(plugin)).toStartWith(join(installRoot, "releases", "3.3.0"));
    expect(readlinkSync(join(f.bin, "omarchy-music"))).toBe(join(current, "bin", "omarchy-music"));
    expect(readlinkSync(join(f.bin, "omarchy-applemusicplayer-uninstall"))).toBe(join(current, "bin", "omarchy-applemusicplayer-uninstall"));
    expect(readFileSync(join(f.data, "applications", "Apple Music.desktop"), "utf8")).toContain("Exec=omarchy-music\n");
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
    const backupEntries = readdirSync(backups, { recursive: true }).map(String);
    expect(backupEntries.some(entry => entry.endsWith("bmw.media/user-file"))).toBe(true);
    expect(backupEntries.some(entry => entry.includes("bmw.media.bak.omarchy-applemusicplayer-old"))).toBe(true);

    for (let repeat = 0; repeat < 2; repeat++) {
      const reinstall = runAt(repo, "install.sh", f.env);
      expect(reinstall.exitCode, reinstall.stderr.toString()).toBe(0);
    }
    expect(runtimeDirectories(f.data)).toHaveLength(2);
    expect(JSON.parse(readFileSync(join(installRoot, "install.json"), "utf8"))).toMatchObject({ mode: "copy", version: "3.3.0" });
    const bindingsAgain = readFileSync(join(f.config, "hypr", "bindings.lua"), "utf8");
    expect(bindingsAgain.match(/omarchy-applemusicplayer:start/g)).toHaveLength(1);
    const shellAgain = JSON.parse(readFileSync(join(f.config, "omarchy", "shell.json"), "utf8"));
    expect(shellAgain.bar.layout.center.filter((item: { id: string }) => item.id === "bmw.media")).toHaveLength(1);
    expect(shellAgain.bar.layout.center[0]).toEqual(shell.bar.layout.center[0]);

    const uninstall = Bun.spawnSync([join(f.bin, "omarchy-applemusicplayer-uninstall")], { env: f.env, stdout: "pipe", stderr: "pipe" });
    expect(uninstall.exitCode, uninstall.stderr.toString()).toBe(0);
    expect(existsSync(plugin)).toBe(false);
    expect(existsSync(join(f.bin, "omarchy-music"))).toBe(false);
    expect(existsSync(join(f.bin, "omarchy-applemusicplayer-uninstall"))).toBe(false);
    expect(existsSync(installRoot)).toBe(false);
    expect(readFileSync(join(f.config, "hypr", "bindings.lua"), "utf8")).not.toContain("omarchy-applemusicplayer:start");
    const shellAfter = JSON.parse(readFileSync(join(f.config, "omarchy", "shell.json"), "utf8"));
    expect(shellAfter.bar.layout.center.some((item: { id: string }) => item.id === "bmw.media")).toBe(false);
    expect(readFileSync(join(f.config, "omarchy-applemusicplayer", "config.json"), "utf8")).toBe("credential sentinel");
    expect(existsSync(backups)).toBe(true);
  });

  test("supports repository-linked development installs", () => {
    const f = fixture();
    const result = runAt(repo, "install.sh", f.env, ["--link"]);
    expect(result.exitCode, result.stderr.toString()).toBe(0);
    expect(readlinkSync(join(f.config, "omarchy", "plugins", "bmw.media"))).toBe(join(repo, "integration", "omarchy-plugin"));
    expect(readlinkSync(join(f.bin, "omarchy-music"))).toBe(join(repo, "bin", "omarchy-music"));
    expect(readlinkSync(join(f.bin, "omarchy-applemusicplayer-uninstall"))).toBe(join(repo, "scripts", "uninstall.sh"));
    expect(JSON.parse(readFileSync(join(f.data, "omarchy-applemusicplayer", "install.json"), "utf8")).mode).toBe("link");
  });

  test("copied install and uninstall survive a deleted checkout whose path contains spaces", () => {
    const f = fixture();
    const checkout = join(f.home, "source checkout with spaces");
    copyCheckout(checkout);
    const result = runAt(checkout, "install.sh", f.env);
    expect(result.exitCode, result.stderr.toString()).toBe(0);
    rmSync(checkout, { recursive: true, force: true });

    const launcher = Bun.spawnSync([join(f.bin, "omarchy-music")], { env: f.env, stdout: "pipe", stderr: "pipe" });
    expect(launcher.exitCode, launcher.stderr.toString()).toBe(0);
    const uninstall = Bun.spawnSync([join(f.bin, "omarchy-applemusicplayer-uninstall")], { env: f.env, stdout: "pipe", stderr: "pipe" });
    expect(uninstall.exitCode, uninstall.stderr.toString()).toBe(0);
    expect(existsSync(join(f.data, "omarchy-applemusicplayer"))).toBe(false);
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
