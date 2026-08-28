# frozen_string_literal: true

require 'time'
require 'open3'

# When the feed's content last changed, which `<lastBuildDate>` states and a
# caching client reads to decide whether to bother re-reading the feed.
#
# The content is this repository — `list.yml` and the templates — so the date is
# the last commit's rather than the clock's: a rebuild that follows no commit
# produces the same feed as the one before it, and a client that already has it
# is told so.
module BuildDate
  class << self
    # Anything building this feed without a repository behind it — a tarball, a
    # checkout with no history — has only the clock to date it by.
    def current(head: method(:head_commit)) = head.call || Time.now.utc

    def head_commit
      out, status = Open3.capture2('git', 'log', '-1', '--format=%cI')
      status.success? ? Time.iso8601(out.strip) : nil
    rescue SystemCallError, ArgumentError
      nil
    end
  end
end
