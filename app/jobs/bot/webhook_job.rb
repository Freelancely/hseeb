class Bot::WebhookJob < ApplicationJob
  queue_as :default

  def perform(user, message)
    Rails.logger.info "------------------------------Bot::WebhookJob perform called------------------------------"
    user.deliver_webhook(message)
    Rails.logger.info "------------------------------Bot::WebhookJob perform finished------------------------------"
  end
end
