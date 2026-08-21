# frozen_string_literal: true

require_relative 'http_client'

# Measures a candidate picture, because what a page calls its image is often not
# artwork at all: `og:image` on a TED talk page is a 1050×550 banner crop, and on
# a show's home page it is frequently a favicon.
#
# A client renders `<itunes:image>` in a square tile, so anything else is either
# letterboxed or cropped through the middle of the subject.
module ImageProbe
  # Enough for the header of any format worth reading; nothing here needs pixels.
  HEADER_BYTES = 65_536

  MIN_EDGE = 400

  # Artwork is square. Real feeds are off by a pixel or two often enough that an
  # exact test would reject perfectly good covers.
  MAX_SKEW = 1.02

  Details = Struct.new(:width, :height) do
    def square? = [width, height].max <= [width, height].min * MAX_SKEW

    def large_enough? = [width, height].min >= MIN_EDGE

    def artwork? = square? && large_enough?

    def to_s = "#{width}×#{height}"
  end

  SOF_MARKERS = [*0xC0..0xC3, *0xC5..0xC7, *0xC9..0xCB, *0xCD..0xCF].freeze

  class << self
    # Nil for a picture that cannot be measured — an unknown format, or a host that
    # will not serve the first bytes — which is not a reason to reject it.
    def details(url)
      response = HttpClient.ranged_get(url, bytes: "0-#{HEADER_BYTES - 1}")
      return nil unless response&.body

      dimensions(response.body.b)
    end

    def dimensions(bytes)
      width, height =
        case format(bytes)
        when :png then png(bytes)
        when :jpeg then jpeg(bytes)
        when :webp then webp(bytes)
        end

      Details.new(width, height) if width&.positive? && height&.positive?
    end

    # What the bytes are, whatever the file is called.
    def format(bytes)
      return :png if bytes.start_with?("\x89PNG\r\n\x1A\n".b)
      return :jpeg if bytes.start_with?("\xFF\xD8".b)

      :webp if bytes[0, 4] == 'RIFF'.b && bytes[8, 4] == 'WEBP'.b
    end

    private

    def png(bytes) = bytes[16, 8]&.unpack('N2')

    # Walk the segment headers to the frame that states the size. Every segment
    # declares its own length, so none of them has to be understood.
    def jpeg(bytes)
      index = 2

      while index + 9 < bytes.bytesize
        return nil unless bytes.getbyte(index) == 0xFF

        marker = bytes.getbyte(index + 1)
        index += 2
        next if standalone?(marker)

        return bytes[index + 3, 4].unpack('n2').reverse if SOF_MARKERS.include?(marker)

        length = bytes[index, 2]&.unpack1('n')
        return nil unless length

        index += length
      end

      nil
    end

    def standalone?(marker) = (0xD0..0xD9).cover?(marker) || marker == 0x01

    def webp(bytes)
      case bytes[12, 4]
      when 'VP8X'.b then [little_endian(bytes, 24) + 1, little_endian(bytes, 27) + 1]
      when 'VP8 '.b then bytes[26, 4]&.unpack('v2')&.map { |value| value & 0x3FFF }
      end
    end

    def little_endian(bytes, offset) = bytes[offset, 3].to_s.unpack('C3').then { |a, b, c| a | (b << 8) | (c << 16) }
  end
end
