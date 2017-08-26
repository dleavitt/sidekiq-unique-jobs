# frozen_string_literal: true

module SidekiqUniqueJobs
  class Lock
    class RescheduleWhileExecuting < RunLockBase
      def lock(_scope)
        true
      end

      def execute(callback = nil)
        @lock.lock do
          yield
          callback.call
        end

        Sidekiq::Client.push(@item) unless @lock.locked?
      end

      def unlock
        @lock.unlock
      end
    end
  end
end
