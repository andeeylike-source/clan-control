#!/usr/bin/env node
// ---------------------------------------------------------------------------
// import-backup-to-supabase.mjs
// Imports a Clan-Control JSON backup into Supabase (PostgreSQL).
// Schema source-of-truth: 0001_clan_control_v1.sql
// ---------------------------------------------------------------------------

import { createClient } from "@supabase/supabase-js";
import { readFile } from "node:fs/promises";
import process from "node:process";

// ── env ────────────────────────────────────────────────────────────────────
const SUPABASE_URL = process.env.SUPABASE_URL;
const SUPABASE_SERVICE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
if (!SUPABASE_URL || !SUPABASE_SERVICE_KEY) {
  console.error(
    "Missing env: SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are required."
  );
  process.exit(1);
}
const sb = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY);

// ── helpers ────────────────────────────────────────────────────────────────

/** Normalize text for alias/name matching: lowercase + trim whitespace. */
function normalize(text) {
  return (text ?? "").toLowerCase().trim();
}

/** Map Cyrillic rank strings to canonical DB values. */
function normalizeRank(raw) {
  const map = { КЛ: "KL", ПЛ: "PL", ИГРОК: "Player" };
  return map[raw] ?? "Player";
}

/** Upsert wrapper that throws on error. */
async function upsertRows(table, rows, opts = {}) {
  if (!rows.length) return [];
  const { data, error } = await sb.from(table).upsert(rows, opts).select();
  if (error) throw new Error(`upsert ${table}: ${error.message}`);
  return data;
}

/** Insert wrapper (no conflict) that throws on error. */
async function insertRows(table, rows) {
  if (!rows.length) return [];
  const { data, error } = await sb.from(table).insert(rows).select();
  if (error) throw new Error(`insert ${table}: ${error.message}`);
  return data;
}

/**
 * Check if an object looks like a player stat entry.
 * Must have `name` (string) and at least one numeric stat field.
 */
function isPlayerLikeObject(obj) {
  if (!obj || typeof obj !== "object" || Array.isArray(obj)) return false;
  if (typeof obj.name !== "string") return false;
  const statFields = ["kills", "deaths", "pvp_dmg", "pve_dmg"];
  return statFields.some((f) => typeof obj[f] === "number");
}

