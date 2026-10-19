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
  "contentVersion": "2026.10.19.8",
  "tag": "v2026.10.19.8",
  "dishCount": 200,
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

The app compares **segment by segment as integers** (`2026.10.19.10 > 2026.10.19.9`) and
**refuses to move backwards**. A remote version older than the local one is dropped with
`downgradeIgnored` and the local catalog stays.

This is not hypothetical. It was a real incident: the bundled snapshot was rolled back to
v4 while the CDN still served a v3 manifest, and a naive "just download whatever manifest
says" client downgraded every device.

Consequence for operators: **you cannot roll back by lowering the version number.** Rolling
back means publishing a *new* version that carries the *old* content.

Also: the built-in snapshot wins when it is newer than the cached copy, so an app update
that ships fresher content invalidates the cache instead of being overwritten by it.

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

## Images

Dish photos live at `images/<dish-id>.jpg` and are **served from `main`, not from the
tag**. This asymmetry with `dishes.json` is deliberate:

- The catalog must match its version exactly — new content with stale photos is a lie.
- Photos must *not*. A tag-pinned image URL guarantees one broken case: an app whose
  bundled snapshot is still `v6` asks for `v6/images/x.jpg` while the photo only shipped
  with `v7` → 404, and the user sees a recipe with no picture until the next content sync.
- Adding photos is purely additive. Branch-pinned URLs only pay the CDN's ~5 minute
  propagation, which is harmless.

So: `scripts/publish.sh` **never** touches `images/`. Commit and push photos separately.

```bash
scripts/import_image.sh <source.png> <dish-id>   # crop watermark → 1200px → JPEG q78
git add images && git commit -m "images: ..." && git push
```

`import_image.sh` performs three non-optional steps: crop the bottom ~15.6% (the generator
stamps a watermark there), downscale to 1200px wide, and convert to JPEG q78 — that last
one takes 200 photos from ~400 MB PNG to ~36 MB.

Any dish may legitimately have no photo. The app renders a region-tinted placeholder, so a
missing image is a cosmetic gap, never an error. Do not point several dish ids at one file
to "fill" coverage.

## Identifiers are a public contract

`dish.id`, ingredient ids and equipment ids are baked into user data (pantry, saved,
shopping list) on devices you cannot reach. Renaming one silently orphans that data.
Only ever **add**; deprecate by keeping the id and hiding the dish, never by renaming.

## What does not belong here

- Secrets, tokens, signing keys.
- User data or anything per-install.
- Image bytes inlined into `dishes.json`. Photos are fetched lazily by URL; base64 inlining
  would make every cold start download the entire photo library.
