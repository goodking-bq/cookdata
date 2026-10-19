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

```json
// manifest.json
{
  "schemaVersion": 1,
  "contentVersion": "2026.10.19.3",
  "tag": "v2026.10.19.3",
  "dishCount": 7,
  "dishesFile": "dishes.json"
}
```

| Field | Why it exists |
|---|---|
| `schemaVersion` | An old app must refuse a newer structure instead of decoding half a recipe. |
| `contentVersion` | The only thing the app compares to decide whether to download at all. |
| `tag` | The immutable URL the catalog is fetched from. **Must equal `v` + `contentVersion`** — the app rejects the publish otherwise. |
| `dishCount` | Catches a half-pushed catalog. The app refuses to persist a download whose size disagrees. |
| `dishesFile` | Bare filename only. Anything containing `/`, `..` or `:` is rejected as URL injection. |

`manifest.json` is **generated, never hand-edited**. Every field is a derivative of
`dishes.json`, and hand-maintaining derivatives is exactly how the two drift apart.

## Versioning

`contentVersion` format: `YYYY.MM.DD.N` (N resets each day).

The app compares for **inequality**, not "greater than". That is deliberate: it makes a
rollback work. If a bad publish goes out and you republish the previous version, the app
must follow it back down.

## Publishing

```bash
scripts/publish.sh                 # bump the day's counter and publish
scripts/publish.sh 2026.10.20.1    # publish an explicit version
scripts/publish.sh --dry-run       # regenerate manifest, print it, commit nothing
```

The script rewrites `manifest.json` from `dishes.json`, refuses duplicate ids and empty
catalogs, then commits, tags and pushes both. Tag and manifest always move together —
pushing a tag the manifest does not name (or the reverse) makes every client silently
drop the update.

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
