# David Deutsch Anthology

Online at https://mokagio.github.io/david-deutsch-anthology/

---

This project aims to collect all of [David Deutsch](https://www.daviddeutsch.org.uk/)'s speeches, talks, and interviews.

It is both a personal reference and an attempt to share David's powerful worldview.

Contribute by adding entries to `list.yml`.

## Podcast feed

The anthology also publishes a podcast feed at `/podcast.rss`, so the interviews can be listened to in a normal podcast app.

A podcast client needs a playable audio file, not a link to the episode's web page, and an `<enclosure>` has to state that file's size and type.
`list.yml` records all three, as `audio_url`, `audio_type` and `audio_length`, and is the source of truth for them as for everything else.

Anything in `podcast_interviews` or `talks` carrying those fields is published, so a TED talk released as a podcast episode stays filed as a talk and still reaches the feed.
Entries in the other sections never do, whatever they record.

The `/audit-list` skill finds and records them.
It also reports links that have rotted.

```sh
rake                                        # test, generate, validate
ruby generate_podcast_rss.rb --no-resolve   # use only what the list records
```

Because the list carries the size and type, a build asks nobody anything and takes a fraction of a second.
That is not a nicety: an earlier version probed each file at build time, and Substack blocks GitHub's runners, so four episodes vanished from a deploy that reported success.

The deploy passes `--no-resolve`, so it touches nothing but `list.yml`.
Run locally without that flag, the build also tries to resolve entries that have no `audio_url` yet, which is convenient when adding one by hand but is thrown away afterwards — a build has no business editing the source of truth.

Resolution tries, in order: the URL itself when it already points at audio, the iTunes API for Apple Podcasts links, the show's feed, and finally the episode page.
Matching an entry to an episode in a show's feed is a heuristic, which is why the skill puts the result in a diff to be looked at.

An interview therefore reaches the feed when `/audit-list` records it, not merely when it is added to the list.

Interviews with no audio stay out of the feed rather than appearing as items no app can play; the build lists them.
