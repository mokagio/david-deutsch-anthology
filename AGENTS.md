# David Deutsch Anthology

A static site generated from `list.yml` and deployed to GitHub Pages on push to `main`.

## Commands

```sh
rake                # test, generate, validate
rake test
rake generate       # public/index.html and public/podcast.rss
rake validate       # the feed works in a podcast client
ruby count.rb       # entry tallies
```

No Gemfile — Ruby stdlib only, version pinned in `.ruby-version`.

## Conventions

- Content goes in `list.yml`, markup in `templates/`, shared code in `lib/`.
- `public/` is generated and gitignored: never edit or commit it.
- `list.yml` uses YAML anchors and comments. Edit it as text; a round-trip through Ruby's YAML dumper renames every anchor and drops every comment.
- An entry reaches the feed only if it has `audio_url`, `audio_type` and `audio_length`, and only from `podcast_interviews` or `talks` (`FeedBuilder::LABELS`). The `/audit-list` skill finds and records all three; the size and type are there so the build never probes a third-party host, which is how a deploy once silently lost four episodes.
- `image_url` is the picture a client shows for an episode, read from the entry or from its `show`, and optional: without one a client falls back to the channel artwork, which is `assets/cover.{jpg,jpeg,png}` if that file exists. `/audit-list` records it, preferring the episode's own picture over the show's and measuring every candidate, because `og:image` is as often a banner crop as it is a cover.
- `/add-entry` adds an interview from a URL; `/find-entries` looks for the ones the list is missing.
- Before touching podcast hosts or audio URLs, read [`docs/audio-sourcing.md`](docs/audio-sourcing.md) — what each host actually does, as against what it claims. Append to it whenever one surprises you.
