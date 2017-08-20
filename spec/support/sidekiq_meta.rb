# frozen_string_literal: true

# rubocop:disable BlockLength
RSpec.configure do |config|
  config.before(:each) do |example|
    SidekiqUniqueJobs.configure do |conn|
      conn.redis_test_mode = :redis
    end

    if (redis_db = example.metadata.fetch(:redis_db) { 0 })
      redis_url = "redis://localhost/#{redis_db}"
      redis_options = { url: redis_url }
      redis = Sidekiq::RedisConnection.create(redis_options)

      Sidekiq.configure_client do |sidekiq_config|
        sidekiq_config.redis = redis_options
      end
      SidekiqUniqueJobs.configure do |unique_config|
        unique_config.redis_test_mode = :redis
      end

      Sidekiq.redis = redis
      Sidekiq.redis(&:flushdb)
      Sidekiq::Worker.clear_all
      Sidekiq::Queues.clear_all

      if Sidekiq::Testing.respond_to?(:server_middleware)
        Sidekiq::Testing.server_middleware do |chain|
          chain.add SidekiqUniqueJobs::Server::Middleware
        end
      end
      enable_delay = defined?(Sidekiq::Extensions) && Sidekiq::Extensions.respond_to?(:enable_delay!)
      Sidekiq::Extensions.enable_delay! if enable_delay
    end

    if (sidekiq = example.metadata[:sidekiq])
      sidekiq = :fake if sidekiq == true
      Sidekiq::Testing.send("#{sidekiq}!")
    end

    if (sidekiq_ver = example.metadata[:sidekiq_ver])
      VERSION_REGEX.match(sidekiq_ver.to_s) do |match|
        version  = match[:version]
        operator = match[:operator]

        raise 'Please specify how to compare the version with >= or < or =' unless operator

        unless Sidekiq::VERSION.send(operator, version)
          skip("Skipped due to version check (requirement was that sidekiq version is " \
               "#{operator} #{version}; was #{Sidekiq::VERSION})")
        end
      end
    end
  end

  config.after(:each) do |example|
    Sidekiq.redis(&:flushdb)
    respond_to_middleware = defined?(Sidekiq::Testing) && Sidekiq::Testing.respond_to?(:server_middleware)
    Sidekiq::Testing.server_middleware(&:clear) if respond_to_middleware
    Sidekiq::Testing.disable! unless example.metadata[:sidekiq].nil?
  end
end
