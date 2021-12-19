# frozen_string_literal: true

class ActivityPub::FetchRemoteKeyService < BaseService
  include JsonLdHelper

  # Returns account that owns the key
  def call(uri, prefetched_body: nil)
    return if uri.blank?

    if prefetched_body.nil?
      t = fetch_resource_with_fallback(uri, false)
      @json = t.json
      @verified_webfinger = !t.fresh
    else
      @json = body_to_json(prefetched_body, compare_id: id ? uri : nil)
      @verified_webfinger = false
    end

    return unless supported_context?(@json) && expected_type?
    return find_account(@json['id'], @json) if person?

    @owner = fetch_resource(owner_uri, true)

    return unless supported_context?(@owner) && confirmed_owner?

    find_account(owner_uri, @owner)
  end

  def find_account(uri, prefetched_body)
    account   = ActivityPub::TagManager.instance.uri_to_resource(uri, Account)
    account ||= ActivityPub::FetchRemoteAccountService.new.call(uri, prefetched_body: prefetched_body, verified_webfinger: @verified_webfinger)
    account
  end

  def expected_type?
    person? || public_key?
  end

  def person?
    equals_or_includes_any?(@json['type'], ActivityPub::FetchRemoteAccountService::SUPPORTED_TYPES)
  end

  def public_key?
    @json['publicKeyPem'].present? && @json['owner'].present?
  end

  def owner_uri
    @owner_uri ||= value_or_id(@json['owner'])
  end

  def confirmed_owner?
    equals_or_includes_any?(@owner['type'], ActivityPub::FetchRemoteAccountService::SUPPORTED_TYPES) && value_or_id(@owner['publicKey']) == @json['id']
  end
end
