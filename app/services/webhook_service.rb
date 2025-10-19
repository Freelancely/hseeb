require "net/http"
require "uri"
require "json"

class WebhookService
  def initialize(payload)
    @payload = payload
  end

  def call
    Rails.logger.info "------------------------------------------- WebhookService call started -------------------------------------------"
    Rails.logger.info "------------------------------------------- Payload sent: #{@payload.inspect} -------------------------------------------"
    
    uri = URI.parse(ENV.fetch("N8N_WEBHOOK_URL"))
    Rails.logger.info "------------------------------------------- Hitting Webhook URL: #{uri} -------------------------------------------"
    
    request = Net::HTTP::Post.new(uri, "Content-Type" => "application/json")
    request.body = @payload.to_json
    
    response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == "https") do |http|
      http.open_timeout = 30
      http.read_timeout = 30
      http.request(request)
    end
    
    Rails.logger.info "------------------------------------------- Webhook response status: #{response.code} headers: #{response.to_hash.inspect} -------------------------------------------"
    Rails.logger.info "------------------------------------------- Webhook payload received: #{response.body} -------------------------------------------"
    response
  rescue Net::ReadTimeout => e
    Rails.logger.error "------------------------------------------- Webhook failed: #{e.class} #{e.message} -------------------------------------------"
    raise
  rescue StandardError => e
    Rails.logger.error "------------------------------------------- Webhook failed: #{e.class} #{e.message} -------------------------------------------"
    raise
  ensure
    Rails.logger.info "------------------------------------------- WebhookService call finished -------------------------------------------"
  end
end