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
    
    uri = URI.parse(ENV.fetch("WEBHOOK_URL"))
    Rails.logger.info "------------------------------------------- Hitting Webhook URL: #{uri} -------------------------------------------"  # ✅ Print URL
  
    request = Net::HTTP::Post.new(uri)
    request.content_type = "application/json"
    request.body = @payload.to_json
  
    response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == "https") do |http|
      http.open_timeout = 7
      http.read_timeout = 7
      http.request(request)
    end
  
    begin
      Rails.logger.info "------------------------------------------- Webhook response status: #{response.code} headers: #{response.to_hash.inspect} -------------------------------------------"
      Rails.logger.info "------------------------------------------- Webhook payload received: #{response.body} -------------------------------------------"
    rescue => e
      Rails.logger.error "------------------------------------------- Webhook response log error: #{e.class} #{e.message} -------------------------------------------"
    end
    Rails.logger.info "------------------------------------------- WebhookService call finished -------------------------------------------"
  rescue StandardError => e
    Rails.logger.error "------------------------------------------- Webhook failed: #{e.message} -------------------------------------------"
  end
end  