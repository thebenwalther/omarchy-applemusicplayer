const isMini = location.pathname === "/mini";
const $ = selector => document.querySelector(selector);
const $$ = selector => [...document.querySelectorAll(selector)];
const resourceStore = new Map();

let music = null;
let developerToken = "";
let configured = false;
let authorized = false;
let currentView = "home";
let navigationHistory = [];
let lastState = null;
let postTimer = null;
let searchTimer = null;

const emptyState = {
  version: 1, connected: false, authorized: false, playback: "stopped", current: null,
  elapsed: 0, duration: 0, volume: 1, shuffle: false, repeat: "none",
  queuePosition: -1, queue: [], error: "",
};

function escapeHtml(value = "") {
  return String(value).replace(/[&<>'"]/g, character => ({
    "&": "&amp;", "<": "&lt;", ">": "&gt;", "'": "&#39;", '"': "&quot;",
  })[character]);
}

function formatTime(seconds) {
  const total = Math.max(0, Math.round(Number(seconds) || 0));
  return `${Math.floor(total / 60)}:${String(total % 60).padStart(2, "0")}`;
}

function formatArtwork(template, size = 500) {
  if (!template) return "";
  return String(template)
    .replaceAll("{w}", String(size))
    .replaceAll("{h}", String(size))
    .replaceAll("{f}", "jpg")
    .replaceAll("{c}", "bb");
}

function attributesOf(resource) {
  return resource?.attributes || resource?.relationships?.catalog?.data?.[0]?.attributes || {};
}

function playParamsOf(resource) {
  const attributes = attributesOf(resource);
  return attributes.playParams || attributes.playParameters || { id: resource?.id, kind: singularType(resource?.type) };
}

function singularType(type = "song") {
  const clean = String(type).replace(/^library-/, "");
  return clean.endsWith("s") ? clean.slice(0, -1) : clean;
}

function displayType(type = "music") {
  return singularType(type).replaceAll("-", " ");
}

function resourceTitle(resource) {
  const attributes = attributesOf(resource);
  return attributes.name || attributes.title || "Untitled";
}

function resourceSubtitle(resource) {
  const attributes = attributesOf(resource);
  return attributes.artistName || attributes.curatorName || attributes.albumName || displayType(resource?.type);
}

function resourceArtwork(resource, size = 500) {
  return formatArtwork(attributesOf(resource).artwork?.url || resource?.artworkURL || "", size);
}

function normalizeTrack(item) {
  if (!item) return null;
  const attributes = attributesOf(item);
  return {
    id: String(item.id || attributes.playParams?.id || ""),
    type: String(item.type || "songs"),
    title: attributes.name || attributes.title || item.title || "Unknown track",
    artist: attributes.artistName || item.artistName || "Unknown artist",
    album: attributes.albumName || item.albumName || "",
    artwork: resourceArtwork(item, 600) || formatArtwork(item.artworkURL, 600),
    duration: Math.max(0, Number(attributes.durationInMillis || item.playbackDuration || 0) / (attributes.durationInMillis ? 1000 : 1)),
  };
}

function rememberResource(resource) {
  if (!resource) return "";
  const key = `${resource.type || "resource"}:${resource.id || crypto.randomUUID()}`;
  resourceStore.set(key, resource);
  return key;
}

function applyTheme(theme = {}) {
  const mapping = {
    accent: "--accent", background: "--background", dark_background: "--background-dark",
    darker_background: "--background-darker", lighter_background: "--surface",
    foreground: "--foreground", dark_foreground: "--foreground-dark",
    light_foreground: "--foreground-light", bright_foreground: "--foreground-bright",
    red: "--red", green: "--green", yellow: "--yellow",
  };
  for (const [key, cssProperty] of Object.entries(mapping)) {
    if (theme[key]) document.documentElement.style.setProperty(cssProperty, theme[key]);
  }
  const color = theme.background || "#1a1b26";
  document.querySelector('meta[name="theme-color"]')?.setAttribute("content", color);
}

function toast(message, type = "info") {
  const region = $("#toast-region");
  const element = document.createElement("div");
  element.className = `toast ${type}`;
  element.textContent = message;
  region.append(element);
  setTimeout(() => element.remove(), 4200);
}

