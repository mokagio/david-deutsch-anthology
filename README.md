# David Deutsch Anthology

Online at https://mokagio.github.io/david-deutsch-anthology/

---

This project aims to collect all of [David Deutsch](https://www.daviddeutsch.org.uk/)'s speeches, talks, and interviews.

It is both a personal reference and an attempt to share David's powerful worldview.

Contribute by adding entries to `list.yml`.

## Podcast feed

The anthology also publishes a podcast feed at `/podcast.rss`, so the interviews can be listened to in a normal podcast app.

A podcast client needs a playable audio file, not a link to the episode's web page, so a podcast interview reaches the feed only once its `audio_url` is known.
`list.yml` is the source of truth for that, alongside everything else.

The `/audit-list` skill finds those URLs and records them.
It also reports links that have rotted.

```sh
rake                                        # test, generate, validate
ruby generate_podcast_rss.rb --no-resolve   # use only what the list records
```

An entry with no `audio_url` is resolved during the build too, so a newly added interview reaches the feed before anyone has run the skill.
That costs a few minutes per build and is thrown away afterwards — a build has no business editing the source of truth — so recording the URL with the skill is what makes it stop.

Resolution tries, in order: the URL itself when it already points at audio, the iTunes API for Apple Podcasts links, the show's feed, and finally the episode page.
Matching an entry to an episode in a show's feed is a heuristic, which is why the skill puts the result in a diff to be looked at.

No build is fully offline: an `<enclosure>` must state the file's MIME type and byte length, and `list.yml` records neither, so every audio URL is probed on the way out.
An entry whose audio cannot be reached is left out of the feed rather than published as an item no app can play, as are the interviews that were only ever filmed.
The build lists both.
