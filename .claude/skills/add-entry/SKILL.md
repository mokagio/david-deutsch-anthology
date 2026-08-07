---
name: add-entry
description: |
  Add a podcast interview to `list.yml` from a URL — Pocket Casts, Apple Podcasts, a show's episode page.
  Works out the title, show, date and audio file, then inserts the entry in date order.
  Use when given a link to a David Deutsch appearance, or asked to "add this to the list" or invokes /add-entry.
allowed-tools: Bash(ruby *), Bash(curl *), Bash(git *), Bash(rake *), Bash(grep *), Read, Edit, WebSearch
user-invocable: true
---

# Add an entry to the list

Read [`docs/audio-sourcing.md`](../../../docs/audio-sourcing.md) first if you have not this session.
It records what each host actually does, and every line of it cost a wrong answer once.

## 1. Gather the fields

```sh
ruby .claude/skills/add-entry/scripts/entry_fields.rb <url>
```

It prints a ready-to-paste entry and, on stderr, how it got there.
Pass `--feed URL`, `--show NAME` or `--title TITLE` when it cannot work something out — `--feed` is the one that rescues most failures.

**Read the warnings, they are the point:**

- `weak title match` — it guessed. Confirm the episode is the right one before going further.
- `feed declared length=0` — normal for Megaphone, already handled, mentioned so the number is not a mystery.
- `could not determine a byte length` — stop. Without it the entry cannot enter the feed, and recording a zero would ship an enclosure strict clients reject.

## 2. Fill in what the script cannot judge

**`show.url`** comes from the feed's channel link, which is sometimes a legacy vanity URL.
Check it resolves and prefer the canonical form — `https://youtube.com/TheoriesOfEverything` still works, but `https://www.youtube.com/@TheoriesOfEverything` is what the channel calls itself now.

**`youtube_url`** is worth adding when the conversation also exists as a video, and the script deliberately does not guess.
Titles differ across platforms, so search the guest and show rather than the episode title, then confirm the video is the same recording: same channel, same publication date, runtime within a few minutes of the audio (the script prints the audio duration for this).
Podcast audio is normally the longer of the two — see the ad-insertion note in the sourcing doc.

**The show may already be in the list.** Check before writing:

```sh
grep -n -i '<show name>' list.yml
```

If it is there with a YAML anchor (`&naval`), reference it (`show: *naval`) instead of repeating the block.
If it is there *without* one and this is the second appearance, introduce an anchor.

## 3. Insert it

Entries sit in `published_date` order. Find the neighbours:

```sh
ruby -ryaml -e 'YAML.load_file("list.yml", aliases: true)["podcast_interviews"].each_with_index { |i, n| puts "#{n}: #{i["published_date"]}  #{i["title"][0,45]}" }'
```

Insert with `Edit`, anchored on the following entry's `- title:` line.
Never rewrite `list.yml` through Ruby's YAML dumper: it renames every anchor to `&1` and drops every comment.

Quote the title if it contains a colon.

## 4. Verify

```sh
ruby -ryaml -e 'pi = YAML.load_file("list.yml", aliases: true)["podcast_interviews"]; puts pi.size'
diff <(git show HEAD:list.yml | grep -oE ': [&*][a-z_]+' | sort) <(grep -oE ': [&*][a-z_]+' list.yml | sort)
git diff --stat list.yml
rake
```

Entry count up by exactly one, anchors and aliases unchanged, diff purely additive, and the episode present in the rebuilt feed.

## 5. Write down anything new

If the host did something the sourcing doc does not describe — a redirect that hides the real file, a feed that lies about something, a platform that blocks a fetch — **append it to `docs/audio-sourcing.md`**.
That file is how the next run avoids the mistake this one made.
