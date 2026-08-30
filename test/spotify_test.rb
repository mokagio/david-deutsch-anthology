# frozen_string_literal: true

require 'json'
require 'minitest/autorun'

require_relative '../lib/spotify'

class SpotifyTest < Minitest::Test
  TOKEN_RESPONSE = { 'access_token' => 'a-token', 'expires_in' => 3600 }.freeze

  def setup
    @gets = []
    @posts = []
    @responses = {}
    @token_response = TOKEN_RESPONSE
    stub_http
  end

  def teardown
    %i[get post_form].each do |verb|
      HttpClient.singleton_class.send(:remove_method, verb)
      HttpClient.singleton_class.send(:alias_method, verb, :"#{verb}_without_stub")
      HttpClient.singleton_class.send(:remove_method, :"#{verb}_without_stub")
    end
  end

  def stub_http
    test = self
    HttpClient.singleton_class.send(:alias_method, :get_without_stub, :get)
    HttpClient.singleton_class.send(:alias_method, :post_form_without_stub, :post_form)
    HttpClient.singleton_class.send(:define_method, :get) { |url, **options| test.respond(url, options) }
    HttpClient.singleton_class.send(:define_method, :post_form) { |url, **options| test.respond_to_post(url, options) }
  end

  def respond(url, options)
    @gets << [url, options[:headers]]
    body = @responses[url]
    body && HttpClient::Response.new(status: 200, headers: {}, body: JSON.dump(body), url: url)
  end

  def respond_to_post(url, options)
    @posts << [url, options[:form], options[:headers]]
    return nil unless @token_response

    HttpClient::Response.new(status: 200, headers: {}, body: JSON.dump(@token_response), url: url)
  end

  def serve(path, body) = @responses["#{Spotify::API}/#{path}"] = body

  def client = Spotify::Client.new(id: 'an-id', secret: 'a-secret')

  def episode(id, name, show: 'A Show')
    {
      'id' => id, 'name' => name, 'release_date' => '2024-01-04', 'duration_ms' => 2_952_000,
      'external_urls' => { 'spotify' => "https://open.spotify.com/episode/#{id}" },
      'images' => [{ 'url' => 'https://i.scdn.co/image/big' }],
      'show' => { 'name' => show }
    }
  end

  # --- credentials --------------------------------------------------------

  def test_reads_the_credentials_from_the_environment
    refute Spotify.configured?({})
    refute Spotify.configured?({ 'SPOTIFY_CLIENT_ID' => 'an-id' })
    assert Spotify.configured?({ 'SPOTIFY_CLIENT_ID' => 'an-id', 'SPOTIFY_CLIENT_SECRET' => 'a-secret' })
  end

  def test_asks_for_a_token_once_and_sends_it_as_a_bearer
    serve('shows/abc?market=US', { 'name' => 'A Show' })
    serve('shows/abc/episodes?market=US&limit=50', { 'items' => [episode('e1', 'An episode')], 'next' => nil })

    client.show_episodes('abc')

    assert_equal 1, @posts.size
    url, form, headers = @posts.first
    assert_equal Spotify::TOKEN_URL, url
    assert_equal({ 'grant_type' => 'client_credentials' }, form)
    assert_equal "Basic #{['an-id:a-secret'].pack('m0')}", headers['Authorization']
    assert(@gets.all? { |_, sent| sent['Authorization'] == 'Bearer a-token' })
  end

  def test_refused_credentials_read_as_an_empty_catalogue
    @token_response = nil

    assert_empty client.show_episodes('abc')
    refute client.usable?
  end

  # --- reading the catalogue ----------------------------------------------

  # A hit says nothing about where it was published: search strips the show off
  # every episode, and only reading one back whole puts it there.
  def test_a_search_hit_carries_no_show_until_it_is_read_back
    serve("search?q=david+deutsch&type=episode&market=US&limit=#{Spotify::SEARCH_PAGE}",
          { 'episodes' => { 'items' => [{ 'id' => 'e1', 'name' => 'On explanation' }], 'next' => nil } })
    serve('episodes/e1?market=US', episode('e1', 'On explanation', show: 'A Show'))

    hit = client.search_episodes('david deutsch').first

    refute hit.key?('show')
    assert_equal 'A Show', client.episode('e1').dig('show', 'name')
  end

  # Ten is what episode search allows; anything above it is a 400.
  def test_a_search_is_read_ten_at_a_time_to_the_end_of_its_pages
    serve("search?q=david+deutsch&type=episode&market=US&limit=#{Spotify::SEARCH_PAGE}",
          { 'episodes' => { 'items' => [{ 'id' => 'e1', 'name' => 'One' }],
                            'next' => "#{Spotify::API}/search?offset=10" } })
    serve('search?offset=10', { 'episodes' => { 'items' => [{ 'id' => 'e2', 'name' => 'Two' }], 'next' => nil } })

    assert_equal 10, Spotify::SEARCH_PAGE
    assert_equal %w[One Two], client.search_episodes('david deutsch').map { |e| e['name'] }
  end

  def test_a_show_is_read_to_the_end_of_its_pages
    serve('shows/abc?market=US', { 'name' => 'A Show' })
    serve('shows/abc/episodes?market=US&limit=50',
          { 'items' => [episode('e1', 'One')], 'next' => "#{Spotify::API}/shows/abc/episodes?offset=50" })
    serve('shows/abc/episodes?offset=50', { 'items' => [episode('e2', 'Two')], 'next' => nil })

    assert_equal %w[One Two], client.show_episodes('abc').map { |e| e['name'] }
  end

  def test_every_episode_carries_the_show_it_came_from
    serve('shows/abc?market=US', { 'name' => 'The Show Itself' })
    serve('shows/abc/episodes?market=US&limit=50',
          { 'items' => [{ 'id' => 'e1', 'name' => 'One' }], 'next' => nil })

    assert_equal 'The Show Itself', client.show_episodes('abc').first.dig('show', 'name')
  end

  def test_reads_a_show_id_out_of_a_listed_url
    assert_equal '5xD9XCKiagoraGYvL0UHrT', Spotify.show_id('https://open.spotify.com/show/5xD9XCKiagoraGYvL0UHrT')
    assert_nil Spotify.show_id('https://open.spotify.com/episode/7kTe0ZNS70Pk7ERGPSrBoW')
    assert_nil Spotify.show_id(nil)
  end
end
