class Message < ApplicationRecord
  include Attachment, Broadcasts, Mentionee, Pagination, Searchable

  belongs_to :room, touch: true
  belongs_to :creator, class_name: "User", default: -> { Current.user }

  has_many :boosts, dependent: :destroy

  has_rich_text :body
  has_one_attached :attachment

  before_create -> { self.client_message_id ||= SecureRandom.uuid }
  after_create_commit -> { room.receive(self) }
  after_create_commit :deliver_webhooks_to_bots_after_commit

  # Webhooks are dispatched from the controller after create to support
  # both text-only and attachment messages without duplication.

  scope :ordered, -> { order(:created_at) }
  scope :with_creator, -> { preload(creator: :avatar_attachment) }
  scope :with_attachment_details, -> {
    with_rich_text_body_and_embeds
    with_attached_attachment.includes(attachment_blob: :variant_records)
  }
  scope :with_boosts, -> { includes(boosts: :booster) }

  def plain_text_body
    body.to_plain_text.presence || attachment&.filename&.to_s || ""
  end

  def to_key
    [client_message_id]
  end

  def content_type
    case
    when attachment? then "attachment"
    when sound.present? then "sound"
    else "text"
    end.inquiry
  end

  def sound
    plain_text_body.match(/\A\/play (?<name>\w+)\z/) do |match|
      Sound.find_by_name match[:name]
    end
  end

  private

  def deliver_webhooks_to_bots_after_commit
    bots = eligible_bots_for_webhook
    bots.excluding(creator).each do |bot|
      bot.deliver_webhook_later(self)
    end
  end

  def eligible_bots_for_webhook
    return room.users.active_bots if room.direct?

    # Start with bots explicitly mentioned in this message
    bots = mentionees.active_bots

    # If this message only contains an attachment and no mentions, try to inherit
    # mentions from the sender's immediately previous message in this room.
    if bots.blank? && attachment.attached?
      previous_message = room.messages
        .where(creator: creator)
        .where("created_at <= ?", created_at)
        .where.not(id: id)
        .order(created_at: :desc)
        .limit(1)
        .first

      bots = previous_message&.mentionees&.active_bots || User.none
    end

    bots
  end

  # Removed attachment-only enqueue; webhooks are sent after commit regardless of type.
end