async function request(path, options = {}) {
  const response = await fetch(path, {
    ...options,
    headers: { "Content-Type": "application/json", ...(options.headers || {}) },
  });
  const data = await response.json().catch(() => ({}));
  if (!response.ok) throw new Error(data.error || `Request failed (${response.status})`);
  return data;
}

async function sendCommand(command, value = undefined) {
  await request("/api/command", { method: "POST", body: JSON.stringify({ command, value }) });
}

function connectEventStream() {
  const events = new EventSource("/api/events");
  events.addEventListener("state", event => renderPlayerState(JSON.parse(event.data)));
  events.addEventListener("command", event => {
    if (isMini || !music) return;
    const payload = JSON.parse(event.data);
    executeCommand(payload.command, payload.value).catch(error => toast(error.message, "error"));
  });
  events.onerror = () => setTimeout(() => {
    if (events.readyState === EventSource.CLOSED) connectEventStream();
  }, 1500);
}

function renderPlayerState(state = emptyState) {
  lastState = { ...emptyState, ...state };
  const current = lastState.current;
  const playing = lastState.playback === "playing";
  const setImage = (selector, source) => {
    const image = $(selector);
    if (!image) return;
    if (source) { image.src = source; image.hidden = false; }
    else { image.removeAttribute("src"); image.hidden = true; }
  };

  setImage("#transport-art", current?.artwork);
  setImage("#mini-art", current?.artwork);
  if ($("#mini-backdrop")) $("#mini-backdrop").style.backgroundImage = current?.artwork ? `url("${current.artwork}")` : "none";
  if ($("#transport-title")) $("#transport-title").textContent = current?.title || "Nothing playing";
  if ($("#transport-artist")) $("#transport-artist").textContent = current?.artist || "Choose something to play";
  if ($("#mini-title")) $("#mini-title").textContent = current?.title || "Apple Music";
  if ($("#mini-artist")) $("#mini-artist").textContent = current?.artist || "Start playback in the full player.";
  if ($("#mini-album")) $("#mini-album").textContent = current?.album || "Not playing";
  if ($("#play-button")) $("#play-button").textContent = playing ? "❚❚" : "▶";
  if ($("#mini-play")) $("#mini-play").textContent = playing ? "❚❚" : "▶";

  const duration = Math.max(0, lastState.duration || current?.duration || 0);
  const elapsed = Math.min(duration || Infinity, Math.max(0, lastState.elapsed || 0));
  for (const selector of ["#seek-slider", "#mini-seek"]) {
    const input = $(selector);
    if (input) { input.max = String(Math.max(1, duration)); input.value = String(elapsed); }
  }
  for (const selector of ["#elapsed-label", "#mini-elapsed"]) if ($(selector)) $(selector).textContent = formatTime(elapsed);
  for (const selector of ["#duration-label", "#mini-duration"]) if ($(selector)) $(selector).textContent = formatTime(duration);
  if ($("#volume-slider")) $("#volume-slider").value = String(lastState.volume ?? 1);
  $("#shuffle-button")?.classList.toggle("is-active", Boolean(lastState.shuffle));
  $("#repeat-button")?.classList.toggle("is-active", lastState.repeat !== "none");
  if ($("#repeat-button")) $("#repeat-button").textContent = lastState.repeat === "one" ? "↻¹" : "↻";

  renderQueue(lastState);
  renderMiniQueue(lastState);
}

function renderQueue(state) {
  const container = $("#queue-list");
  if (!container) return;
  if (!state.queue?.length) {
    container.innerHTML = '<div class="empty-state compact"><span>☷</span><p>Your queue will appear here.</p></div>';
    return;
  }
  container.innerHTML = state.queue.map((track, index) => `
    <article class="queue-item ${index === state.queuePosition ? "is-current" : ""}" data-queue-index="${index}">
      <span class="queue-index">${index === state.queuePosition ? "▶" : index + 1}</span>
      ${track.artwork ? `<img class="queue-art" src="${escapeHtml(track.artwork)}" alt="">` : '<div class="queue-art"></div>'}
      <div class="queue-copy"><strong>${escapeHtml(track.title)}</strong><span>${escapeHtml(track.artist)}</span></div>
      <div class="queue-actions">
        <button data-queue-action="up" title="Move up">↑</button>
        <button data-queue-action="down" title="Move down">↓</button>
        <button data-queue-action="remove" title="Remove">×</button>
      </div>
    </article>`).join("");
}

