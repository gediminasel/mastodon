# frozen_string_literal: true

class FetchResourceService < BaseService
  include JsonLdHelper

  ACCEPT_HEADER = 'application/activity+json, application/ld+json; profile="https://www.w3.org/ns/activitystreams", text/html;q=0.1'

  attr_reader :response_code

  def call(url, possible_cache = nil)
    return if url.blank?
    data, e = try_process(url)
    return data unless data.nil?
    return if possible_cache.nil?
    data = get_from_cache(url_in_cache(possible_cache, url))
    raise e if data.nil? && !e.nil?
    data
  end

  private

  def get_from_cache(cache_url)
    data = process(cache_url, true, true)
    return if data.nil?
    json = JSON.parse data[1][:prefetched_body]
    creator = ActivityPub::LinkedDataSignature.new(json).verify_account!
    return if creator.nil?
    return data if creator.uri == json['actor'] || creator.uri == json['object']['attributedTo']
    nil
  end

  def try_process(url)
    [process(url), nil]
  rescue => e
    Rails.logger.debug "Error fetching resource #{@url}: #{e}"
    [nil, e]
  end

  def url_in_cache(possible_cache, url)
    return if possible_cache.nil?
    cache_uri = Addressable::URI.parse(possible_cache)
    return if cache_uri.nil? || cache_uri.normalized_site.nil?
    "#{cache_uri.normalized_site}/get_from_cache/#{CGI.escape url}"
  end

  def process(url, terminal = false, allow_create = false)
    return nil if url.nil?
    @url = url

    perform_request { |response| process_response(response, terminal, allow_create) }
  end

  def perform_request(&block)
    Request.new(:get, @url).tap do |request|
      request.add_headers('Accept' => ACCEPT_HEADER)

      # In a real setting we want to sign all outgoing requests,
      # in case the remote server has secure mode enabled and requires
      # authentication on all resources. However, during development,
      # sending request signatures with an inaccessible host is useless
      # and prevents even public resources from being fetched, so
      # don't do it

      request.on_behalf_of(Account.representative) unless Rails.env.development?
    end.perform(&block)
  end

  def process_response(response, terminal = false, allow_create = false)
    @response_code = response.code
    return nil if response.code != 200

    if ['application/activity+json', 'application/ld+json'].include?(response.mime_type)
      body = response.body_with_limit
      json = body_to_json(body)

      [json['id'], { prefetched_body: body, id: true }] if supported_context?(json) && (expected_type?(json) || (allow_create && json['type'] == 'Create'))
    elsif !terminal
      link_header = response['Link'] && parse_link_header(response)

      if link_header&.find_link(%w(rel alternate))
        process_link_headers(link_header)
      elsif response.mime_type == 'text/html'
        process_html(response)
      end
    end
  end

  def expected_type?(json)
    return true if equals_or_includes_any?(json['type'], ActivityPub::FetchRemoteAccountService::SUPPORTED_TYPES)
    equals_or_includes_any?(json['type'], ActivityPub::Activity::Create::SUPPORTED_TYPES + ActivityPub::Activity::Create::CONVERTED_TYPES)
  end

  def process_html(response)
    page      = Nokogiri::HTML(response.body_with_limit)
    json_link = page.xpath('//link[@rel="alternate"]').find { |link| ['application/activity+json', 'application/ld+json; profile="https://www.w3.org/ns/activitystreams"'].include?(link['type']) }

    process(json_link['href'], terminal: true) unless json_link.nil?
  end

  def process_link_headers(link_header)
    json_link = link_header.find_link(%w(rel alternate), %w(type application/activity+json)) || link_header.find_link(%w(rel alternate), ['type', 'application/ld+json; profile="https://www.w3.org/ns/activitystreams"'])

    process(json_link.href, terminal: true) unless json_link.nil?
  end

  def parse_link_header(response)
    LinkHeader.parse(response['Link'].is_a?(Array) ? response['Link'].first : response['Link'])
  end
end
