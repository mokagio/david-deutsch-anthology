# frozen_string_literal: true

require 'minitest/autorun'
require 'tmpdir'

require_relative '../lib/cover'

class CoverTest < Minitest::Test
  def png(width, height)
    "\x89PNG\r\n\x1A\n".b + [13].pack('N') + 'IHDR'.b + [width, height].pack('N2')
  end

  def jpeg(width, height)
    "\xFF\xD8".b + "\xFF\xC0".b + [11].pack('n') + "\x08".b + [height, width].pack('n2') + "\x03".b
  end

  def errors_for(name, bytes)
    Dir.mktmpdir do |dir|
      path = File.join(dir, name)
      File.binwrite(path, bytes)
      Cover.errors(path)
    end
  end

  def test_accepts_a_square_jpeg_named_jpg
    assert_empty errors_for('cover.jpg', jpeg(3000, 3000))
  end

  def test_accepts_a_square_png_named_png
    assert_empty errors_for('cover.png', png(1400, 1400))
  end

  # A JPEG named `.png` is served as `image/png`, and the header contradicting the
  # bytes is what gets artwork rejected.
  def test_rejects_a_jpeg_wearing_a_png_extension
    errors = errors_for('cover.png', jpeg(3000, 3000))

    assert_equal 1, errors.size
    assert_includes errors.first, 'rename it to cover.jpg'
  end

  def test_rejects_a_picture_that_is_not_square
    assert_includes errors_for('cover.jpg', jpeg(3000, 1500)).first, 'has to be square'
  end

  def test_rejects_a_picture_too_small_for_a_client_to_show
    assert_includes errors_for('cover.png', png(600, 600)).first, 'under the 1400px'
  end

  def test_rejects_a_file_that_is_not_an_image
    assert_includes errors_for('cover.jpg', 'nope'.b).first, 'not a JPEG or a PNG'
  end
end