function renderMiniQueue(state) {
  const container = $("#mini-queue-list");
  if (!container) return;
  const upcoming = (state.queue || []).slice(Math.max(0, state.queuePosition + 1), Math.max(0, state.queuePosition + 1) + 5);
  container.innerHTML = upcoming.length ? upcoming.map((track, index) => `
    <div class="mini-queue-row"><span>${index + 1}</span><div><strong>${escapeHtml(track.title)}</strong><em>${escapeHtml(track.artist)}</em></div></div>`).join("")
    : '<div class="empty-state compact"><p>No upcoming tracks.</p></div>';
}

function mediaCard(resource) {
  const key = rememberResource(resource);
  const title = resourceTitle(resource);
  const subtitle = resourceSubtitle(resource);
  const art = resourceArtwork(resource, 450);
  return `<article class="media-card" data-resource-key="${escapeHtml(key)}">
    <div class="card-art">${art ? `<img src="${escapeHtml(art)}" alt="">` : ""}<button class="card-play" data-card-action="play" type="button" title="Play">▶</button></div>
    <strong>${escapeHtml(title)}</strong><span>${escapeHtml(subtitle)}</span>
  </article>`;
}

function trackRow(resource, index) {
  const key = rememberResource(resource);
  const attributes = attributesOf(resource);
  const art = resourceArtwork(resource, 100);
  const duration = Number(attributes.durationInMillis || 0) / 1000;
  return `<article class="track-row" data-resource-key="${escapeHtml(key)}">
    <span class="track-number">${index + 1}</span>
    ${art ? `<img class="row-art" src="${escapeHtml(art)}" alt="">` : '<div class="row-art"></div>'}
    <div class="row-copy"><strong>${escapeHtml(resourceTitle(resource))}</strong><span>${escapeHtml(attributes.artistName || "")}</span></div>
    <span class="track-album">${escapeHtml(attributes.albumName || "")}</span>
    <span class="track-time">${duration ? formatTime(duration) : ""}</span>
    <div class="row-actions"><button class="icon-button" data-card-action="next" type="button" title="Play next">＋</button></div>
  </article>`;
}

function flattenRecommendations(response) {
  return (response?.data || []).flatMap(item => item.relationships?.contents?.data || []);
}

async function getDeveloperToken() {
  const response = await request("/api/token");
  developerToken = response.token;
  return developerToken;
}

async function appleFetch(path, retry = true) {
  if (!music || !authorized) throw new Error("Connect Apple Music first.");
  if (!developerToken) await getDeveloperToken();
  const headers = { Authorization: `Bearer ${developerToken}` };
  const userToken = music.musicUserToken;
  if (userToken) headers["Music-User-Token"] = userToken;
  const response = await fetch(`https://api.music.apple.com${path}`, { headers });
  if (response.status === 401 && retry) {
    developerToken = "";
    await getDeveloperToken();
    return appleFetch(path, false);
  }
  const data = await response.json().catch(() => ({}));
  if (!response.ok) throw new Error(data.errors?.[0]?.detail || data.errors?.[0]?.title || `Apple Music request failed (${response.status}).`);
  return data;
}

function loadingView() {
  $("#content").innerHTML = '<div class="loading">Loading Apple Music…</div>';
}

function unauthorizedView() {
  $("#content").innerHTML = `<section class="hero">
    <div class="hero-copy"><p class="eyebrow">MusicKit player</p><h1>Your music, shaped for Omarchy.</h1>
    <p>Connect your Apple Music subscription to search the catalog, browse your library, own the playback queue, and control everything from the Omarchy bar.</p>
    <div class="button-row"><button class="primary-button" data-action="authorize" type="button">Connect Apple Music</button><button class="secondary-button" data-action="open-settings" type="button">MusicKit settings</button></div></div>
    <div class="hero-art" style="background-image:url('/icon.svg')"></div>
  </section>`;
}

function errorView(message) {
  $("#content").innerHTML = `<div class="empty-state"><span>!</span><p>${escapeHtml(message)}</p><button class="secondary-button" data-action="refresh" type="button">Try again</button></div>`;
}

function sectionHtml(title, resources) {
  if (!resources?.length) return "";
  return `<section class="section"><div class="section-heading"><h2>${escapeHtml(title)}</h2></div><div class="card-grid">${resources.map(mediaCard).join("")}</div></section>`;
}

