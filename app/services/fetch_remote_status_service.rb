# frozen_string_literal: true

class FetchRemoteStatusService < BaseService
  def call(url, prefetched_body = nil, possible_cache = nil)
    if prefetched_body.nil?
      resource_url, resource_options = FetchResourceService.new.call(url, possible_cache)
    else
      resource_url     = url
      resource_options = { prefetched_body: prefetched_body }
    end

    ActivityPub::FetchRemoteStatusService.new.call(resource_url, **resource_options) unless resource_url.nil?
  end
end
