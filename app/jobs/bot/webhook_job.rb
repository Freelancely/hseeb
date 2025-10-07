class Bot::WebhookJob < ApplicationJob
  queue_as :default
  retry_on Net::ReadTimeout, attempts: 3, wait: 10.seconds

  def perform(user, message)
    # Convert message to Message object if it's a Hash (Resque serialization)
    message = message.is_a?(Hash) ? Message.find_by(id: message[:id] || message['id']) : message

    # Skip if message is invalid
    unless message
      Rails.logger.error "Invalid message for Bot::WebhookJob: #{message.inspect}"
      return
    end

    plain_body = message.body.to_plain_text.strip
    has_attachment = message.attachment.attached?

    # Skip mention-only messages (without attachments)
    # This handles the dual-message behavior from Campfire's composer:
    # - When user sends "@mention" + file, it creates TWO messages:
    #   1. File upload message (attachment only, empty body) -> PROCESS THIS
    #   2. Text message (@mention only, no attachment) -> SKIP THIS
    # Matches: "@word", "@word ", "@word  ", "@word filename.png", etc.
    if !has_attachment && plain_body.match?(/^@\w+(\s+\w+\.(png|jpg|jpeg|pdf|docx))?\s*$/i)
      Rails.logger.info "Skipping webhook for mention-only message #{message.id}: '#{plain_body}'"
      return
    end

    # For messages with attachments, clean the body to remove filename echoes
    # This prevents attachment messages from also triggering text-based workflows
    if has_attachment
      original_body = plain_body
      filename = message.attachment.filename.to_s
      
      # Remove the filename from body (case-insensitive, handle spaces)
      plain_body = plain_body.gsub(/\s*#{Regexp.escape(filename)}\s*/i, '').strip
      
      # If body becomes just a mention after cleaning, empty it for attachment-only workflow
      if plain_body.match?(/^@\w+$/i)
        Rails.logger.info "Attachment message #{message.id}: setting body to empty for attachment-only workflow. Original: '#{original_body}'"
        plain_body = ""
      elsif original_body != plain_body
        Rails.logger.info "Attachment message #{message.id}: cleaned body. Original: '#{original_body}' -> '#{plain_body}'"
      end
    end

    Rails.logger.info "------------------------------------------- Bot::WebhookJob perform called for message #{message.id}: body='#{plain_body}', attachment: #{has_attachment} -------------------------------------------"
    
    WebhookService.new(payload(user, message, plain_body)).call
    
    Rails.logger.info "------------------------------------------- Bot::WebhookJob perform finished for message #{message.id} -------------------------------------------"
  end

  private

  def payload(user, message, cleaned_body = nil)
    # Use cleaned body if provided, otherwise use original
    body_text = cleaned_body.nil? ? message.plain_text_body : cleaned_body
    has_attachment = message.attachment.attached?
    
    # Base message structure
    message_data = {
      id: message.id,
      body: body_text,
      static: "ashish",
      path: Rails.application.routes.url_helpers.room_at_message_path(message.room, message)
    }
    
    # Add attachment data if exists
    if has_attachment
      message_data[:attachment] = {
        filename: message.attachment.filename.to_s,
        content_type: message.attachment.content_type,
        size: message.attachment.byte_size,
        url: attachment_url(message.attachment)
      }
    end

    # Build full payload with n8n-compatible structure
    {
      user: {
        id: user.id,
        name: user.name
      },
      room: {
        id: message.room.id,
        name: message.room.name,
        path: Rails.application.routes.url_helpers.room_at_message_path(message.room, message)
      },
      message: message_data,
      # Add top-level flags for n8n workflow compatibility
      hasAttachment: has_attachment,
      attachmentUrl: has_attachment ? attachment_url(message.attachment) : nil,
      roomId: message.room.id.to_s,
      userToken: "3-6s7VBBRD0mi9" # You might want to make this dynamic or environment-based
    }
  end

  def attachment_url(attachment)
    return nil unless attachment.attached?
    
    if Rails.application.config.active_storage.service == :local
      Rails.application.routes.url_helpers.rails_blob_url(
        attachment,
        host: ENV.fetch("HOST_URL", "http://localhost:3000")
      )
    else
      attachment.service_url(expires_in: 1.hour, disposition: "inline")
    end
  end
end