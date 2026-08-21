# frozen_string_literal: true

require 'fileutils'

# Everything in `assets/` is published as-is, so a file lands on the site by being
# put there — the cover the feed points at, the icons the page declares.
#
# Both generators publish, because CI runs them as separate scripts rather than
# through `rake`, and either one alone has to produce a complete site.
module Assets
  DIR = 'assets'

  def self.publish(into:)
    return unless Dir.exist?(DIR)

    FileUtils.mkdir_p(into)
    Dir.children(DIR).sort.each do |name|
      FileUtils.cp(File.join(DIR, name), File.join(into, name))
    end
  end
end
