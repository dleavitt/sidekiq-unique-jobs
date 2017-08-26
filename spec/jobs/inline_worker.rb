# frozen_string_literal: true

class InlineWorker
  include Sidekiq::Worker
  sidekiq_options unique: :while_executing, lock_timeout: 0

  def perform(x)
    TestClass.run(x)
  end
end
