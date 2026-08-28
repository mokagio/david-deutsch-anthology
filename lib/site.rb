# frozen_string_literal: true

require_relative 'cover'
require_relative 'image_probe'

# What the site is called, where it lives, and the picture that stands for it.
#
# Slack, iMessage and the rest build a link preview out of Open Graph tags and
# nothing else — no tags, no card, which is why a bare link unfurled as a bare
# link.
module Site
  URL = 'https://mokagio.github.io/david-deutsch-anthology/'
  TITLE = 'The David Deutsch Anthology'
  DESCRIPTION = "A growing collection of David Deutsch's books, talks, and interviews."
  IMAGE_ALT = 'David Deutsch, against a spiral galaxy'

  Image = Struct.new(:url, :width, :height, keyword_init: true)

  class << self
    # The channel artwork doubles as the preview picture. `assets/` is published
    # flat, so the file's name is its path on the site.
    #
    # The dimensions are stated so an unfurl can lay out the card before it has
    # fetched the image, and left out when the header will not measure.
    def image
      path = Cover::PATHS.find { |candidate| File.exist?(candidate) }
      return nil unless path

      size = ImageProbe.dimensions(File.binread(path, ImageProbe::HEADER_BYTES))
      Image.new(url: "#{URL}#{File.basename(path)}", width: size&.width, height: size&.height)
    end
  end
end
