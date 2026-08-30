# frozen_string_literal: true

require 'cgi/escape'
require 'json'
require 'uri'

require_relative 'http_client'

# What Spotify can be asked, and what it will not answer.
#
# It is the one catalogue here with no feed behind it. A show published there
# alone has no RSS to read and no Apple listing to search, and the list already
# carries one such show and one such episode that no sweep could see.
#
# The Web API wants an application's own credentials — `SPOTIFY_CLIENT_ID` and
# `SPOTIFY_CLIENT_SECRET` from developer.spotify.com — and no user login, because
# all of this is public catalogue. Without them the source is skipped and says so.
#
# It never yields audio. An episode's file is Spotify's to play and the API states
# no enclosure, so a hit here is a lead to a recording, not the recording: the
# `audio_preview_url` it does offer is a 30-second clip, which is worse than
# nothing to a feed that publishes what it records.
module Spotify
  TOKEN_URL = 'https://accounts.spotify.com/api/token'
  API = 'https://api.spotify.com/v1'

  # Catalogue endpoints answer for one country at a time and return an empty
  # payload when asked for none.
  MARKET = 'US'

  PAGE = 50

  # Episode search refuses a limit above ten — it answers 400 "Invalid limit" —
  # so the hits come ten at a time, and there are more of them than one page.
  SEARCH_PAGE = 10

  # Pages read per search term. `q=david deutsch` alone matches three dozen.
  MAX_SEARCH_RESULTS = 50

  # A back catalogue is read to its end, up to this many episodes. Nothing he has
  # been on runs longer, and the cap is what stops a daily show from spending the
  # sweep's whole budget on pagination.
  MAX_EPISODES = 500

  SHOW_URL = %r{open\.spotify\.com/show/(?<id>[A-Za-z0-9]+)}
  EPISODE_URL = %r{open\.spotify\.com/episode/(?<id>[A-Za-z0-9]+)}

  class << self
    def configured?(env = ENV) = !id(env).empty? && !secret(env).empty?

    def show_id(url) = url.to_s[SHOW_URL, :id]

    def episode_id(url) = url.to_s[EPISODE_URL, :id]

    def id(env = ENV) = env['SPOTIFY_CLIENT_ID'].to_s

    def secret(env = ENV) = env['SPOTIFY_CLIENT_SECRET'].to_s
  end

  # Holds the access token for the length of one sweep. It is good for an hour,
  # and a sweep is minutes.
  class Client
    def initialize(id: Spotify.id, secret: Spotify.secret)
      @id = id
      @secret = secret
    end

    # Asked once, before any sweep starts: credentials that will be refused are
    # better refused here than inside six threads reading six shows.
    def usable? = !token.nil?

    # Episodes matching a phrase, across the whole catalogue, stripped of the show
    # each belongs to: search says nothing about where an episode was published.
    def search_episodes(term)
      episodes = []
      url = "search?q=#{CGI.escape(term)}&type=episode&market=#{MARKET}&limit=#{SEARCH_PAGE}"

      while url && episodes.size < MAX_SEARCH_RESULTS
        page = get(url)&.dig('episodes')
        break unless page.is_a?(Hash)

        episodes.concat(page_items(page))
        url = page['next']
      end

      episodes
    end

    # One episode, whole, which is the only way to learn what show it is from:
    # reading fifty back at once is forbidden to an application's own credentials.
    def episode(id) = get("episodes/#{id}?market=#{MARKET}")

    # Every episode of one show, oldest page last, as full episodes carrying the
    # show they came from.
    def show_episodes(show_id)
      show = get("shows/#{show_id}?market=#{MARKET}")
      return [] unless show

      episodes = []
      url = "shows/#{show_id}/episodes?market=#{MARKET}&limit=#{PAGE}"
      while url && episodes.size < MAX_EPISODES
        page = get(url)
        break unless page

        episodes.concat(page_items(page))
        url = page['next']
      end

      episodes.map { |episode| episode.merge('show' => show) }
    end

    private

    def page_items(page) = page.is_a?(Hash) ? Array(page['items']).compact : []

    # A `next` link arrives absolute; everything else is asked for by path.
    def get(path)
      return nil unless token

      url = path.start_with?('http') ? path : "#{API}/#{path}"
      response = HttpClient.get(url, headers: { 'Authorization' => "Bearer #{token}" })
      response && JSON.parse(response.body)
    rescue JSON::ParserError
      nil
    end

    # Nil where the credentials were refused, which reads the same to every caller
    # as a catalogue with nothing in it — the difference is said once, by the
    # sweep, rather than raised out of a worker thread.
    def token
      return @token if defined?(@token)

      credentials = ["#{@id}:#{@secret}"].pack('m0')
      response = HttpClient.post_form(
        TOKEN_URL,
        form: { 'grant_type' => 'client_credentials' },
        headers: { 'Authorization' => "Basic #{credentials}" }
      )
      @token = response && JSON.parse(response.body)['access_token']
    rescue JSON::ParserError
      @token = nil
    end
  end
end
