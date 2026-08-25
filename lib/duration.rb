# frozen_string_literal: true

# How long an episode runs, which a client shows beside it and reads from
# `<itunes:duration>`. Without one it displays 0s until the file is downloaded.
#
# Feeds state it in whichever of three forms they please — `5034`, `62:03`,
# `01:02:34` — so anything read from one is converted to seconds. `list.yml`
# records seconds for a reason beyond tidiness: YAML 1.1 reads an unquoted
# `62:03` as a sexagesimal number, so a clock face written there parses as
# 223380 without a word of complaint.
module Duration
  # A minute of audio is a trailer, not an episode, and a day of it is a parse
  # gone wrong.
  PLAUSIBLE_SECONDS = (60..86_400)

  class << self
    # Nil for anything that is not a duration, which is not a reason to reject
    # the episode: the feed simply says nothing about how long it runs.
    def seconds(stated)
      parts = stated.to_s.strip.split(':')
      return nil if parts.empty? || parts.any? { |part| !part.match?(/\A\d+(?:\.\d+)?\z/) }

      total = parts.reverse.each_with_index.sum { |part, place| part.to_f * (60**place) }
      total.round if PLAUSIBLE_SECONDS.cover?(total)
    end

    def hms(seconds)
      return nil unless seconds

      Kernel.format('%02d:%02d:%02d', seconds / 3600, (seconds % 3600) / 60, seconds % 60)
    end
  end
end
