require "net/http"
require "uri"
require "json"

class WebhookService
  def initialize(payload)
    @payload = payload
  end

  def call
    Rails.logger.info "------------------------------WebhookService call started------------------------------"
    Rails.logger.info "Payload: #{@payload.inspect}"
    uri = URI.parse(ENV.fetch("WEBHOOK_URL"))
    request = Net::HTTP::Post.new(uri)
    request.content_type = "application/json"
    request.body = @payload.to_json

    response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == "https") do |http|
      http.open_timeout = 7
      http.read_timeout = 7
      http.request(request)
    end

    Rails.logger.info "------------------------------Webhook response: #{response.body}------------------------------"
    Rails.logger.info "------------------------------WebhookService call finished------------------------------"
  rescue StandardError => e
    Rails.logger.error "------------------------------Webhook failed: #{e.message}------------------------------"
  end
end
