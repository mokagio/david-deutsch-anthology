# David Deutsch Anthology

A static site generated from `list.yml` and deployed to GitHub Pages on push to `main`.

## Commands

```sh
ruby generate_html.rb              # public/index.html
ruby generate_podcast_rss.rb       # public/podcast.rss
ruby count.rb                      # entry tallies
ruby test/episode_matcher_test.rb  # tests
```

No Gemfile — Ruby stdlib only, version pinned in `.ruby-version`.

## Conventions

- Content goes in `list.yml`, markup in `templates/`.
- `public/` is generated and gitignored: never edit or commit it.