async function loadHome(pushHistory = false) {
  if (!authorized) return unauthorizedView();
  if (pushHistory) navigationHistory.push(currentView);
  currentView = "home";
  setActiveNav("home");
  loadingView();
  try {
    const [recommendations, rotation, recent, added] = await Promise.all([
      appleFetch("/v1/me/recommendations?limit=8").catch(() => ({ data: [] })),
      appleFetch("/v1/me/history/heavy-rotation?limit=10").catch(() => ({ data: [] })),
      appleFetch("/v1/me/recent/played/tracks?limit=10").catch(() => ({ data: [] })),
      appleFetch("/v1/me/library/recently-added?limit=10").catch(() => ({ data: [] })),
    ]);
    const recommended = flattenRecommendations(recommendations);
    const heroItem = recommended[0] || rotation.data?.[0] || recent.data?.[0];
    const heroArt = heroItem ? resourceArtwork(heroItem, 1000) : "";
    $("#content").innerHTML = `<section class="hero">
      <div class="hero-copy"><p class="eyebrow">Listen now</p><h1>${escapeHtml(heroItem ? resourceTitle(heroItem) : "Your Apple Music library")}</h1>
      <p>${escapeHtml(heroItem ? resourceSubtitle(heroItem) : "Recommendations, recent favorites, and your library in one focused player.")}</p>
      <div class="button-row">${heroItem ? `<button class="primary-button" data-hero-play="${escapeHtml(rememberResource(heroItem))}" type="button">▶ Play</button>` : ""}<button class="secondary-button" data-action="focus-search" type="button">Search music</button></div></div>
      <div class="hero-art" ${heroArt ? `style="background-image:url('${escapeHtml(heroArt)}')"` : ""}></div></section>
      ${sectionHtml("Made for you", recommended.slice(0, 10))}
      ${sectionHtml("Heavy rotation", rotation.data)}
      ${sectionHtml("Recently played", recent.data)}
      ${sectionHtml("Recently added", added.data)}`;
  } catch (error) { errorView(error.message); }
}

async function loadCollection(view, pushHistory = true) {
  if (!authorized) return unauthorizedView();
  if (pushHistory) navigationHistory.push(currentView);
  currentView = view;
  setActiveNav(view);
  loadingView();
  const definitions = {
    recent: ["Recently Played", "/v1/me/recent/played/tracks?limit=25", "tracks"],
    "library-albums": ["Albums", "/v1/me/library/albums?limit=50", "cards"],
    "library-artists": ["Artists", "/v1/me/library/artists?limit=50", "cards"],
    "library-songs": ["Songs", "/v1/me/library/songs?limit=50", "tracks"],
    "library-playlists": ["Playlists", "/v1/me/library/playlists?limit=50", "cards"],
  };
  const [title, path, layout] = definitions[view];
  try {
    const response = await appleFetch(path);
    const resources = response.data || [];
    $("#content").innerHTML = `<header class="content-header"><div><h1>${title}</h1><p>${resources.length} items from your Apple Music library</p></div></header>
      ${resources.length ? (layout === "tracks" ? `<div class="track-list">${resources.map(trackRow).join("")}</div>` : `<div class="card-grid">${resources.map(mediaCard).join("")}</div>`) : '<div class="empty-state"><span>♫</span><p>Nothing here yet.</p></div>'}`;
  } catch (error) { errorView(error.message); }
}

async function searchCatalog(term) {
  if (!authorized) return unauthorizedView();
  const query = term.trim();
  if (!query) return loadHome();
  currentView = `search:${query}`;
  setActiveNav("");
  loadingView();
  try {
    const storefront = music.storefrontId || "us";
    const params = new URLSearchParams({ term: query, types: "songs,albums,playlists,artists", limit: "20" });
    const response = await appleFetch(`/v1/catalog/${encodeURIComponent(storefront)}/search?${params}`);
    const results = response.results || {};
    $("#content").innerHTML = `<header class="content-header"><div><h1>“${escapeHtml(query)}”</h1><p>Apple Music catalog results</p></div></header>
      ${sectionHtml("Albums", results.albums?.data)}
      ${sectionHtml("Playlists", results.playlists?.data)}
      ${sectionHtml("Artists", results.artists?.data)}
      ${results.songs?.data?.length ? `<section class="section"><div class="section-heading"><h2>Songs</h2></div><div class="track-list">${results.songs.data.map(trackRow).join("")}</div></section>` : ""}
      ${Object.keys(results).length ? "" : '<div class="empty-state"><span>⌕</span><p>No results found.</p></div>'}`;
  } catch (error) { errorView(error.message); }
}

