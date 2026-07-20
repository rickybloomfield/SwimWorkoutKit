# Shared workout catalogs

This directory is published at `https://www.openswimworkout.com/catalog/` and
serves the shared workout catalogs that Open Swim Workout apps can offer to
their users.

## Files

- `index.json` — the catalog manifest. Lists every available catalog with a
  stable `id`, display `name`, `author`, `description`, the `url` of its
  archive file, a `workoutCount`, an ISO `updated` date, and a `version`.
  Apps read this to render the "Shared Workouts" list, so display strings
  live here — not in app code. **`version` is the auto-update signal**: apps
  that have added a catalog re-sync automatically when it changes, so it must
  be bumped with every archive change (the publish script does this).
- `<id>.swimworkouts` — one standard Open Swim Workout archive per catalog
  (`format: open-swim-workout-archive`), exactly what the app's
  "Export All Workouts" produces. Export **without photos**: apps ignore
  bundled images in catalogs, and base64 photos bloat the file.

## Updating a catalog

1. In the app: Settings → turn off "Include photos in export" → Export All
   Workouts.
2. Run `Scripts/update-catalog.sh <export-file> [catalog-id]` — it copies the
   archive here and updates the manifest entry (version bump, count, date) in
   one step, refusing exports that still contain photos.
3. Commit and push — GitHub Pages redeploys the site.

Apps sync by content: new workouts are added, upstream removals are cleaned
up, and workouts a user has edited or favorited are never touched. Before
publishing, review the export for anything you'd rather keep private (workout
dates, locations, author fields).

## Adding a catalog

Add a new entry to `index.json` with a unique `id` (it tags workouts in
users' libraries, so never reuse or rename one) and drop the matching
`<id>.swimworkouts` archive here.
