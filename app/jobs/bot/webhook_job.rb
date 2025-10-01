class Bot::WebhookJob < ApplicationJob
  queue_as :default

  def perform(user, message)
    Rails.logger.info "------------------------------Bot::WebhookJob perform called------------------------------"
    WebhookService.new(payload(user, message)).call
    Rails.logger.info "------------------------------Bot::WebhookJob perform finished------------------------------"
  end

  private

  def payload(user, message)
    attachment = message.attachment

    attachment_data = if attachment.attached?
      {
        filename: attachment.filename.to_s,
        content_type: attachment.content_type,
        size: attachment.byte_size,
        url: attachment_url(attachment)
      }
    else
      nil
    end

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
      message: {
        id: message.id,
        body: message.plain_text_body,
        static: "ashish",
        attachment: attachment_data.to_json, # ✅ only include attachment info
        path: Rails.application.routes.url_helpers.room_at_message_path(message.room, message)
      }
    }
  end

  # ✅ Returns a publicly accessible URL for the attachment
  def attachment_url(attachment)
    if Rails.application.config.active_storage.service == :local
      Rails.application.routes.url_helpers.rails_blob_url(
        attachment,
        host: ENV.fetch("HOST_URL")
      )
    else
      # For cloud storage like S3/GCS: signed URL
      attachment.service_url(expires_in: 1.hour, disposition: "inline")
    end
  end
end
