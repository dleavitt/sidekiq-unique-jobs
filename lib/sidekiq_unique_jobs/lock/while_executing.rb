# frozen_string_literal: true

module SidekiqUniqueJobs
  class Lock
    class WhileExecuting < RunLockBase
      # Don't lock when client middleware runs
      #
      # @param _scope [Symbol] the scope, `:client` or `:server`
      # @return [Boolean] always returns true
      def lock(_scope)
        true
      end

      # Locks while server middleware executes the job
      #
      # @param callback [Proc] callback to call when finished
      # @return [Boolean] report success
      # @raise [SidekiqUniqueJobs::LockTimeout] when lock fails within configured timeout
      def execute(callback, &block)
        performed = @lock.lock(@calculator.lock_timeout) do
          callback&.call
          yield
        end
        fail_with_lock_timeout! unless performed
        unlock(:server)

        performed
      end

      # Unlock the current item
      #
      def unlock(scope)
        @lock.unlock
      end
    end
  end
end
