# frozen_string_literal: true

module SidekiqUniqueJobs
  module Timeout
    class QueueLock < Timeout::Calculator
      def seconds
        expiration + time_until_scheduled
      end

      def expiration
        @expiration ||= worker_class_expiration
        @expiration ||= worker_class_queue_lock_expiration
        @expiration ||= SidekiqUniqueJobs.config.default_queue_lock_expiration
        @expiration   = @expiration.to_i
        @expiration
      end
    end
  end
end
