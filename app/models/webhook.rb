require "net/http"
require "uri"

class Webhook < ApplicationRecord
  ENDPOINT_TIMEOUT = 7.seconds

  belongs_to :user

  def deliver(message)
    Rails.logger.info "------------------------------------------- Webhook#deliver called -------------------------------------------"
    payload_json = payload(message)
    Rails.logger.info "------------------------------------------- Webhook#deliver payload sent: #{payload_json} -------------------------------------------"
    post(payload_json).tap do |response|
      Rails.logger.info "------------------------------------------- Webhook#deliver response: #{response.inspect} -------------------------------------------"
      begin
        Rails.logger.info "------------------------------------------- Webhook#deliver payload received: #{response.body} -------------------------------------------"
      rescue => e
        Rails.logger.error "------------------------------------------- Webhook#deliver response log error: #{e.class} #{e.message} -------------------------------------------"
      end
      if text = extract_text_from(response)
        receive_text_reply_to(message.room, text: text)
      elsif attachment = extract_attachment_from(response)
        receive_attachment_reply_to(message.room, attachment: attachment)
      end
    end
  rescue Net::OpenTimeout, Net::ReadTimeout
    Rails.logger.error "------------------------------------------- Webhook#deliver timeout -------------------------------------------"
    receive_text_reply_to message.room, text: "Failed to respond within #{ENDPOINT_TIMEOUT} seconds"
  rescue => e
    Rails.logger.error "------------------------------------------- Webhook#deliver error: #{e.class} #{e.message} -------------------------------------------"
  end

  private
    def post(payload)
      http.request \
        Net::HTTP::Post.new(uri, "Content-Type" => "application/json").tap { |request| request.body = payload }
    end

    def http
      Net::HTTP.new(uri.host, uri.port).tap do |http|
        http.use_ssl = (uri.scheme == "https")
        http.open_timeout = ENDPOINT_TIMEOUT
        http.read_timeout = ENDPOINT_TIMEOUT
      end
    end

    def uri
      @uri ||= URI(url)
    end

    def payload(message)
      message_data = {
        id: message.id,
        body: { html: message.body.body, plain: without_recipient_mentions(message.plain_text_body),static:"yellow" },
        path: message_path(message),
        content_type: message.content_type
      }

      # Include attachment information if message has an attachment
      if message.attachment.attached?
        message_data[:attachment] = {
          filename: message.attachment.filename.to_s,
          content_type: message.attachment.content_type,
          url: attachment_url(message.attachment),
          size: message.attachment.byte_size,
          metadata: message.attachment.metadata,
          base64: Base64.strict_encode64(message.attachment.download)
        }
        Rails.logger.info "------------------------------------------- Webhook#deliver attachment included: #{message_data[:attachment].inspect} -------------------------------------------"
      else
        Rails.logger.info "------------------------------------------- Webhook#deliver no attachment found -------------------------------------------"
      end

      payload_hash = {
        user:    { id: message.creator.id, name: message.creator.name },
        room:    { id: message.room.id, name: message.room.name, path: room_bot_messages_path(message) },
        message: message_data
      }
      Rails.logger.info "------------------------------------------- Webhook#deliver payload: #{payload_hash.inspect} -------------------------------------------"
      payload_hash.to_json
    end

    def message_path(message)
      Rails.application.routes.url_helpers.room_at_message_path(message.room, message)
    end

    def room_bot_messages_path(message)
      Rails.application.routes.url_helpers.room_bot_messages_path(message.room, user.bot_key)
    end

    def attachment_url(attachment)
      Rails.application.routes.url_helpers.rails_blob_url(attachment)
    end

    def extract_text_from(response)
      response.body.dup.force_encoding("UTF-8") if response.code == "200" && response.content_type.in?(%w[ text/html text/plain ])
    end

    def receive_text_reply_to(room, text:)
      room.messages.create!(body: text, creator: user).broadcast_create
    end

    def extract_attachment_from(response)
      if response.content_type && mime_type = Mime::Type.lookup(response.content_type)
        ActiveStorage::Blob.create_and_upload! \
          io: StringIO.new(response.body), filename: "attachment.#{mime_type.symbol}", content_type: mime_type.to_s
      end
    end

    def receive_attachment_reply_to(room, attachment:)
      room.messages.create_with_attachment!(attachment: attachment, creator: user).broadcast_create
    end

    def without_recipient_mentions(body)
      body \
        .gsub(user.attachable_plain_text_representation(nil), "") # Remove mentions of the recipient user
        .gsub(/\A\p{Space}+|\p{Space}+\z/, "") # Remove leading and trailing whitespace uncluding unicode spaces
    end
end
