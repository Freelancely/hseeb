class Messages::ByBotsController < MessagesController
  allow_bot_access only: :create

  def create
    begin
      if params[:attachment]
        att = params[:attachment]
        att_info = { filename: (att.respond_to?(:original_filename) ? att.original_filename : nil), content_type: (att.respond_to?(:content_type) ? att.content_type : nil), size: (att.respond_to?(:size) ? att.size : nil) }
        Rails.logger.info "------------------------------------------- Messages::ByBotsController#create payload received (attachment): #{att_info.inspect} -------------------------------------------"
      else
        body = request.body.read
        Rails.logger.info "------------------------------------------- Messages::ByBotsController#create payload received (text): #{body.inspect} -------------------------------------------"
        request.body.rewind
      end
    rescue => e
      Rails.logger.error "------------------------------------------- Messages::ByBotsController#create payload log error: #{e.class} #{e.message} -------------------------------------------"
    end
    super
    head :created, location: message_url(@message)
  end

  private
    def message_params
      if params[:attachment]
        params.permit(:attachment)
      else
        reading(request.body) { |body| { body: body } }
      end
    end

    def reading(io)
      io.rewind
      yield io.read.force_encoding("UTF-8")
    ensure
      io.rewind
    end
end
