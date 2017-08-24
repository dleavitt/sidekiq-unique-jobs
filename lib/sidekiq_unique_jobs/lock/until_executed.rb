# frozen_string_literal: true

module SidekiqUniqueJobs
  class Lock
    class UntilExecuted
      OK ||= 'OK'

      include SidekiqUniqueJobs::Unlockable

      extend Forwardable
      def_delegators :Sidekiq, :logger

      def initialize(item, redis_pool = nil)
        @item = item.merge('expiration' => Timeout::QueueLock.new(item).seconds)
        @redis_pool = redis_pool
        @lock ||= SidekiqUniqueJobs::Lock.new(@item, @redis_pool)
      end

      def execute(callback, &blk)
        operative = true
        send(:after_yield_yield, &blk)
      rescue Sidekiq::Shutdown
        operative = false
        raise
      ensure
        if operative && unlock(:server)
          callback.call
        else
          logger.fatal("the unique_key: #{unique_key} needs to be unlocked manually")
        end
      end

      def unlock(scope)
        unless [:server, :api, :test].include?(scope)
          raise ArgumentError, "#{scope} middleware can't #{__method__} #{unique_key}"
        end

        @lock.unlock
      end

      def lock(scope)
        if scope.to_sym != :client
          raise ArgumentError, "#{scope} middleware can't #{__method__} #{unique_key}"
        end

        @lock.lock(0)
      end
      # rubocop:enable MethodLength

      def unique_key
        @unique_key ||= UniqueArgs.digest(@item)
      end

      def after_yield_yield
        yield
      end
    end
  end
end
