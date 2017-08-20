# frozen_string_literal: true

module SidekiqUniqueJobs
  module Lock
    # rubocop:disable ClassLength
    class WhileExecuting
      EXISTS_TOKEN = '1'
      API_VERSION = '1'

      # stale_client_timeout is the threshold of time before we assume
      # that something has gone terribly wrong with a client and we
      # invalidate it's lock.
      # Default is nil for which we don't check for stale clients
      # SidekiqUniqueJobs::Lock::WhileExecuting.new(item, :stale_client_timeout => 30, :redis => myRedis)
      # SidekiqUniqueJobs::Lock::WhileExecuting.new(item, :redis => myRedis)
      # SidekiqUniqueJobs::Lock::WhileExecuting.new(item, :resources => 1, :redis => myRedis)
      # SidekiqUniqueJobs::Lock::WhileExecuting.new(item, :host => "", :port => "")
      # SidekiqUniqueJobs::Lock::WhileExecuting.new(item, :path => "bla")
      def initialize(item, opts = {})
        @item = item
        @name = create_digest
        @redis_pool = opts.delete(:redis_pool)
        @expiration = opts.delete(:expiration)
        @resource_count = opts.delete(:resources) || 1
        @stale_client_timeout = opts.delete(:stale_client_timeout)
        @use_local_time = opts.delete(:use_local_time)
        @tokens = []
      end

      def exists_or_create!
        SidekiqUniqueJobs::Scripts.call(
          :create,
          @redis_pool,
          keys: [exists_key, grabbed_key, available_key, version_key],
          argv: [EXISTS_TOKEN, @resource_count, @expiration, API_VERSION],
        )
      end

      def exists?
        SidekiqUniqueJobs.connection(@redis_pool) do |conn|
          conn.exists(exists_key)
        end
      end

      def available_count
        SidekiqUniqueJobs.connection(@redis_pool) do |conn|
          if conn.exists(exists_key)
            conn.llen(available_key)
          else
            @resource_count
          end
        end
      end

      def delete!
        SidekiqUniqueJobs.connection(@redis_pool) do |conn|
          conn.del(available_key)
          conn.del(grabbed_key)
          conn.del(exists_key)
          conn.del(version_key)
        end
      end

      def lock(timeout = nil) # rubocop:disable Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity, Metrics/LineLength
        return true if timeout == :client
        exists_or_create!
        result = release_stale_locks!

        SidekiqUniqueJobs.connection(@redis_pool) do |conn|
          if timeout.nil? || timeout.positive?
            # passing timeout 0 to blpop causes it to block
            _key, current_token = conn.blpop(available_key, timeout || 0)
          else
            current_token = conn.lpop(available_key)
          end

          return false if current_token.nil?

          @tokens.push(current_token)
          conn.hset(grabbed_key, current_token, current_time.to_f)
          return_value = current_token

          if block_given?
            begin
              return_value = yield current_token
            ensure
              signal(conn, current_token)
            end
          end

          return_value
        end
      end
      alias wait lock
      alias synchronize lock

      def execute(_callback)
        lock do
          yield
        end
      end

      def unlock
        return false unless locked?
        SidekiqUniqueJobs.connection(@redis_pool) do |conn|
          signal(conn, @tokens.pop)[1]
        end
      end

      def locked?(token = nil)
        if token
          SidekiqUniqueJobs.connection(@redis_pool) do |conn|
            conn.hexists(grabbed_key, token)
          end
        else
          @tokens.each do |cached_token|
            return true if locked?(cached_token)
          end

          false
        end
      end

      def all_tokens(conn = nil)
        if conn
          all_tokens_for(conn)
        else
          SidekiqUniqueJobs.connection(@redis_pool) do |redis|
            all_tokens_for(redis)
          end
        end
      end

      def all_tokens_for(conn)
        conn.multi do
          conn.lrange(available_key, 0, -1)
          conn.hkeys(grabbed_key)
        end.flatten
      end

      def signal(conn, token = 1)
        token ||= generate_unique_token(conn)

        conn.multi do
          conn.hdel grabbed_key, token
          conn.lpush available_key, token

          expire_when_necessary(conn)
        end
      end

      def generate_unique_token(conn)
        tokens = all_tokens(conn)
        token = Random.rand.to_s
        token = Random.rand.to_s while tokens.include? token
        token
      end

      def release_stale_locks!
        return unless check_staleness?
        SidekiqUniqueJobs::Scripts.call(
          :release_stale_locks,
          @redis_pool,
          keys:  [exists_key, grabbed_key, available_key, version_key, release_key],
          argv: [10, @stale_client_timeout, @expiration],
        )
      end

      private

      def expire_when_necessary(conn)
        return if @expiration.nil?

        [available_key, exists_key, version_key].each do |key|
          conn.expire(key, @expiration)
        end
      end

      def check_staleness?
        !@stale_client_timeout.nil?
      end

      def namespaced_key(variable)
        "#{@name}:#{variable}"
      end

      def available_key
        @available_key ||= namespaced_key('AVAILABLE')
      end

      def exists_key
        @exists_key ||= namespaced_key('EXISTS')
      end

      def grabbed_key
        @grabbed_key ||= namespaced_key('GRABBED')
      end

      def version_key
        @version_key ||= namespaced_key('VERSION')
      end

      def release_key
        @release_key ||= namespaced_key('RELEASE')
      end

      def current_time
        if @use_local_time
          Time.now
        else
          begin
            instant = SidekiqUniqueJobs.connection(@redis_pool, &:time)
            Time.at(instant[0], instant[1])
          rescue
            @use_local_time = true
            current_time
          end
        end
      end

      def create_digest
        @create_digest ||= @item[UNIQUE_DIGEST_KEY]
        @create_digest ||= SidekiqUniqueJobs::UniqueArgs.digest(@item)
      end
    end
  end
end
