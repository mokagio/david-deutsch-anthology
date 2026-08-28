# frozen_string_literal: true

require_relative 'image_probe'

# Checks the channel artwork before the feed points a client at it.
#
# The file is served by extension, so one named `.png` holding a JPEG ships a
# `Content-Type` that contradicts its own bytes — which is how artwork gets
# rejected by a client that reads the header rather than the name.
module Cover
  # Dropped in by hand: nothing in `list.yml` is ours to use as a cover.
  PATHS = %w[assets/cover.jpg assets/cover.jpeg assets/cover.png].freeze

  FORMATS = { '.jpg' => :jpeg, '.jpeg' => :jpeg, '.png' => :png }.freeze

  EXTENSIONS = { jpeg: 'jpg', png: 'png' }.freeze

  # Apple's floor, and what a client wants for a full-screen tile.
  MIN_EDGE = 1400

  # Feed validators flag a cover past half a megabyte, and a player downloads it
  # before it will show anything at all.
  MAX_BYTES = 500_000

  class << self
    def errors(path)
      bytes = File.binread(path, ImageProbe::HEADER_BYTES)
      extension = File.extname(path).downcase

      format_errors(path, bytes, extension) + size_errors(path, bytes) + weight_errors(path)
    end

    private

    def format_errors(path, bytes, extension)
      actual = ImageProbe.format(bytes)
      return ["#{path} is not a JPEG or a PNG"] unless actual

      return [] if FORMATS[extension] == actual

      ["#{path} holds #{actual.to_s.upcase} data — rename it to #{File.basename(path, '.*')}.#{EXTENSIONS[actual]}"]
    end

    def weight_errors(path)
      bytes = File.size(path)
      return [] if bytes <= MAX_BYTES

      ["#{path} is #{(bytes / 1000.0).round}KB, over the #{MAX_BYTES / 1000}KB a validator will pass — " \
       'resize it to 1400px and re-encode rather than converting it, since a photograph is far larger as a PNG']
    end

    def size_errors(path, bytes)
      size = ImageProbe.dimensions(bytes)
      return ["#{path}: could not read the dimensions"] unless size

      errors = []
      errors << "#{path} is #{size}, and channel artwork has to be square" unless size.square?
      errors << "#{path} is #{size}, under the #{MIN_EDGE}px a client wants" if [size.width, size.height].min < MIN_EDGE
      errors
    end
  end
end
