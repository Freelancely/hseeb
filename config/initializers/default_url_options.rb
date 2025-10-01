

# config/initializers/default_url_options.rb
Rails.application.routes.default_url_options[:host] = ENV.fetch("HOST_URL", "https://unpartaking-unvengeful-tama.ngrok-free.dev")