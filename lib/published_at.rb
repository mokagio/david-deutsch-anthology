# frozen_string_literal: true

require 'time'

# When an episode says it was published, which a client sorts by and shows
# beside it.
#
# `list.yml` records a day, and a day has to be given an hour before it is an
# instant. Midday UTC rather than midnight: midnight is the recorded day only
# east of Greenwich, and a listener in New York is shown the day before.
#
# The zone is stated because `Time.parse` reads a bare date in the machine's
# own, which had the feed CI builds and the feed a laptop builds disagreeing by
# eleven hours over the same list.
module PublishedAt
  DAY = %r{\A\d{4}[-/]\d{1,2}[-/]\d{1,2}\z}
  # `Z`, `+11:00`, `-0500`, and the named zones RFC 2822 allows.
  ZONE = /(?:Z|[+-]\d{2}:?\d{2}|[A-Za-z]{2,5})\z/

  class << self
    # Zero offset whatever zone the instant was stated in, and written `+0000`:
    # `Time#rfc2822` prints a `utc?` time as `-0000`, which RFC 5322 reserves for
    # a sender whose own zone is unknown.
    def parse(stated) = Time.parse(instant(stated.to_s.strip)).getlocal('+00:00')

    private

    def instant(text)
      return "#{text} 12:00:00 UTC" if text.match?(DAY)

      text.match?(ZONE) ? text : "#{text} UTC"
    end
  end
end