async function openResource(resource) {
  if (!resource) return;
  const type = String(resource.type || "");
  if (type.includes("song")) return playResource(resource);
  navigationHistory.push(currentView);
  currentView = `detail:${type}:${resource.id}`;
  setActiveNav("");
  loadingView();
  try {
    let detail = resource;
    let tracks = resource.relationships?.tracks?.data || [];
    if (!tracks.length) {
      const library = type.startsWith("library-");
      const path = library
        ? `/v1/me/library/${type.replace("library-", "")}/${encodeURIComponent(resource.id)}?include=tracks,catalog`
        : `/v1/catalog/${encodeURIComponent(music.storefrontId || "us")}/${type}/${encodeURIComponent(resource.id)}?include=tracks,artists`;
      const response = await appleFetch(path);
      detail = response.data?.[0] || resource;
      tracks = detail.relationships?.tracks?.data || [];
    }
    const attributes = attributesOf(detail);
    const art = resourceArtwork(detail, 700);
    const key = rememberResource(detail);
    $("#content").innerHTML = `<section class="detail-header">
      ${art ? `<img src="${escapeHtml(art)}" alt="">` : '<div class="card-art"></div>'}
      <div class="detail-copy"><p class="eyebrow">${escapeHtml(displayType(type))}</p><h1>${escapeHtml(resourceTitle(detail))}</h1><strong>${escapeHtml(resourceSubtitle(detail))}</strong>
      <p>${escapeHtml(attributes.description?.short || attributes.description?.standard || attributes.editorialNotes?.short || "")}</p>
      <div class="button-row"><button class="primary-button" data-hero-play="${escapeHtml(key)}" type="button">▶ Play</button><button class="secondary-button" data-resource-next="${escapeHtml(key)}" type="button">Play next</button></div></div></section>
      ${tracks.length ? `<div class="track-list">${tracks.map(trackRow).join("")}</div>` : '<div class="empty-state compact"><p>No track listing was returned.</p></div>'}`;
  } catch (error) { errorView(error.message); }
}

function setActiveNav(view) {
  $$(".nav-item").forEach(button => button.classList.toggle("is-active", button.dataset.view === view));
}

async function waitForMusicKit() {
  if (window.MusicKit) return;
  await new Promise((resolve, reject) => {
    const timeout = setTimeout(() => reject(new Error("MusicKit did not load. Check your network connection.")), 15_000);
    document.addEventListener("musickitloaded", () => { clearTimeout(timeout); resolve(); }, { once: true });
  });
}

async function initializeMusicKit() {
  await waitForMusicKit();
  const token = await getDeveloperToken();
  await window.MusicKit.configure({
    developerToken: token,
    app: { name: "Omarchy Apple Music Player", build: "0.1.0" },
  });
  music = window.MusicKit.getInstance();
  authorized = Boolean(music.isAuthorized);
  attachMusicEvents();
  updateAuthUi();
  if (authorized) await loadHome(); else unauthorizedView();
  publishState();
}

async function authorize() {
  if (!configured) return $("#setup-dialog")?.showModal();
  if (!music) await initializeMusicKit();
  if (music.isAuthorized) {
    await music.unauthorize();
    authorized = false;
    updateAuthUi();
    unauthorizedView();
    publishState();
    return;
  }
  try {
    await music.authorize();
    authorized = Boolean(music.isAuthorized || music.musicUserToken);
    updateAuthUi();
    await loadHome();
    publishState();
  } catch (error) { toast(error.message || "Apple Music authorization was cancelled.", "error"); }
}

function updateAuthUi() {
  const button = $("#auth-button");
  if (!button) return;
  button.classList.toggle("is-connected", authorized);
  button.querySelector("span:last-child").textContent = authorized ? "Apple Music connected" : "Connect Apple Music";
  button.title = authorized ? "Disconnect Apple Music" : "Connect Apple Music";
}

