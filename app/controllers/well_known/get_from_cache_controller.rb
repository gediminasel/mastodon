# frozen_string_literal: true

module WellKnown
  class GetFromCacheController < ActionController::Base
    include RoutingHelper

    rescue_from ActiveRecord::RecordNotFound, with: :not_found
    rescue_from ActionController::ParameterMissing, WebfingerResource::InvalidRequest, with: :bad_request

    def get
      expires_in 3.days, public: false
      uri = params[:uri]
      return not_found if uri.nil?
      status = Status.find_by(uri: uri)
      return not_found if status.nil? || status.signed_json.nil? || !status.deleted_at.nil?
      render json: status.signed_json, content_type: 'application/activity+json'
    end

    private

    def bad_request
      expires_in(3.minutes, public: true)
      head 400
    end

    def not_found
      expires_in(3.minutes, public: true)
      head 404
    end
  end
end