// ── main ───────────────────────────────────────────────────────────────────
async function main() {
  const backupPath = process.argv[2];
  if (!backupPath) {
    console.error("Usage: node import-backup-to-supabase.mjs <backup.json>");
    process.exit(1);
  }

  const raw = await readFile(backupPath, "utf-8");
  const backup = JSON.parse(raw);

  // FIX #1: Support both backup formats:
  //   { version, exportedAt, data: {...} }  — wrapped format
  //   { packs, roster, ... }                — raw top-level format
  const d = backup.data ?? backup;

  console.log("Backup version:", backup.version ?? "(none)", "exported:", backup.exportedAt ?? "(none)");

  // ────────────────────────────────────────────────────────────────────────
  // 1. Packs
  // ────────────────────────────────────────────────────────────────────────
  const rawPacks = d.packs ?? [];
  const packRows = rawPacks.map((p) => ({
    name: typeof p === "string" ? p : p.name,
    is_active: true,
  }));

  // Always ensure a "СОЛО" pseudo-pack does NOT go into DB.
  const filteredPacks = packRows.filter(
    (p) => p.name && p.name !== "СОЛО"
  );
  const dbPacks = await upsertRows("packs", filteredPacks, {
    onConflict: "name",
  });
  const packIdByName = Object.fromEntries(
    dbPacks.map((p) => [p.name, p.id])
  );
  console.log(`Packs: ${dbPacks.length} upserted`);

  // ────────────────────────────────────────────────────────────────────────
  // 2. Players  (roster + archive)
  // ────────────────────────────────────────────────────────────────────────
  const rosterPlayers = (d.roster ?? []).map((r) => ({ ...r, _status: "active" }));
  const archivePlayers = (d.archive ?? []).map((r) => ({
    ...r,
    _status: "archived",
  }));
  const allRawPlayers = [...rosterPlayers, ...archivePlayers];

  // De-duplicate by name (keep first occurrence)
  const seenNames = new Set();
  const uniquePlayers = [];
  for (const p of allRawPlayers) {
    const key = normalize(p.name);
    if (seenNames.has(key)) continue;
    seenNames.add(key);
    uniquePlayers.push(p);
  }

  const playerRows = uniquePlayers.map((p) => ({
    name: p.name,
    rank: normalizeRank(p.rank),
    primary_profa: p.profa || null,
    pack_id:
      p.pac && p.pac !== "СОЛО" ? packIdByName[p.pac] ?? null : null,
    verified: p.verified ?? false,
    is_new: p.isNew ?? false,
    status: p._status,
    archived_at: p._status === "archived" ? new Date().toISOString() : null,
  }));

  // Insert all players (no natural unique constraint in schema for name,
  // so we wipe-and-insert to keep the import idempotent).
  // To make re-runs safe, delete existing data first.
  await sb.from("player_notes").delete().neq("id", "00000000-0000-0000-0000-000000000000");
  await sb.from("player_profa_history").delete().neq("id", "00000000-0000-0000-0000-000000000000");
  await sb.from("km_session_player_stats").delete().neq("id", "00000000-0000-0000-0000-000000000000");
  await sb.from("km_sessions").delete().neq("id", "00000000-0000-0000-0000-000000000000");
  await sb.from("player_aliases").delete().neq("id", "00000000-0000-0000-0000-000000000000");
  await sb.from("calendar_events").delete().neq("id", "00000000-0000-0000-0000-000000000000");
  await sb.from("players").delete().neq("id", "00000000-0000-0000-0000-000000000000");
  await sb.from("packs").delete().neq("id", "00000000-0000-0000-0000-000000000000");
  await sb.from("app_settings").delete().neq("key", "___never___");
  console.log("Existing data cleared for clean re-import.");

  // Re-insert packs after wipe
  const dbPacksFresh = await insertRows("packs", filteredPacks);
  const packIdMap = Object.fromEntries(dbPacksFresh.map((p) => [p.name, p.id]));

  // Fix pack_id references after re-insert
  for (const row of playerRows) {
    if (row.pack_id) {
      // Re-lookup from fresh pack IDs
      const origPlayer = uniquePlayers.find((p) => p.name === row.name);
      row.pack_id =
        origPlayer?.pac && origPlayer.pac !== "СОЛО"
          ? packIdMap[origPlayer.pac] ?? null
          : null;
    }
  }

  const dbPlayers = await insertRows("players", playerRows);
  console.log(`Players: ${dbPlayers.length} inserted`);

  // Build player lookup maps: normalized name → { id, name }
  const playerByNormalizedName = new Map();
  for (const p of dbPlayers) {
    playerByNormalizedName.set(normalize(p.name), {
      id: p.id,
      name: p.name,
    });
  }

  // ────────────────────────────────────────────────────────────────────────
  // 3. Player aliases  (from nickAliases)
  // ────────────────────────────────────────────────────────────────────────
  const nickAliases = d.nickAliases ?? {};
  const aliasRows = [];

  for (const [aliasKey, canonicalName] of Object.entries(nickAliases)) {
    // Skip __diff__ meta-entries and "different" markers
    if (aliasKey.startsWith("__diff__")) continue;
    if (canonicalName === "different") continue;

    const normalizedAlias = normalize(aliasKey);
    // Resolve canonical name to a player
    const target = playerByNormalizedName.get(normalize(canonicalName));
    if (!target) continue; // canonical player not found – skip

    // Don't create alias if it's identical to the player's own normalized name
    if (normalizedAlias === normalize(target.name)) continue;

    aliasRows.push({
      player_id: target.id,
      alias_text: aliasKey,
      alias_text_normalized: normalizedAlias,
      created_from: "manual",
    });
  }

  // De-duplicate by alias_text_normalized (unique constraint in DB)
  const seenAliasNorm = new Set();
  const dedupAliasRows = [];
  for (const row of aliasRows) {
    if (seenAliasNorm.has(row.alias_text_normalized)) continue;
    seenAliasNorm.add(row.alias_text_normalized);
    dedupAliasRows.push(row);
  }

  const dbAliases = await insertRows("player_aliases", dedupAliasRows);
  console.log(`Player aliases: ${dbAliases.length} inserted`);

  // ────────────────────────────────────────────────────────────────────────
  // FIX #1 — Build full in-memory alias map AFTER aliases are imported
  // ────────────────────────────────────────────────────────────────────────
  // aliasMap: normalized text → { playerId, canonicalName }
  // Sources (in priority order):
  //   1) Player's own normalized name
  //   2) Imported player_aliases (alias_text_normalized → player)
  //   3) Raw nickAliases fallback (for aliases that didn't get imported,
  //      e.g. canonical player was missing but might match by chain)

  const aliasMap = new Map();

  // (a) Player own names (highest priority — never overwritten)
  for (const p of dbPlayers) {
    aliasMap.set(normalize(p.name), { playerId: p.id, canonicalName: p.name });
  }

  // (b) Imported aliases
  for (const a of dbAliases) {
    const norm = a.alias_text_normalized;
    if (!aliasMap.has(norm)) {
      const playerEntry = playerByNormalizedName.get(
        normalize(
          dbPlayers.find((p) => p.id === a.player_id)?.name ?? ""
        )
      );
      if (playerEntry) {
        aliasMap.set(norm, {
          playerId: playerEntry.id,
          canonicalName: playerEntry.name,
        });
      }
    }
  }

  // (c) Fallback: raw nickAliases chains (for entries that resolved to a
  //     known player but weren't imported as aliases, e.g. transitive)
  for (const [aliasKey, canonicalName] of Object.entries(nickAliases)) {
    if (aliasKey.startsWith("__diff__")) continue;
    if (canonicalName === "different") continue;
    const norm = normalize(aliasKey);
    if (aliasMap.has(norm)) continue; // already resolved

    // Try to resolve canonical name through the alias map itself
    const resolved = aliasMap.get(normalize(canonicalName));
    if (resolved) {
      aliasMap.set(norm, {
        playerId: resolved.playerId,
        canonicalName: resolved.canonicalName,
      });
    }
  }

  console.log(`Alias map: ${aliasMap.size} total entries`);

  // ── Unified resolver ────────────────────────────────────────────────────
  /**
   * Resolve a raw player name to { playerId, resolvedName } or null.
   * Uses:
   *   1. Direct normalized player name lookup
   *   2. Alias map (imported aliases + nickAliases fallback)
   */
  function resolvePlayer(rawName) {
    if (!rawName) return null;
    const norm = normalize(rawName);
    const hit = aliasMap.get(norm);
    if (hit) return { playerId: hit.playerId, resolvedName: hit.canonicalName };
    return null;
  }

  // ────────────────────────────────────────────────────────────────────────
  // 4. Calendar events  (manualEvents + eventStatuses)
  // ────────────────────────────────────────────────────────────────────────
  const manualEvents = d.manualEvents ?? [];
  const eventStatuses = d.eventStatuses ?? {};
  const eventOverrides = d.eventOverrides ?? {};

  const calendarRows = manualEvents.map((e) => {
    const statusKey = `${e.date}|manual_${e.id}`;
    const overrideValue = eventOverrides[statusKey] ?? null;
    return {
      title: e.title,
      event_date: e.date,
      event_time: e.time ?? null,
      type: "Manual",
      status: eventStatuses[statusKey] === true ? "done" : null,
      source: "manual",
      // FIX #3: pass JSONB fields as JS objects, not JSON strings
      override_json: overrideValue,
    };
  });

  const dbEvents = await insertRows("calendar_events", calendarRows);
  console.log(`Calendar events: ${dbEvents.length} inserted`);

  // Map "date|title" → event id (for linking sessions)
  const eventByDate = Object.fromEntries(
    dbEvents.map((e) => [e.event_date, e.id])
  );

  // ────────────────────────────────────────────────────────────────────────
  // 5. App settings (valueWeights, etc.)
  // ────────────────────────────────────────────────────────────────────────
  const settingsRows = [];
  if (d.valueWeights) {
    settingsRows.push({
      key: "valueWeights",
      value_json: d.valueWeights,
    });
  }
  if ("exhaustedKeys" in d) {
    settingsRows.push({
      key: "exhaustedKeys",
      value_json: d.exhaustedKeys,
    });
  }
  if (settingsRows.length) {
    await upsertRows("app_settings", settingsRows, { onConflict: "key" });
    console.log(`App settings: ${settingsRows.length} upserted`);
  }

  // ────────────────────────────────────────────────────────────────────────
  // 6. KM Sessions + player stats  (appliedStatsByDate)
  // ────────────────────────────────────────────────────────────────────────
  // FIX #2: Remove screenPlayersMap from META_KEYS so it is processed as a
  // grouped dict (Case B) and its player arrays are imported into
  // km_session_player_stats with leader_name = subKey.
  const META_KEYS = new Set([
    "players",
    "appliedAt",
    "raidTotal",
    "commandChannel",
    "packLeaders",
  ]);

  const appliedStatsByDate = d.appliedStatsByDate ?? {};

  for (const [dateStr, session] of Object.entries(appliedStatsByDate)) {
    // 6a. Upsert the km_session row
    // FIX #3: JSONB fields passed as JS objects (not JSON.stringify)
    const sessionRow = {
      session_date: dateStr,
      event_id: eventByDate[dateStr] ?? null,
      raid_total: session.raidTotal ?? null,
      applied_at: session.appliedAt ?? null,
      command_channel_json: session.commandChannel ?? null,
      pack_leaders_json: session.packLeaders ?? null,
      screen_players_map_json: session.screenPlayersMap ?? null,
      raw_snapshot_json: session,
    };
    const [dbSession] = await upsertRows("km_sessions", [sessionRow], {
      onConflict: "session_date",
    });
    const sessionId = dbSession.id;

    // Delete existing stats for this session (idempotent re-run)
    await sb
      .from("km_session_player_stats")
      .delete()
      .eq("session_id", sessionId);

    // 6b. Import top-level `players` array as stat rows
    const statRows = [];
    const topPlayers = session.players ?? [];
    for (const p of topPlayers) {
      const rawName = p._rawName ?? p.name;
      const resolved = resolvePlayer(rawName);
      statRows.push({
        session_id: sessionId,
        player_id: resolved?.playerId ?? null,
        raw_name: rawName,
        resolved_name: resolved?.resolvedName ?? p.name,
        detected_profa: p.class2 ?? null,
        kills: p.kills ?? 0,
        deaths: p.deaths ?? 0,
        pvp_dmg: p.pvp_dmg ?? 0,
        pve_dmg: p.pve_dmg ?? 0,
        pack_name: null,
        leader_name: null,
        // FIX #3: pass as JS object (JSONB)
        raw_payload_json: p,
      });
    }

    // 6c. Iterate remaining session keys for grouped player arrays.
    // screenPlayersMap is now included here (not in META_KEYS) and handled
    // as Case B (dict of arrays).
    for (const [key, value] of Object.entries(session)) {
      if (META_KEYS.has(key)) continue;

      // Case A: value is a flat array of player-like objects
      if (Array.isArray(value)) {
        const playerLike = value.filter(isPlayerLikeObject);
        if (playerLike.length === 0) continue;

        console.log(
          `  Session ${dateStr}: importing grouped key "${key}" (${playerLike.length} players)`
        );
        for (const p of playerLike) {
          const rawName = p._rawName ?? p.name;
          const resolved = resolvePlayer(rawName);
          statRows.push({
            session_id: sessionId,
            player_id: resolved?.playerId ?? null,
            raw_name: rawName,
            resolved_name: resolved?.resolvedName ?? p.name,
            detected_profa: p.class2 ?? null,
            kills: p.kills ?? 0,
            deaths: p.deaths ?? 0,
            pvp_dmg: p.pvp_dmg ?? 0,
            pve_dmg: p.pve_dmg ?? 0,
            pack_name: null,
            leader_name: key,
            raw_payload_json: p,
          });
        }
        continue;
      }

      // Case B: value is a dict of arrays (screenPlayersMap pattern and others)
      if (value && typeof value === "object" && !Array.isArray(value)) {
        let anyImported = false;
        for (const [subKey, subValue] of Object.entries(value)) {
          if (!Array.isArray(subValue)) continue;
          const playerLike = subValue.filter(isPlayerLikeObject);
          if (playerLike.length === 0) continue;

          anyImported = true;
          for (const p of playerLike) {
            const rawName = p._rawName ?? p.name;
            const resolved = resolvePlayer(rawName);
            statRows.push({
              session_id: sessionId,
              player_id: resolved?.playerId ?? null,
              raw_name: rawName,
              resolved_name: resolved?.resolvedName ?? p.name,
              detected_profa: p.class2 ?? null,
              kills: p.kills ?? 0,
              deaths: p.deaths ?? 0,
              pvp_dmg: p.pvp_dmg ?? 0,
              pve_dmg: p.pve_dmg ?? 0,
              pack_name: null,
              leader_name: subKey,
              raw_payload_json: p,
            });
          }
        }
        if (anyImported) {
          console.log(
            `  Session ${dateStr}: imported grouped dict key "${key}"`
          );
        }
      }
    }

    // Batch-insert stat rows (Supabase limit ~1000 per call)
    const BATCH = 500;
    for (let i = 0; i < statRows.length; i += BATCH) {
      await insertRows(
        "km_session_player_stats",
        statRows.slice(i, i + BATCH)
      );
    }
    console.log(
      `  Session ${dateStr}: ${statRows.length} stat rows inserted`
    );
  }

  // ────────────────────────────────────────────────────────────────────────
  // 7. Player profa history  (playerProfaByDate)
  // ────────────────────────────────────────────────────────────────────────
  const playerProfaByDate = d.playerProfaByDate ?? {};
  const profaRows = [];

  // We also need session_id by date for FK
  const { data: allSessions } = await sb
    .from("km_sessions")
    .select("id, session_date");
  const sessionIdByDate = Object.fromEntries(
    (allSessions ?? []).map((s) => [s.session_date, s.id])
  );

  for (const [playerName, dateMap] of Object.entries(playerProfaByDate)) {
    const resolved = resolvePlayer(playerName);
    if (!resolved) {
      console.warn(
        `  playerProfaByDate: cannot resolve player "${playerName}" — skipped`
      );
      continue;
    }
    for (const [dateStr, profa] of Object.entries(dateMap)) {
      profaRows.push({
        player_id: resolved.playerId,
        session_id: sessionIdByDate[dateStr] ?? null,
        session_date: dateStr,
        profa,
        source: "backup",
      });
    }
  }

  if (profaRows.length) {
    // Use upsert on the unique(player_id, session_date) constraint.
    // Supabase JS needs the column names for onConflict.
    await upsertRows("player_profa_history", profaRows, {
      onConflict: "player_id,session_date",
    });
    console.log(`Player profa history: ${profaRows.length} upserted`);
  }

  // ────────────────────────────────────────────────────────────────────────
  // 8. Player notes  (playerNotes)
  // ────────────────────────────────────────────────────────────────────────
  const playerNotes = d.playerNotes ?? {};
  const noteRows = [];

  for (const [playerName, content] of Object.entries(playerNotes)) {
    const resolved = resolvePlayer(playerName);
    if (!resolved) {
      console.warn(
        `  playerNotes: cannot resolve player "${playerName}" — skipped`
      );
      continue;
    }
    noteRows.push({
      player_id: resolved.playerId,
      content: typeof content === "string" ? content : JSON.stringify(content),
      author: null,
    });
  }

  if (noteRows.length) {
    await insertRows("player_notes", noteRows);
    console.log(`Player notes: ${noteRows.length} inserted`);
  }

  // ────────────────────────────────────────────────────────────────────────
  console.log("\n✅ Import complete.");
}

main().catch((err) => {
  console.error("FATAL:", err);
  process.exit(1);
});