function attachMusicEvents() {
  const events = window.MusicKit?.Events || {};
  const names = [
    "playbackStateDidChange", "nowPlayingItemDidChange", "playbackTimeDidChange",
    "queueItemsDidChange", "queuePositionDidChange", "playbackVolumeDidChange",
    "shuffleModeDidChange", "repeatModeDidChange", "authorizationStatusDidChange",
  ];
  for (const key of names) {
    const eventName = events[key] || key;
    try { music.addEventListener(eventName, () => publishState()); } catch {}
  }
  setInterval(() => { if (music && authorized) publishState(); }, 1000);
}

function playbackStatus() {
  const state = music?.playbackState;
  const states = window.MusicKit?.PlaybackStates || {};
  const name = Object.entries(states).find(([, value]) => value === state)?.[0] || String(state || "");
  if (/playing/i.test(name)) return "playing";
  if (/loading|waiting|seeking|stalled/i.test(name)) return "loading";
  if (/paused/i.test(name)) return "paused";
  return "stopped";
}

function queueItems() {
  const queue = music?.queue;
  const items = queue?.items || queue?._items || [];
  try { return Array.from(items); } catch { return []; }
}

function currentQueuePosition() {
  const position = Number(music?.queue?.position);
  if (Number.isFinite(position)) return position;
  const currentId = music?.nowPlayingItem?.id;
  return queueItems().findIndex(item => item.id === currentId);
}

function buildPlayerState() {
  const current = normalizeTrack(music?.nowPlayingItem);
  const queue = queueItems().map(normalizeTrack).filter(Boolean);
  const repeatValue = String(music?.repeatMode ?? "").toLowerCase();
  const shuffleValue = String(music?.shuffleMode ?? "").toLowerCase();
  return {
    version: 1,
    connected: Boolean(music),
    authorized: Boolean(authorized),
    playback: playbackStatus(),
    current,
    elapsed: Math.max(0, Number(music?.currentPlaybackTime || 0)),
    duration: Math.max(0, Number(music?.currentPlaybackDuration || current?.duration || 0)),
    volume: Math.max(0, Math.min(1, Number(music?.volume ?? 1))),
    shuffle: shuffleValue.includes("song") || shuffleValue === "1" || music?.shuffleMode === 1,
    repeat: repeatValue.includes("one") || repeatValue === "1" ? "one" : (repeatValue.includes("all") || repeatValue === "2" ? "all" : "none"),
    queuePosition: currentQueuePosition(),
    queue,
    error: "",
  };
}

function publishState() {
  if (!music) return;
  const state = buildPlayerState();
  renderPlayerState(state);
  publishMediaSession(state);
  clearTimeout(postTimer);
  postTimer = setTimeout(() => request("/api/state", { method: "POST", body: JSON.stringify(state) }).catch(() => {}), 90);
}

function publishMediaSession(state) {
  if (!("mediaSession" in navigator)) return;
  const current = state.current;
  if (current) {
    navigator.mediaSession.metadata = new MediaMetadata({
      title: current.title,
      artist: current.artist,
      album: current.album,
      artwork: current.artwork ? [96, 128, 192, 256, 384, 512].map(size => ({ src: current.artwork, sizes: `${size}x${size}`, type: "image/jpeg" })) : [],
    });
    if (state.duration > 0) {
      try { navigator.mediaSession.setPositionState({ duration: state.duration, playbackRate: 1, position: Math.min(state.elapsed, state.duration) }); } catch {}
    }
  }
  navigator.mediaSession.playbackState = state.playback === "playing" ? "playing" : state.playback === "paused" ? "paused" : "none";
  const handlers = {
    play: () => music.play(), pause: () => music.pause(), previoustrack: () => music.skipToPreviousItem(), nexttrack: () => music.skipToNextItem(),
    seekto: details => music.seekToTime(details.seekTime), seekbackward: details => music.seekToTime(Math.max(0, music.currentPlaybackTime - (details.seekOffset || 10))),
    seekforward: details => music.seekToTime(Math.min(music.currentPlaybackDuration, music.currentPlaybackTime + (details.seekOffset || 10))),
  };
  for (const [action, handler] of Object.entries(handlers)) {
    try { navigator.mediaSession.setActionHandler(action, handler); } catch {}
  }
}

