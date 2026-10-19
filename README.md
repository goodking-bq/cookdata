# cookdata

WokIt recipe content. Single source of truth for everything the app reads at runtime.

## Contract

The app never reads this repository's Git tree directly. It follows a two-hop fetch:

```
manifest.json   (~200 bytes, must always be fresh)
      │  compare contentVersion against the local copy
      ▼  only when different
dishes.json     (the whole catalog)
```

Both files are validated before use. **Any failure falls back to the catalog bundled in
the app binary** — a broken publish must never be able to black-screen the app.

## Files

| File | Owner | Rules |
|---|---|---|
| `dishes.json` | content | `schemaVersion` must match an app that understands it. `contentVersion` must change on **every** publish. |
| `manifest.json` | publishing | Mirrors `contentVersion` + `dishCount` from `dishes.json`. Must not drift. |

`dishCount` exists so the app can reject a truncated catalog before decoding it, and so a
human can eyeball "did all 100 dishes actually ship".

## Versioning

`contentVersion` format: `YYYY.MM.DD.N` (N resets each day).

The app compares for **inequality**, not "greater than". That is deliberate: it makes a
rollback work. If a bad publish goes out and you republish the previous version, the app
must follow it back down.

## Adding or editing dishes

1. Edit `dishes.json`.
2. Bump `contentVersion` and `dishCount` to match.
3. Commit, tag `v<contentVersion>`, push.

Do not hand-edit a publish that is already live. Publishing a new version is always cheaper
than debugging a mutated one, because clients that already synced cannot be un-synced.

## Identifiers are a public contract

`dish.id`, ingredient ids and equipment ids are baked into user data (pantry, saved,
shopping list) on devices you cannot reach. Renaming one silently orphans that data.
Only ever **add**; deprecate by keeping the id and hiding the dish, never by renaming.

## What does not belong here

- Secrets, tokens, signing keys.
- User data or anything per-install.
- Images at first: they bloat the catalog and should be fetched lazily by URL, not inlined.
