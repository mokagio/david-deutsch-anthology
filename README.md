# David Deutsch Anthology

Online at https://mokagio.github.io/david-deutsch-anthology/

---

This project aims to collect all of [David Deutsch](https://www.daviddeutsch.org.uk/)'s speeches, talks, and interviews.

It is both a personal reference and an attempt to share David's powerful worldview.

Contribute by adding entries to `list.yml`.

## Podcast feed

The anthology also publishes a podcast feed at `/podcast.rss`, so the interviews can be listened to in a normal podcast app.

A podcast client needs a playable audio file, not a link to the episode's web page, so each entry has to be resolved to one.
`audio_urls.yml` is that dictionary, keyed by the URL in `list.yml` and tracked in the repository: the build reads it and never touches the network.

After adding entries, run:

```sh
rake resolve   # fill in audio_urls.yml for the new entries
rake           # test, generate, validate
```

`rake resolve` tries, in order: the URL itself when it already points at audio, the iTunes API for Apple Podcasts links, the show's feed, and finally the episode page.
Matching an entry to an episode in a show's feed is a heuristic, so the dictionary records the episode title it settled on — worth a glance in the diff.

Entries it cannot resolve stay out of the feed rather than appearing as items no app can play; `rake generate` lists them.
Video-only appearances are the usual reason.

To reattempt them, or to rebuild the dictionary from scratch:

```sh
ruby resolve_audio_urls.rb --retry-failed
ruby resolve_audio_urls.rb --refresh
```