async function playResource(resource, mode = "now") {
  if (!music || !authorized) return authorize();
  const params = playParamsOf(resource);
  const id = params.id || resource.id;
  const kind = params.kind || singularType(resource.type);
  if (!id) throw new Error("This item cannot be played.");
  if (mode === "next" && typeof music.playNext === "function") {
    await music.playNext({ [kind]: id });
  } else if (mode === "later" && typeof music.playLater === "function") {
    await music.playLater({ [kind]: id });
  } else {
    try { await music.setQueue({ [kind]: id }); }
    catch { await music.setQueue({ items: [params] }); }
    await music.play();
  }
  publishState();
}

async function executeCommand(command, value) {
  if (!music) return;
  if (command === "play") await music.play();
  else if (command === "pause") await music.pause();
  else if (command === "toggle") playbackStatus() === "playing" ? await music.pause() : await music.play();
  else if (command === "previous") await music.skipToPreviousItem();
  else if (command === "next") await music.skipToNextItem();
  else if (command === "seek") await music.seekToTime(Math.max(0, Number(value) || 0));
  else if (command === "volume") music.volume = Math.max(0, Math.min(1, Number(value) || 0));
  else if (command === "shuffle") toggleShuffle();
  else if (command === "repeat") toggleRepeat();
  else if (command === "play-index") { await music.changeToMediaAtIndex(Number(value)); await music.play(); }
  else if (command === "remove-index") await mutateQueue("remove", Number(value));
  else if (command === "move-item") await mutateQueue("move", Number(value?.from), Number(value?.to));
  else if (command === "open-player") location.href = "/";
  publishState();
}

function toggleShuffle() {
  const modes = window.MusicKit?.PlaybackBitrate ? window.MusicKit.PlayerShuffleMode : window.MusicKit?.PlayerShuffleMode;
  const on = modes?.songs ?? 1;
  const off = modes?.off ?? 0;
  music.shuffleMode = buildPlayerState().shuffle ? off : on;
}

function toggleRepeat() {
  const modes = window.MusicKit?.PlayerRepeatMode || {};
  const current = buildPlayerState().repeat;
  music.repeatMode = current === "none" ? (modes.all ?? 2) : current === "all" ? (modes.one ?? 1) : (modes.none ?? 0);
}

async function mutateQueue(action, from, to = -1) {
  const state = buildPlayerState();
  if (from < 0 || from >= state.queue.length || from === state.queuePosition) return;
  const tracks = [...state.queue];
  if (action === "remove") tracks.splice(from, 1);
  else if (action === "move" && to >= 0 && to < tracks.length) tracks.splice(to, 0, tracks.splice(from, 1)[0]);
  else return;

  const currentId = state.current?.id;
  const newPosition = Math.max(0, tracks.findIndex(track => track.id === currentId));
  const elapsed = state.elapsed;
  const wasPlaying = state.playback === "playing";
  const songIds = tracks.map(track => track.id).filter(Boolean);
  if (!songIds.length) return;
  await music.setQueue({ songs: songIds });
  await music.changeToMediaAtIndex(newPosition);
  if (elapsed) await music.seekToTime(elapsed);
  if (wasPlaying) await music.play();
}

async function clearFutureQueue() {
  const state = buildPlayerState();
  if (state.queuePosition < 0) return;
  const future = state.queue.slice(state.queuePosition + 1);
  for (let index = state.queue.length - 1; index > state.queuePosition; index--) await mutateQueue("remove", index);
  if (future.length) toast(`Removed ${future.length} upcoming track${future.length === 1 ? "" : "s"}.`);
}

