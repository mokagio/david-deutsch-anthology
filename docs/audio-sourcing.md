# Audio sourcing notes

What the podcast hosts and platforms in this list actually do, as opposed to what they claim.
Every entry here cost a wrong answer once.
**Append to it when a new host surprises you** — that is the point of the file.

## Never trust a feed's `length`

Megaphone publishes `length="0"`.
The TED Interview's feed declares 86,077,619 bytes for a file that is 60,223,650 — overstating by 43%, presumably from an earlier encoding.

Both are valid RSS and neither number is the file. Always probe; use the declared value only when the file will not answer.

## Never trust a HEAD response either

acast answers `HEAD` with `content-type: text/plain` and `content-length: 2`.
It is a stub describing nothing, and it sailed through a "length must be positive" check straight into the published feed, where one episode advertised a two-byte enclosure for weeks.

Ask for `Range: bytes=0-0` and read the total out of `Content-Range`.
Treat a HEAD whose content type is not `audio/*` as no answer at all.

**A podcast episode is never a few kilobytes.** `Enclosure::MIN_PLAUSIBLE_BYTES` is the floor, and both the feed builder and the validator enforce it, because "greater than zero" is not a test that catches a stub.

Byte lengths on ad-inserted files drift by a fraction of a percent between requests, which is normal and not worth chasing. A discrepancy of tens of percent is a wrong number.

## Never scrape an aggregator's episode page for audio

A Pocket Casts episode page (`pca.st/xxxx`, redirecting to `pocketcasts.com/podcast/<show>/<uuid>/<episode>/<uuid>`) embeds the mp3 URLs of *several* episodes — the one you want plus neighbours in the same show.
Picking one by position is a coin flip.

Use the page only for the episode title and show name, then find the episode in the show's own RSS feed.
Cross-check: the enclosure you settle on should also appear somewhere on the aggregator page.

## Titles differ across platforms

The same conversation is routinely retitled between its YouTube and podcast releases.
Theories of Everything published `David Deutsch: Einstein Would Fail Modern Grant Applications` as `The Multiverse May Be Real | David Deutsch`, so an exact-title search finds nothing.

Confirm two releases are the same recording by triangulating instead:

- same channel/show author,
- same publication date,
- runtime within a few minutes.

## Podcast audio runs longer than the video

Dynamic ad insertion adds minutes. A `pscrb.fm`, `podtrac.com`, `chrt.fm` or `dts.podtrac.com` hop in the audio URL means ads are being stitched in per request.

Expect the audio to exceed the video: 8123s of video against 8313s of audio was the same TOE episode; 3846s against 3881s was the same Foresight one.
A gap of minutes is normal, an hour is a different recording.

**A much shorter video is a clip, not the episode.**
The IAI published a 753-second excerpt of its 3617-second *In search of nothing* debate, under a near-identical title with the guests reordered.
Title, channel and rough date all agreed; only the runtime gave it away.
Compare the ratio, not just the titles — anything under about half the audio length is an excerpt and does not belong in `youtube_url`.

Corollary: `audio_length` on an ad-inserted file will drift over time.
`/audit-list` reports it as `audio_unreadable` if the URL stops resolving.

## Substack blocks CI

`api.substack.com` serves audio fine from a laptop and refuses GitHub Actions runners.
This is why `list.yml` records `audio_type` and `audio_length` rather than probing at build time, and why the deploy runs `--no-resolve`.

A build that probes drops those episodes *and reports success*, because a feed of whatever survived still validates.

## YouTube liveness needs oEmbed, and oEmbed lies about 401

A deleted video's watch page returns **200**. Liveness has to come from `https://www.youtube.com/oembed?format=json&url=…`, which 400s once the video is gone.

But oEmbed returns **401 for a live video whose owner disabled embedding**.
Resolve that by fetching the watch page and looking for `"status":"OK"` — present means it plays.

oEmbed does not understand channel URLs (`youtube.com/@handle`); check those as ordinary links.

## Throttle per host, and treat 429 as "unknown"

Four `nav.al` links checked back-to-back earn a 429 indistinguishable from a dead link.
Space requests to the same host and retry once before believing a failure.

## HEAD is not universally supported

`dts.podtrac.com` answers HEAD with 405 while serving a ranged GET happily.
Fall back to `Range: bytes=0-0` and read the total from `Content-Range`.

## Unreachable is not dead

`fromthelotus.world` fails the TLS handshake from Ruby *and* from curl.
That is the host refusing us, not evidence the page is gone. Report it separately and do not act on it.

## Finding a show's feed

In order of reliability:

1. `feed_url` recorded on the show in `list.yml`.
2. `<link rel="alternate" type="application/rss+xml">` on the episode page.
3. The same on the **show's own home page** — `list.yml` records it, and it is how the Increments feed was found.
4. iTunes search by show name.

Search is last for a reason: querying "Increments Podcast" returns three unrelated shows, and "Logan Chipkin" returns a show whose episodes match on the guest's name alone.
Whatever the source, confirm by finding the episode in the feed — a feed with no matching episode is the wrong feed.

WordPress advertises a per-post feed at `<post-url>/feed/`, which announces itself as `application/rss+xml` and contains no enclosures at all.
Discovery from an episode page can land on it. Pass the show's real feed explicitly when that happens.

## The same show appears under different names

A producer's video channel and its podcast are often branded differently: the Institute of Art and Ideas publishes the podcast *Philosophy For Our Times*.
They are separate entries in `list.yml` with separate `show` blocks, because `show` records where an appearance was published, not who produced it.

## An episode can already be in the list under another URL

An aggregator link carries no hint that the same conversation is already recorded under the show's own URL — `pca.st/xd56bapl` is the EconTalk episode the list has had all along.
The audio file is the reliable identity; the page URL is not.
`entry_fields.rb` checks and says so.

## Artwork is not whatever a page calls its image

A client renders `<itunes:image>` in a square tile, and three of the four places artwork can come from will happily hand back something else:

- `og:image` on a TED talk page is a 1050×550 banner crop of the stage.
- `og:image` on a show's own site is often the site logo — `nav.al` returns the same `Navatar.png` for every episode page.
- Apple's `artworkUrl600` on a `podcastEpisode` record is the *show's* logo whenever the episode has no picture of its own, with nothing in the record to say so. Compare it against the collection's `artworkUrl600`: identical means it is the show's.

So measure the file. `ImageProbe` reads the dimensions out of the first 64KB — PNG, JPEG and WebP headers — and rejects anything that is not square within a couple of percent or is smaller than 400px. A picture it cannot measure is kept, since an unknown format is not evidence of a bad image.

A show's own channel `<itunes:image>` is always artwork, and is the fallback worth trusting. Take it only from a feed the entry or its show names, or one an episode was matched in — an iTunes search by show name lands on the wrong show often enough that its logo cannot be trusted unchecked.
