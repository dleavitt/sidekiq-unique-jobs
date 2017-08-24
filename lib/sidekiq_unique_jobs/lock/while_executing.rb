# frozen_string_literal: true

module SidekiqUniqueJobs
  class Lock
    class WhileExecuting
      def initialize(item, redis_pool = nil)
        @item = item
        @redis_pool = redis_pool
        @item[EXPIRATION_KEY] ||= @item[RUN_LOCK_TIMEOUT_KEY]
        @lock ||= SidekiqUniqueJobs::Lock.new(@item)
      end

      def lock(_scope)
        true
      end

      def execute(callback = nil)
        @lock.lock(Timeout::RunLock.new(@item).seconds) do
          yield
          callback.call
        end
      end

      def unlock
        @lock.unlock
      end
    end
  end
end
