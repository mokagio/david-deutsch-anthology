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
- A podcast interview reaches the feed only if it has `audio_url`, `audio_type` and `audio_length`. The `/audit-list` skill finds and records all three; the size and type are there so the build never probes a third-party host, which is how a deploy once silently lost four episodes.
