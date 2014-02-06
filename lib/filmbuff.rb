require 'filmbuff/title'
require 'excon'
require 'json'

# Interacts with IMDb and is used to look up titles
class FilmBuff
  class NotFound < StandardError; end

  USER_AGENTS = [
    "Mozilla/5.0 (Windows NT 6.1; Win64; x64; rv:25.0) Gecko/20100101 Firefox/25.0",
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10.6; rv:25.0) Gecko/20100101 Firefox/25.0",
    "Mozilla/5.0 (X11; Ubuntu; Linux x86_64; rv:24.0) Gecko/20100101 Firefox/24.0",
    "Mozilla/5.0 (Windows NT 6.0; WOW64; rv:24.0) Gecko/20100101 Firefox/24.0",
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10.8; rv:24.0) Gecko/20100101 Firefox/24.0"
  ].freeze

  # @return [String] The locale currently used by the IMDb instance
  attr_accessor :locale

  # Create a new FilmBuff instance
  #
  # @param [String] locale
  #   The locale to search with. The FilmBuff instance will also return
  #   results in the language matching the given locale. Defaults to `en_US`
  #
  # @param [Boolean] ssl
  #   Whether or not to use SSL when searching by IMDb ID (IMDb does not
  #   currently support SSL when searching by title). Defaults to `true`
  #
  # @param [Object, Hash, nil] cache
  #   Whatever Faraday-http-cache should use for caching. Can be both an
  #    object such as `Rails.cache`, a hash like
  #   `:mem_cache_store, 'localhost:11211'`, or `nil`, meaning no caching.
  #   Defaults to `nil`
  #
  # @param [Object] logger
  #   An instance of a logger object. Defaults to `nil` and no logging
  def initialize(locale = 'en_US', ssl: true, cache: nil, logger: nil)
    @locale = locale
    @protocol = ssl ? 'https' : 'http'
    @cache = cache
    @logger = logger
  end

  private

  def connection
    @connection ||= Excon.new("#{@protocol}://app.imdb.com")
  end

  def build_hash(type, values)
    {
      type: type,
      imdb_id: values['id'],
      title: values['title'],
      release_year: values['description'][/\A\d{4}/]
    }
  end

  def headers
    @headers ||= { 'User-Agent' => USER_AGENTS.sample }
  end

  public

  # Looks up the title with the IMDb ID imdb_id and returns a
  # FilmBuff::Title object with information on that title
  #
  # @param [String] imdb_id
  #   The IMDb ID for the title to look up
  #
  # @return [Title]
  #   The FilmBuff::Title object containing information on the title
  #
  # @example Basic usage
  #   movie = imdb_instance.look_up_id('tt0032138')
  def look_up_id(imdb_id)
    response = connection.get(path: '/title/maindetails', query: {
      tconst: imdb_id, locale: @locale
    }, headers: headers)

    unless response.status == 200
      fail NotFound
    else
      Title.new(JSON.parse(response.body)['data'])
    end
  end

  # Searches IMDb for the title provided and returns an array with results
  #
  # @param [String] title The title to search for
  #
  # @param [Integer] limit The maximum number of results to return
  #
  # @param [Array] types The types of matches to search for.
  #   These types will be searched in the provided order. Can be
  #   `title_popular`, `title_exact`, `title_approx`, and `title_substring`
  #
  # @return [Array<Hash>] An array of hashes, each representing a search result
  #
  # @example Basic usage
  #   movie = imdb_instance.search_for_title('The Wizard of Oz')
  #
  # @example Return only 2 results
  #   movie = imdb_instance.search_for_title('The Wizard of Oz', limit: 2)
  #
  # @example Only return results containing the exact title provided
  #   movie = imdb_instance.search_for_title('The Wizard of Oz',
  #                                          types: %w(title_exact))
  def search_for_title(title, limit: nil, types: %w(title_popular
                                                 title_exact
                                                 title_approx
                                                 title_substring))
    response = Excon.get('http://www.imdb.com/xml/find', query: {
      q: title,
      json: '1',
      tt: 'on'
    }, headers: headers)

    output = []
    body = JSON.parse(response.body)
    results = body.select { |key| types.include? key }

    results.each_key do |key|
      body[key].each do |row|
        break unless output.size < limit if limit
        next unless row['id'] && row['title'] && row['description']

        output << build_hash(key, row)
      end
    end

    output
  end
end
