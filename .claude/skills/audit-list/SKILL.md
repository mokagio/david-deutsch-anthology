---
name: audit-list
description: |
  Check every link in `list.yml` and find audio URLs for podcast interviews that lack one.
  Adds `audio_url` to entries where audio was found; reports dead links without touching them.
  Use when asked to "audit the list", "check the links", "find missing audio", or invokes /audit-list.
allowed-tools: Bash(ruby *), Read, Edit, Grep
user-invocable: true
---

# Audit the list

Two passes over `list.yml`: link liveness, and audio discovery for `podcast_interviews`.

## 1. Run the audit

```sh
ruby .claude/skills/audit-list/scripts/audit_list.rb --json
```

Takes several minutes — it resolves audio over the network for every interview without an `audio_url`.
Narrow it with `--links-only` or `--audio-only` when only one pass is wanted.

The report has four keys:

- `audio_found` — an audio URL to add, with the `entry_url` identifying which entry, and `matched_title` when it came from matching an episode in a show's feed.
- `audio_missing` — no audio anywhere. Usually a video-only appearance. Leave alone.
- `broken_links` — confirmed dead.
- `unchecked_links` — the checker could not reach the host. Not evidence of anything.

## 2. Add the audio URLs

**Only ever add `audio_url`. Never change, reorder, or remove anything already in the file.**

For each `audio_found` entry, find the entry in `list.yml` by its `entry_url` and insert `audio_url` directly beneath that URL line, at the same indentation:

```yaml
  - title: David Deutsch on the Pattern
    url: https://www.econtalk.org/david-deutsch-on-the-pattern/
    audio_url: https://cdn.simplecast.com/audio/.../default_tc.mp3
    show: *econtalk
    published_date: 2025/12/22
```

Use `Edit`, never a YAML rewrite: `list.yml` uses anchors (`&naval`, `*naval`) and inline comments, and re-serialising it through Ruby renames every anchor and drops every comment.

When `matched_title` differs noticeably from the entry's own title, say so in your summary — that match was a heuristic and is the one thing worth a human glance.

## 3. Verify

```sh
ruby -ryaml -e 'd = YAML.load_file("list.yml", aliases: true); puts d["podcast_interviews"].size'
grep -c '&' list.yml
```

The interview count must be unchanged and the anchors must still be there.

## 4. Report, do not fix

Surface `broken_links` to the user and stop.
Fixing a dead link means finding where the content moved, which is a judgement call, not a substitution.

Mention `unchecked_links` only in passing; a TLS handshake this script cannot complete usually says more about the checker than the link.
