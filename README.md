# David Deutsch Anthology

Online at https://mokagio.github.io/david-deutsch-anthology/

---

This project aims to collect all of [David Deutsch](https://www.daviddeutsch.org.uk/)'s speeches, talks, and interviews.

It is both a personal reference and an attempt to share David's powerful worldview.

Contribute by adding entries to `list.yml`.

## Podcast feed

The anthology also publishes a podcast feed at `/podcast.rss`, so the interviews can be listened to in a normal podcast app.

A podcast client needs a playable audio file, not a link to the episode's web page, so each entry has to be resolved to one.
`audio_urls.yml` is that dictionary, keyed by the URL in `list.yml` and tracked in the repository.

Adding an entry to `list.yml` is enough: the build resolves anything the dictionary has never seen, so a new interview reaches the feed whether or not the dictionary was updated first.
Entries the dictionary already answered are taken at their word, including the ones it found no audio for, so a normal build stays offline.

```sh
rake                                     # test, generate, validate
ruby generate_podcast_rss.rb --offline   # build from the dictionary alone
```

Resolution tries, in order: the URL itself when it already points at audio, the iTunes API for Apple Podcasts links, the show's feed, and finally the episode page.
Matching an entry to an episode in a show's feed is a heuristic, so the dictionary records the episode title it settled on — worth a glance in the diff.

Commit `audio_urls.yml` when a build updates it.
Nothing breaks if you don't, but the deploy re-resolves those entries every time, and the matched titles go unreviewed.

Entries with no audio stay out of the feed rather than appearing as items no app can play; the build lists them.
Video-only appearances are the usual reason.

To reattempt those, or to rebuild the dictionary after changing the resolver:

```sh
ruby resolve_audio_urls.rb --retry-failed
ruby resolve_audio_urls.rb --refresh
```
