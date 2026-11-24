# CinePulse on Yuka

A port of [CinePulse](https://github.com/madireis/vidsrc-wrapper) (React + TMDB) to
[Yuka](https://github.com/davesnx/yuka), the OCaml framework that renders pages on the
server and hydrates islands compiled with Melange.

## Setup

Needs opam, Node, and a Yuka checkout at `~/Documents/yuka` (override with `YUKA=...`).

```sh
make init                 # local switch in ./_opam, yuka pinned to $(YUKA), npm install
cp .env.example .env      # then set TMDB_API_KEY (or export it)
make serve                # http://localhost:8080 (PORT=...)
make dev                  # rebuild, restart and reload on change
```

`make init` pins yuka through [scripts/patch-yuka-opam.sh](scripts/patch-yuka-opam.sh), which
drops `dune subst` (yuka's dune-project has no name) and makes `Yuka.Async`, `Yuka.State` and
`Yuka.Browser` public. Both edits live in the switch, not in the Yuka checkout.

## Layout

- `Routes.ml`: every page, layout and overlay.
- `server/`: TMDB client with a cache, loaders, pages (`pages.mlx`), Dream entry point.
- `shared/`: model and codecs, saved state, and the islands (watchlist button, player,
  search box, sliders, infinite scroll, ...), built for both native and Melange.
- `client/`: the browser entry, which hydrates the islands.
- `assets/app.css`: Tailwind input, built to `static/app.css`.

## Differences from the React app

- The watchlist, history, recent searches and player settings are stored in cookies
  instead of localStorage, so the server renders personalized pages.
- Filters, pagination, tabs, seasons and Decision Mode steps live in the URL.
- The trailer and Decision Mode open as overlay routes above the current page.
