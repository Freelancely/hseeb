module Message::Attachment
  extend ActiveSupport::Concern

  THUMBNAIL_MAX_WIDTH = 1200
  THUMBNAIL_MAX_HEIGHT = 800

  included do
    has_one_attached :attachment
  end

  module ClassMethods
    def create_with_attachment!(attributes)
      create!(attributes).tap(&:process_attachment)
    end
  end

  def attachment?
    attachment.attached?
  end

  def process_attachment
    ensure_attachment_analyzed
    process_attachment_thumbnail
  end

  def thumbnail_variant
    return unless attachment.attached?
    if attachment.video?
      attachment.preview(format: :webp, resize_to_limit: [THUMBNAIL_MAX_WIDTH, THUMBNAIL_MAX_HEIGHT])
    elsif attachment.image?
      attachment.variant(resize_to_limit: [THUMBNAIL_MAX_WIDTH, THUMBNAIL_MAX_HEIGHT])
    else
      nil
    end
  end

  private

  def ensure_attachment_analyzed
    attachment&.analyze
  end

  def process_attachment_thumbnail
    variant = thumbnail_variant
    variant&.processed
  rescue => e
    Rails.logger.error("[Message::Attachment] Failed to process thumbnail: #{e.message}")
    nil
  end
end