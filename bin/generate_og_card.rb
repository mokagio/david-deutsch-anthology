# frozen_string_literal: true

# Draws `assets/og-card.jpg`, the picture a link preview shows.
#
# By hand, like the cover it is drawn from: it needs Chrome and ImageMagick,
# which the build does not have. Run it whenever the title or the description
# changes, or the cover is replaced.
#
#   ruby bin/generate_og_card.rb
#
# 1200×630 rather than the square cover because Slack drops an image it cannot
# lay out in a card, which is how a link unfurled with a title and no picture.

require 'base64'
require 'shellwords'
require 'tmpdir'

require_relative '../lib/cover'
require_relative '../lib/site'

CHROME = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'

# The bottom of the cover is cropped away: it carries the generator's watermark,
# which reads as a stray mark once the art is bled behind the title.
ART_CROP = '1400x1300+0+0'

GROUND = '#0F0E24'

def page(art)
  <<~HTML
    <!DOCTYPE html>
    <html><head><meta charset="utf-8"><style>
      * { margin: 0; padding: 0; box-sizing: border-box; }
      html, body { width: 1200px; height: 630px; }
      body {
        background: #{GROUND};
        font-family: system-ui, -apple-system, "Helvetica Neue", sans-serif;
        overflow: hidden;
      }
      .art {
        position: absolute;
        inset: 0 0 0 46%;
        background: url(data:image/jpeg;base64,#{art}) center/cover no-repeat;
      }
      /* The art is bled into the ground rather than framed, so the card reads as
         one picture. The stops are on a diagonal to follow the spiral. */
      .fade {
        position: absolute;
        inset: 0;
        background: linear-gradient(100deg,
          #{GROUND} 0%, #{GROUND} 42%,
          rgba(15, 14, 36, 0.92) 52%,
          rgba(15, 14, 36, 0.35) 66%,
          rgba(15, 14, 36, 0.10) 80%,
          rgba(15, 14, 36, 0.28) 100%);
      }
      .text { position: absolute; left: 78px; top: 50%; transform: translateY(-50%); width: 560px; }
      h1 { font-size: 68px; line-height: 1.06; letter-spacing: -0.022em; font-weight: 700; color: #F2F0FF; }
      p { margin-top: 28px; font-size: 29px; line-height: 1.42; color: #A9A4C9; }
      /* The accent the page drifts through, held still. */
      .rule {
        margin-top: 34px;
        width: 108px;
        height: 5px;
        border-radius: 3px;
        background: linear-gradient(90deg,
          oklch(0.672 0.113 300.3), oklch(0.677 0.129 322.0), oklch(0.671 0.116 268.6));
      }
    </style></head>
    <body>
      <div class="art"></div>
      <div class="fade"></div>
      <div class="text">
        <h1>#{Site::TITLE}</h1>
        <p>#{Site::DESCRIPTION}</p>
        <div class="rule"></div>
      </div>
    </body></html>
  HTML
end

cover = Cover::PATHS.find { |candidate| File.exist?(candidate) }
abort "No cover to draw from: expected one of #{Cover::PATHS.join(', ')}." unless cover
abort "Chrome is not at #{CHROME}." unless File.exist?(CHROME)

Dir.mktmpdir do |dir|
  art = File.join(dir, 'art.jpg')
  html = File.join(dir, 'card.html')
  shot = File.join(dir, 'card.png')

  system('magick', cover, '-crop', ART_CROP, '+repage', '-resize', '900x', '-quality', '92', art, exception: true)
  File.write(html, page(Base64.strict_encode64(File.binread(art))))

  system(CHROME, '--headless', '--disable-gpu', '--hide-scrollbars', '--window-size=1200,630',
         "--screenshot=#{shot}", "--default-background-color=#{GROUND.delete('#')}FF",
         '--virtual-time-budget=3000', "file://#{html}", exception: true)

  # Stripped and subsampled to stay well under the few hundred kilobytes an
  # unfurler will fetch before it gives up on the picture.
  system('magick', shot, '-quality', '86', '-sampling-factor', '4:2:0', '-strip', Site::CARD, exception: true)
end

puts "#{Site::CARD}: #{(File.size(Site::CARD) / 1000.0).round}KB"
