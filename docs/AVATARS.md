# Avatar artwork

Tracking, notification cards, Git counters/effects, and toolbar actions belong to Arta, not to a particular character. The bundled avatar is loaded through `AvatarAssets` from `Sources/CompanionApp/Resources/Pet/`.

An avatar contains:

- `sprites.png`: a transparent, evenly sized grid. Each state occupies one row and animation frames run left to right.
- `menu-icon.pdf`: recommended vector artwork designed specifically for a 20-point menu-bar icon. A transparent PNG can also be used; provide enough resolution for Retina rendering. Use a simple face or silhouette with high contrast rather than a tiny full-body sprite.
- `manifest.json`: describes layout and artwork choices.

```json
{
  "columns": 4,
  "rows": 4,
  "framesPerState": 4,
  "secondsPerFrame": 0.32,
  "states": ["idle", "working", "waiting", "finished"],
  "menuIcon": "menu-icon.pdf",
  "interpolation": "pixel",
  "workingOverlay": "laptop"
}
```

The four named states are required, but their row order and the number of frames may change. Use `smooth` interpolation for illustrated artwork, or `pixel` for pixel art. Omit `workingOverlay` if the avatar's working frames already depict its working pose. The `laptop` option is an app-drawn overlay for the current character.

The menu icon filename must stay inside the avatar directory. Invalid manifests fall back to the original layout; a missing menu icon falls back to the idle frame. Motion policy remains shared: quiet during routine work, animation on hover or attention, and respect for Reduce Motion.

To create another bundled character, replace the artwork and manifest in this directory, build with `scripts/build-app.sh`, and inspect all four states and the menu icon. Source builds currently bundle one active avatar; a user-facing avatar gallery/runtime selector is not implemented yet. This asset contract makes adding that selector possible without changing tracking or notification logic.

The current vector mark is reproducible with `swift scripts/RenderMenuIcon.swift`. README previews can be regenerated with `scripts/render-readme-media.sh`.
