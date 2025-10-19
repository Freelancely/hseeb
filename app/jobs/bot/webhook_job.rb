class Bot::WebhookJob < ApplicationJob
  queue_as :default
  retry_on Net::ReadTimeout, attempts: 3, wait: 10.seconds

  # Bot's message token - messages from this endpoint are bot responses
  BOT_MESSAGE_TOKEN = "4-PuoeOrHbcbh8"

  def perform(user, message)
    # Convert message to Message object if it's a Hash (Resque serialization)
    message = message.is_a?(Hash) ? Message.find_by(id: message[:id] || message['id']) : message

    # Skip if message is invalid
    unless message
      Rails.logger.error "Invalid message for Bot::WebhookJob: #{message.inspect}"
      return
    end

    # **CRITICAL: Skip bot's own messages to prevent infinite loop**
    # Bot messages are posted via the endpoint containing BOT_MESSAGE_TOKEN
    # Check if this message was created by the bot by looking at the creator token
    message_path = Rails.application.routes.url_helpers.room_at_message_path(message.room, message)
    if message_path.include?(BOT_MESSAGE_TOKEN) || is_bot_message?(message)
      Rails.logger.info "Skipping webhook for bot message #{message.id} - preventing infinite loop"
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

  def is_bot_message?(message)
    # Additional checks to identify bot messages:
    # 1. Check if message creator matches bot token pattern
    # 2. Check message content patterns (bot responses usually start with specific phrases)
    body = message.body.to_plain_text.strip
    
    # Bot responses typically start with these patterns
    bot_patterns = [
      # Financial summary patterns
      /^On \w+ \d+, \d{4}, the (company|business)/i,           # "On October 19, 2025, the company..."
      /^We (logged|noted|recorded|registered)/i,                # "We logged revenue..."
      /^KWD \d+ was (recognized|recorded|logged)/i,            # "KWD 300 was recognized..."
      /^The (company|business) (recorded|registered|logged)/i, # "The company recorded..."
      /^An (income|expense) transaction/i,                      # "An income transaction..."
      /^This entry/i,                                           # "This entry shows..."
      /^Revenue of KWD/i,                                       # "Revenue of KWD 500..."
      /^Expense of KWD/i,                                       # "Expense of KWD 200..."
      
      # Transaction confirmation patterns
      /successfully (created|recorded|added|logged)/i,          # "Successfully created invoice..."
      /transaction (has been|was) (processed|completed)/i,      # "Transaction has been processed..."
      /invoice (created|generated|issued)/i,                    # "Invoice created for..."
      /payment (recorded|processed|completed)/i,                # "Payment recorded successfully..."
      
      # Financial report patterns
      /^(Total|Net) (revenue|income|profit|loss)/i,            # "Total revenue for..."
      /^Your (current|financial) (balance|status)/i,           # "Your current balance is..."
      /^Financial (summary|report|overview)/i,                 # "Financial summary for..."
      /P&L (report|summary)/i,                                 # "P&L report shows..."
      
      # Status and confirmation patterns
      /^(Successfully|Transaction|Record) (added|saved|updated)/i, # "Successfully added expense..."
      /has been (saved|recorded|added) to/i,                   # "...has been saved to Xero"
      /^Data (processed|extracted|parsed)/i,                   # "Data processed successfully..."
      
      # Error and validation patterns
      /^(Error|Warning|Failed|Unable)/i,                       # "Error processing transaction..."
      /^Please (provide|check|verify)/i,                       # "Please provide more details..."
      /^Invalid (transaction|amount|data)/i,                   # "Invalid transaction format..."
      
      # Greeting responses (if bot responds to greetings)
      /^Hello! (I'm|Here|Ready)/i,                             # "Hello! I'm your financial assistant..."
      /^(Hi|Hey) there/i,                                      # "Hi there! How can I help..."
      
      # Amount-based patterns
      /^\d+(\.\d{1,3})?\s*(KWD|USD|EUR|GBP)/i,                # "500 KWD received..."
      /^Amount:\s*\d+/i,                                       # "Amount: 300"
      
      # Category-based patterns
      /^Category:\s*(Sales|Marketing|Office|Travel)/i,         # "Category: Sales"
      /classified (under|as|within)/i,                         # "...classified under Sales"
      /categorized (as|under)/i,                               # "...categorized as expense"
      
      # Date-based patterns
      /for the period/i,                                       # "...for the period ending..."
      /as of \d{4}-\d{2}-\d{2}/i,                             # "...as of 2025-10-19"
      
      # Action confirmation patterns
      /^Processed \d+ transaction/i,                           # "Processed 3 transactions..."
      /^Updated (balance|total|summary)/i,                     # "Updated balance reflects..."
      
      # JSON or structured data (sometimes bot might echo structured data)
      /^\{.*"(success|transaction|revenue|expense)".*\}/i,     # JSON response patterns
      
      # Xero-specific patterns
      /^Xero (invoice|bill|payment)/i,                         # "Xero invoice created..."
      /synced (to|with) Xero/i,                                # "...synced to Xero"
      /in your Xero account/i,                                 # "...in your Xero account"
      
      # Attachment processing patterns
      /^(Receipt|Document|File) (processed|analyzed|extracted)/i, # "Receipt processed successfully..."
      /^OCR (extracted|detected|found)/i,                      # "OCR extracted the following..."
      /^Text extracted from/i,                                 # "Text extracted from image..."
      
      # Summary sentence starters
      /^(Overall|In total|Combined)/i,                         # "Overall, you have..."
      /^Your total (income|expenses|profit)/i,                 # "Your total income is..."
      /^As of (today|now|\w+ \d+)/i,                          # "As of today, your balance..."
      
      # Multi-sentence patterns (bot often uses formal language)
      /\. This (entry|transaction|record)/i,                   # Any sentence ending with ". This entry..."
      /significantly (enhances|impacts|affects)/i,             # "...significantly enhances performance"
      /contributes (to|directly to)/i,                         # "...contributes to revenue"
      /supports (business|the company)/i,                      # "...supports business earnings"
    ]
    
    bot_patterns.any? { |pattern| body.match?(pattern) }
  end

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