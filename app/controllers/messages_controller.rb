class MessagesController < ApplicationController
  include ActiveStorage::SetCurrent, RoomScoped

  before_action :set_room, except: :create
  before_action :set_message, only: %i[ show edit update destroy ]
  before_action :ensure_can_administer, only: %i[ edit update destroy ]

  layout false, only: :index

  def index
    @messages = find_paged_messages

    if @messages.any?
      fresh_when @messages
    else
      head :no_content
    end
  end

  def create
    set_room
    Rails.logger.info "------------------------------------------- MessagesController#create called -------------------------------------------"
    begin
      payload_log = message_params.except(:attachment)
      if message_params[:attachment]
        att = message_params[:attachment]
        att_info = { filename: (att.respond_to?(:original_filename) ? att.original_filename : nil), content_type: (att.respond_to?(:content_type) ? att.content_type : nil), size: (att.respond_to?(:size) ? att.size : nil) }
        Rails.logger.info "------------------------------------------- MessagesController#create payload received: #{payload_log.inspect}, attachment: #{att_info.inspect} -------------------------------------------"
      else
        Rails.logger.info "------------------------------------------- MessagesController#create payload received: #{payload_log.inspect} -------------------------------------------"
      end
    rescue => e
      Rails.logger.error "------------------------------------------- MessagesController#create payload log error: #{e.class} #{e.message} -------------------------------------------"
    end
    @message = @room.messages.create_with_attachment!(message_params)

    @message.broadcast_create
    deliver_webhooks_to_bots
    Rails.logger.info "------------------------------------------- MessagesController#create finished -------------------------------------------"
  rescue ActiveRecord::RecordNotFound
    Rails.logger.error "------------------------------------------- MessagesController#create room not found -------------------------------------------"
    render action: :room_not_found
  end

  def show
  end

  def edit
  end

  def update
    @message.update!(message_params)

    @message.broadcast_replace_to @room, :messages, target: [ @message, :presentation ], partial: "messages/presentation", attributes: { maintain_scroll: true }
    redirect_to room_message_url(@room, @message)
  end

  def destroy
    @message.destroy
    @message.broadcast_remove_to @room, :messages
  end

  private

  def set_message
    @message = @room.messages.find(params[:id])
  end

  def ensure_can_administer
    head :forbidden unless Current.user.can_administer?(@message)
  end

  def find_paged_messages
    case
    when params[:before].present?
      @room.messages.with_creator.page_before(@room.messages.find(params[:before]))
    when params[:after].present?
      @room.messages.with_creator.page_after(@room.messages.find(params[:after]))
    else
      @room.messages.with_creator.last_page
    end
  end

  def message_params
    params.require(:message).permit(:body, :attachment, :client_message_id)
  end

  # --- Updated webhook delivery ---
  def deliver_webhooks_to_bots
    bots_eligible_for_webhook.excluding(@message.creator).each do |bot|
      payload = build_webhook_payload(@message)
      bot.deliver_webhook_later(payload)
    end
  end

  def build_webhook_payload(message)
    {
      user: {
        id: message.creator.id,
        name: message.creator.name
      },
      room: {
        id: message.room.id,
        name: message.room.name,
        path: "/rooms/#{message.room.id}/#{message.room.messages_path}"
      },
      message: {
        id: message.id,
        body: message.body,
        attachment_count: message.attachment.attached? ? 1 : 0,
        attachments: message.attachment.attached? ? [
          {
            filename: message.attachment.filename.to_s,
            content_type: message.attachment.content_type,
            byte_size: message.attachment.byte_size,
            base64: Base64.strict_encode64(message.attachment.download)
          }
        ] : []
      }
    }
  end

  def bots_eligible_for_webhook
    @room.direct? ? @room.users.active_bots : @message.mentionees.active_bots
end
end