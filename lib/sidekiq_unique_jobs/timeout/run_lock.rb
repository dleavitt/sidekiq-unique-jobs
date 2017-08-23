# frozen_string_literal: true

module SidekiqUniqueJobs
  module Timeout
    class RunLock < Timeout::Calculator
      def seconds
        expiration.to_i
      end

      def expiration
        @expiration ||= worker_class_expiration
        @expiration ||= worker_class_run_lock_expiration
        @expiration ||= SidekiqUniqueJobs.config.default_run_lock_expiration
      end
    end
  end
end
