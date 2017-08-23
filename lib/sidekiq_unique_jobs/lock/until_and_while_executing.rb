# frozen_string_literal: true

module SidekiqUniqueJobs
  class Lock
    class UntilAndWhileExecuting < UntilExecuting
      def execute(callback)
        unlock(:server)

        runtime_lock.lock do
          yield
        end

        callback.call
      end

      def runtime_lock
        @runtime_lock ||= SidekiqUniqueJobs::Lock::WhileExecuting.new(item, redis_pool: redis_pool)
      end
    end
  end
end
