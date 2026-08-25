import { chmod, mkdir, readFile, rename, stat, writeFile } from "node:fs/promises";
import { dirname, extname, join, normalize } from "node:path";
import { emptyPlayerState, normalizePlayerState, type PlayerState } from "./player-state";
import { generateDeveloperToken, validateCredentials, type MusicKitCredentials } from "./token";

const root = dirname(dirname(import.meta.path));
const webRoot = join(root, "web");
const home = process.env.HOME || "/tmp";
const configDir = join(process.env.XDG_CONFIG_HOME || join(home, ".config"), "omarchy-applemusicplayer");
const configPath = join(configDir, "config.json");
const runtimeDir = join(process.env.XDG_RUNTIME_DIR || `/run/user/${process.getuid?.() ?? 1000}`, "omarchy-applemusicplayer");
const statePath = join(runtimeDir, "state.json");
const themePath = join(home, ".local/state/omarchy/current/theme/colors.toml");
const port = Number(process.env.OMARCHY_APPLEMUSIC_PORT || 17689);
const host = "127.0.0.1";
const origin = `http://applemusic.localhost:${port}`;
const allowedOrigins = new Set([
  origin,
  `http://mini.applemusic.localhost:${port}`,
  `http://${host}:${port}`,
]);

const commands = new Set([
  "play", "pause", "toggle", "previous", "next", "seek", "volume",
  "shuffle", "repeat", "play-index", "remove-index", "move-item", "open-player",
]);

let playerState: PlayerState = emptyPlayerState();
const eventClients = new Set<ReadableStreamDefaultController<Uint8Array>>();
const encoder = new TextEncoder();

await mkdir(configDir, { recursive: true, mode: 0o700 });
await mkdir(runtimeDir, { recursive: true, mode: 0o700 });
try {
  playerState = normalizePlayerState(JSON.parse(await readFile(statePath, "utf8")));
} catch {}
await persistState();

function json(value: unknown, status = 200, headers: HeadersInit = {}): Response {
  return Response.json(value, {
    status,
    headers: { "Cache-Control": "no-store", ...headers },
  });
}

function error(message: string, status = 400): Response {
  return json({ error: message }, status);
}

async function readCredentials(): Promise<MusicKitCredentials | null> {
  try {
    const value = validateCredentials(JSON.parse(await readFile(configPath, "utf8")));
    await chmod(configPath, 0o600);
    return value;
  } catch {
    return null;
  }
}

async function persistState(): Promise<void> {
  const temporary = `${statePath}.${process.pid}.tmp`;
  await writeFile(temporary, `${JSON.stringify(playerState)}\n`, { mode: 0o600 });
  await rename(temporary, statePath);
}

function sendEvent(event: "state" | "command" | "theme", data: unknown): void {
  const chunk = encoder.encode(`event: ${event}\ndata: ${JSON.stringify(data)}\n\n`);
  for (const client of [...eventClients]) {
    try { client.enqueue(chunk); } catch { eventClients.delete(client); }
  }
}

