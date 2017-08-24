# frozen_string_literal: true

class ExpiringJob
  include Sidekiq::Worker
  sidekiq_options unique: :until_executed, expiration: 10 * 60
end
