# frozen_string_literal: true

require 'minitest/autorun'

require_relative '../lib/image_probe'

class ImageProbeTest < Minitest::Test
  def png(width, height)
    "\x89PNG\r\n\x1A\n".b + [13].pack('N') + 'IHDR'.b + [width, height].pack('N2')
  end

  # SOI, an APP0 segment to be walked past, then the frame header that states the
  # size — the shape of every JPEG a host will serve.
  def jpeg(width, height, app0: 16)
    "\xFF\xD8".b +
      "\xFF\xE0".b + [app0].pack('n') + ("\0".b * (app0 - 2)) +
      "\xFF\xC0".b + [11].pack('n') + "\x08".b + [height, width].pack('n2') + "\x03".b
  end

  def webp(width, height)
    "RIFF".b + [0].pack('V') + 'WEBP'.b + 'VP8X'.b + [10].pack('V') + ("\0".b * 4) +
      [width - 1, height - 1].flat_map { |value| [value & 0xFF, (value >> 8) & 0xFF, (value >> 16) & 0xFF] }.pack('C6')
  end

  def test_reads_png_dimensions
    assert_equal '1400×1400', ImageProbe.dimensions(png(1400, 1400)).to_s
  end

  def test_reads_jpeg_dimensions_past_the_segments_before_the_frame
    assert_equal '3000×3000', ImageProbe.dimensions(jpeg(3000, 3000, app0: 4096)).to_s
  end

  def test_reads_webp_dimensions
    assert_equal '1500×1500', ImageProbe.dimensions(webp(1500, 1500)).to_s
  end

  def test_says_nothing_about_a_format_it_cannot_read
    assert_nil ImageProbe.dimensions('<html>not an image</html>'.b)
  end

  def test_says_nothing_about_a_truncated_header
    assert_nil ImageProbe.dimensions("\xFF\xD8".b)
  end

  def test_square_artwork_is_artwork
    assert_predicate ImageProbe.dimensions(png(1400, 1400)), :artwork?
  end

  def test_a_banner_is_not_artwork
    refute_predicate ImageProbe.dimensions(jpeg(1050, 550)), :artwork?
  end

  def test_a_thumbnail_is_not_artwork
    refute_predicate ImageProbe.dimensions(png(144, 144)), :artwork?
  end

  # Real covers are off by a pixel often enough that exact squareness rejects them.
  def test_a_pixel_off_square_is_still_artwork
    assert_predicate ImageProbe.dimensions(png(1400, 1399)), :artwork?
  end
end