function attachUiEvents() {
  document.addEventListener("click", async event => {
    const commandButton = event.target.closest("[data-command]");
    if (commandButton) {
      const command = commandButton.dataset.command;
      if (isMini) await sendCommand(command); else await executeCommand(command);
      return;
    }
    const actionButton = event.target.closest("[data-action]");
    if (actionButton) {
      const action = actionButton.dataset.action;
      if (action === "authorize") await authorize();
      else if (action === "open-settings") $("#setup-dialog")?.showModal();
      else if (action === "focus-search") { $("#search-input")?.focus(); $("#search-input")?.select(); }
      else if (action === "refresh") await navigateCurrent();
      else if (action === "back") await navigateBack();
      else if (action === "open-mini") await request("/api/window", { method: "POST", body: JSON.stringify({ kind: "mini" }) });
      else if (action === "open-full") await request("/api/window", { method: "POST", body: JSON.stringify({ kind: "full" }) });
      else if (action === "clear-future") await clearFutureQueue();
      return;
    }
    const nav = event.target.closest("[data-view]");
    if (nav) {
      const view = nav.dataset.view;
      if (view === "home") await loadHome(true); else await loadCollection(view);
      return;
    }
    const heroPlay = event.target.closest("[data-hero-play]");
    if (heroPlay) return playResource(resourceStore.get(heroPlay.dataset.heroPlay));
    const nextButton = event.target.closest("[data-resource-next]");
    if (nextButton) return playResource(resourceStore.get(nextButton.dataset.resourceNext), "next");
    const card = event.target.closest("[data-resource-key]");
    if (card) {
      const resource = resourceStore.get(card.dataset.resourceKey);
      if (event.target.closest('[data-card-action="play"]')) await playResource(resource);
      else if (event.target.closest('[data-card-action="next"]')) await playResource(resource, "next");
      else await openResource(resource);
      return;
    }
    const queueItem = event.target.closest("[data-queue-index]");
    if (queueItem) {
      const index = Number(queueItem.dataset.queueIndex);
      const queueAction = event.target.closest("[data-queue-action]")?.dataset.queueAction;
      if (!queueAction) return executeCommand("play-index", index);
      if (queueAction === "remove") return mutateQueue("remove", index);
      if (queueAction === "up") return mutateQueue("move", index, Math.max(0, index - 1));
      if (queueAction === "down") return mutateQueue("move", index, Math.min((lastState?.queue?.length || 1) - 1, index + 1));
    }
  });

  $("#search-input")?.addEventListener("input", event => {
    clearTimeout(searchTimer);
    searchTimer = setTimeout(() => searchCatalog(event.target.value), 350);
  });
  $("#search-input")?.addEventListener("keydown", event => {
    if (event.key === "Escape") { event.target.value = ""; event.target.blur(); loadHome(); }
  });
  document.addEventListener("keydown", event => {
    if ((event.ctrlKey || event.metaKey) && event.key.toLowerCase() === "k") { event.preventDefault(); $("#search-input")?.focus(); }
    if (event.code === "Space" && !["INPUT", "TEXTAREA"].includes(document.activeElement?.tagName)) { event.preventDefault(); isMini ? sendCommand("toggle") : executeCommand("toggle"); }
  });

  const seek = async event => isMini ? sendCommand("seek", Number(event.target.value)) : executeCommand("seek", Number(event.target.value));
  $("#seek-slider")?.addEventListener("change", seek);
  $("#mini-seek")?.addEventListener("change", seek);
  $("#volume-slider")?.addEventListener("input", event => executeCommand("volume", Number(event.target.value)));

  $("#setup-form")?.addEventListener("submit", async event => {
    event.preventDefault();
    const form = event.currentTarget;
    const values = Object.fromEntries(new FormData(form));
    const error = $("#setup-error");
    error.textContent = "";
    try {
      await request("/api/setup", { method: "POST", body: JSON.stringify(values) });
      configured = true;
      $("#setup-dialog").close();
      form.reset();
      toast("MusicKit signing key saved locally.");
      await initializeMusicKit();
    } catch (cause) { error.textContent = cause.message; }
  });
}

async function navigateBack() {
  const target = navigationHistory.pop() || "home";
  if (target === "home") return loadHome();
  if (target.startsWith("library-") || target === "recent") return loadCollection(target, false);
  return loadHome();
}

async function navigateCurrent() {
  if (currentView === "home") return loadHome();
  if (currentView.startsWith("search:")) return searchCatalog(currentView.slice(7));
  if (currentView.startsWith("library-") || currentView === "recent") return loadCollection(currentView, false);
  return loadHome();
}

async function initialize() {
  attachUiEvents();
  connectEventStream();
  try {
    const bootstrap = await request("/api/bootstrap");
    configured = bootstrap.configured;
    applyTheme(bootstrap.theme);
    renderPlayerState(bootstrap.state);
    if (isMini) return;
    if (!configured) {
      unauthorizedView();
      $("#setup-dialog").showModal();
      return;
    }
    await initializeMusicKit();
  } catch (error) {
    if (!isMini) errorView(error.message);
    else toast(error.message, "error");
  }
}

window.addEventListener("beforeunload", () => {
  if (!isMini && music) {
    const state = { ...buildPlayerState(), connected: false, playback: "stopped" };
    navigator.sendBeacon("/api/state", JSON.stringify(state));
  }
});

initialize();
