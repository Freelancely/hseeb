class Message < ApplicationRecord
  include Attachment, Broadcasts, Mentionee, Pagination, Searchable

  belongs_to :room, touch: true
  belongs_to :creator, class_name: "User", default: -> { Current.user }

  has_many :boosts, dependent: :destroy

  has_rich_text :body
  has_one_attached :attachment

  before_create -> { self.client_message_id ||= SecureRandom.uuid }
  after_create_commit -> { room.receive(self) }

  # Trigger webhook after attachment is processed
  after_commit :enqueue_webhook_after_attachment, on: :create

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

  # ✅ Enqueue webhook after attachment is analyzed
  def enqueue_webhook_after_attachment
    return unless attachment.attached?

    # Analyze the attachment if not already done
    attachment.analyze unless attachment.analyzed?

    # Only enqueue the webhook if analysis is complete
    if attachment.analyzed?
      Bot::WebhookJob.perform_later(creator, self)
    else
      # Retry after a short delay if analysis not finished yet
      Bot::WebhookJob.set(wait: 5.seconds).perform_later(creator, self)
    end
  end
end
