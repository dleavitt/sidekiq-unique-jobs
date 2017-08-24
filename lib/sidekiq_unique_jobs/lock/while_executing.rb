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
        performed = @lock.lock(timeout) do
          yield
          callback.call
        end

        fail_with_lock_timeout! unless performed
      end

      def unlock
        @lock.unlock
      end

      private

      def timeout
        @timeout ||= Timeout::RunLock.new(@item).seconds
      end

      def fail_with_lock_timeout!
        raise(SidekiqUniqueJobs::LockTimeout,
              "couldn't achieve lock for #{@lock.available_key} within: #{timeout} seconds")
      end
    end
  end
end