function parseTomlColors(text: string): Record<string, string> {
  const wanted = new Set([
    "accent", "background", "dark_background", "darker_background", "lighter_background",
    "foreground", "dark_foreground", "light_foreground", "bright_foreground", "red", "green", "yellow",
  ]);
  const colors: Record<string, string> = {};
  for (const line of text.split("\n")) {
    const match = line.match(/^\s*([a-z_]+)\s*=\s*["'](#[0-9a-fA-F]{6})["']/);
    if (match && wanted.has(match[1])) colors[match[1]] = match[2];
  }
  return colors;
}

async function getTheme(): Promise<Record<string, string>> {
  const fallback = {
    accent: "#7aa2f7", background: "#1a1b26", dark_background: "#13141c",
    darker_background: "#0e0e14", lighter_background: "#24283b", foreground: "#a9b1d6",
    dark_foreground: "#565f89", light_foreground: "#b4bee6", bright_foreground: "#c0caf5",
    red: "#f7768e", green: "#9ece6a", yellow: "#e0af68",
  };
  try { return { ...fallback, ...parseTomlColors(await readFile(themePath, "utf8")) }; }
  catch { return fallback; }
}

function requestAllowed(request: Request, allowCli = false): boolean {
  const requestOrigin = request.headers.get("origin");
  if (requestOrigin && allowedOrigins.has(requestOrigin)) return true;
  if (!requestOrigin && allowCli && request.headers.get("x-omarchy-applemusic") === "1") return true;
  return false;
}

const mimeTypes: Record<string, string> = {
  ".html": "text/html; charset=utf-8",
  ".js": "text/javascript; charset=utf-8",
  ".css": "text/css; charset=utf-8",
  ".svg": "image/svg+xml",
  ".png": "image/png",
  ".json": "application/json; charset=utf-8",
};

async function staticResponse(pathname: string): Promise<Response> {
  const requested = pathname === "/" || pathname === "/mini" ? "index.html" : pathname.slice(1);
  const filePath = normalize(join(webRoot, requested));
  if (!filePath.startsWith(webRoot)) return error("Not found", 404);
  try {
    const file = Bun.file(filePath);
    if (!(await file.exists()) || !(await stat(filePath)).isFile()) return error("Not found", 404);
    return new Response(file, {
      headers: {
        "Content-Type": mimeTypes[extname(filePath)] || "application/octet-stream",
        "Cache-Control": process.env.OMARCHY_APPLEMUSIC_DEV ? "no-store" : "public, max-age=300",
        "X-Content-Type-Options": "nosniff",
      },
    });
  } catch { return error("Not found", 404); }
}

const server = Bun.serve({
  hostname: host,
  port,
  idleTimeout: 30,
  async fetch(request) {
    const url = new URL(request.url);

    if (request.method === "GET" && url.pathname === "/api/health") {
      return json({ ok: true, configured: Boolean(await readCredentials()), version: "0.1.0" });
    }

    if (request.method === "GET" && url.pathname === "/api/bootstrap") {
      return json({ configured: Boolean(await readCredentials()), state: playerState, theme: await getTheme() });
    }

    if (request.method === "GET" && url.pathname === "/api/token") {
      const credentials = await readCredentials();
      if (!credentials) return error("MusicKit has not been configured yet.", 409);
      try {
        return json({ token: await generateDeveloperToken(credentials, origin), mediaId: credentials.mediaId || "" });
      } catch (cause) {
        return error(cause instanceof Error ? cause.message : "Could not sign the developer token.", 500);
      }
    }

    if (request.method === "POST" && url.pathname === "/api/setup") {
      if (!requestAllowed(request)) return error("Forbidden", 403);
      try {
        const credentials = validateCredentials(await request.json());
        await generateDeveloperToken(credentials, origin, Math.floor(Date.now() / 1000), 60);
        const temporary = `${configPath}.${process.pid}.tmp`;
        await writeFile(temporary, `${JSON.stringify(credentials, null, 2)}\n`, { mode: 0o600 });
        await rename(temporary, configPath);
        await chmod(configPath, 0o600);
        return json({ ok: true });
      } catch (cause) {
        return error(cause instanceof Error ? cause.message : "Invalid MusicKit configuration.");
      }
    }

    if (request.method === "GET" && url.pathname === "/api/state") return json(playerState);

    if (request.method === "POST" && url.pathname === "/api/state") {
      if (!requestAllowed(request)) return error("Forbidden", 403);
      try {
        playerState = normalizePlayerState(await request.json());
        await persistState();
        sendEvent("state", playerState);
        return json({ ok: true });
      } catch { return error("Invalid player state."); }
    }

    if (request.method === "POST" && url.pathname === "/api/command") {
      if (!requestAllowed(request, true)) return error("Forbidden", 403);
      try {
        const payload = await request.json() as Record<string, unknown>;
        const command = String(payload.command || "");
        if (!commands.has(command)) return error("Unknown player command.");
        sendEvent("command", { ...payload, command });
        return json({ ok: true });
      } catch { return error("Invalid player command."); }
    }

    if (request.method === "POST" && url.pathname === "/api/window") {
      if (!requestAllowed(request)) return error("Forbidden", 403);
      try {
        const payload = await request.json() as Record<string, unknown>;
        const kind = String(payload.kind || "");
        if (kind !== "full" && kind !== "mini") return error("Unknown window type.");
        const executable = join(root, "bin", kind === "mini" ? "omarchy-music-mini" : "omarchy-music");
        Bun.spawn([executable], { cwd: root, stdin: "ignore", stdout: "ignore", stderr: "ignore" }).unref();
        return json({ ok: true });
      } catch { return error("Could not open the player window.", 500); }
    }

    if (request.method === "GET" && url.pathname === "/api/events") {
      let controllerRef: ReadableStreamDefaultController<Uint8Array> | null = null;
      const stream = new ReadableStream<Uint8Array>({
        start(controller) {
          controllerRef = controller;
          eventClients.add(controller);
          controller.enqueue(encoder.encode(`event: state\ndata: ${JSON.stringify(playerState)}\n\n`));
        },
        cancel() { if (controllerRef) eventClients.delete(controllerRef); },
      });
      return new Response(stream, {
        headers: {
          "Content-Type": "text/event-stream",
          "Cache-Control": "no-cache, no-transform",
          "Connection": "keep-alive",
          "X-Accel-Buffering": "no",
        },
      });
    }

    if (request.method === "GET") return staticResponse(url.pathname);
    return error("Method not allowed", 405);
  },
});

const heartbeat = setInterval(() => {
  const chunk = encoder.encode(": heartbeat\n\n");
  for (const client of [...eventClients]) {
    try { client.enqueue(chunk); } catch { eventClients.delete(client); }
  }
}, 20_000);

async function shutdown() {
  clearInterval(heartbeat);
  playerState = { ...playerState, connected: false, playback: "stopped", updatedAt: Date.now() };
  await persistState().catch(() => {});
  server.stop(true);
  process.exit(0);
}

process.on("SIGINT", shutdown);
process.on("SIGTERM", shutdown);
console.log(`Omarchy Apple Music Player listening on http://${host}:${port} (app origin ${origin})`);
