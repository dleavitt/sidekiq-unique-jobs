# frozen_string_literal: true

require 'sidekiq_unique_jobs/testing/sidekiq_overrides'

module SidekiqUniqueJobs
  alias redis_version_real redis_version
  def redis_version
    if mocked?
      '0.0'
    else
      redis_version_real
    end
  end

  class Lock
    module Testing
      def self.included(base)
        base.class_eval do
          alias_method :exists_or_create_orig!, :exists_or_create!
          alias_method :exists_or_create!, :exists_or_create_ext!

          alias_method :lock_orig, :lock
          alias_method :lock, :lock_ext
        end
      end

      def exists_or_create_ext!
        return exists_or_create_orig! unless SidekiqUniqueJobs.mocked?

        SidekiqUniqueJobs.connection do |conn|
          token = conn.getset(exists_key, @item[JID_KEY])

          if token.nil?
            conn.expire(exists_key, 10)

            conn.multi do
              conn.del(grabbed_key)
              conn.del(available_key)
              @lock_resources.times do |index|
                conn.rpush(available_key, index)
              end
              conn.set(version_key, API_VERSION)
              conn.persist(exists_key)

              expire_when_necessary(conn)
            end
          else
            conn.set(version_key, API_VERSION) if conn.get(version_key).nil?
            true
          end
        end
      end

      def lock_ext(timeout = nil, &block) # rubocop:disable MethodLength
        return lock_orig(timeout, &block) unless SidekiqUniqueJobs.mocked?

        SidekiqUniqueJobs.connection(@redis_pool) do |conn|
          exists_or_create!
          release_stale_locks!
          current_token = conn.lpop(available_key)
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
    end

    include Testing
  end

  module Client
    class Middleware
      # alias call_real call
      # def call(worker_class, item, queue, redis_pool = nil)
      #   worker_class = SidekiqUniqueJobs.worker_class_constantize(worker_class)

      #   if Sidekiq::Testing.inline?
      #     call_real(worker_class, item, queue, redis_pool) do
      #       _server.call(worker_class.new, item, queue, redis_pool) do
      #         yield
      #       end
      #     end
      #   else
      #     call_real(worker_class, item, queue, redis_pool) do
      #       yield
      #     end
      #   end
      # end

      def _server
        SidekiqUniqueJobs::Server::Middleware.new
      end
    end
  end
end
