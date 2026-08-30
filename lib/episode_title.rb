# frozen_string_literal: true

# A show numbers its episodes for its own feed; the anthology does not. An entry
# is titled as the conversation is called — "#4 - Decisions" enters as
# "Decisions" — because a position in one show's series says nothing to a reader
# meeting it among ninety entries sorted by date.
#
# Only the marked forms are read as numbering. A bare leading number is left
# alone: it is as likely to be the title, as in "2001: A Space Odyssey".
module EpisodeTitle
  NUMBERING = /\A(?:#\s*-?\d+|ep(?:isode)?\.?\s*#?-?\d+)\s*[-–—:.|]?\s+/i

  class << self
    def numbered?(title) = title.to_s.match?(NUMBERING)

    def strip_numbering(title) = title.to_s.sub(NUMBERING, '').strip
  end
end
