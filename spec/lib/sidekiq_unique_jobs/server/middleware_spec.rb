# frozen_string_literal: true

require 'spec_helper'
require 'sidekiq/api'
require 'sidekiq/cli'
require 'sidekiq/worker'
require 'sidekiq_unique_jobs/server/middleware'

RSpec.describe SidekiqUniqueJobs::Server::Middleware do
  let(:middleware) { SidekiqUniqueJobs::Server::Middleware.new }

  QUEUE ||= 'working'

  def digest_for(item)
    SidekiqUniqueJobs::UniqueArgs.digest(item)
  end

  describe '#call' do
    subject { middleware.call(*args) {} }
    let(:args) { [WhileExecutingJob, { 'class' => 'WhileExecutingJob' }, 'working', nil] }

    context 'when unique is disabled' do
      before do
        allow(middleware).to receive(:unique_enabled?).and_return(false)
      end

      it 'does not use locking' do
        expect(middleware).not_to receive(:lock)
        subject
      end
    end

    context 'when unique is enabled' do
      let(:lock) { instance_spy(SidekiqUniqueJobs::Lock::WhileExecuting) }

      before do
        allow(middleware).to receive(:unique_enabled?).and_return(true)
        allow(middleware).to receive(:lock).and_return(lock)
      end

      it 'executes the lock' do
        expect(lock).to receive(:send).with(:execute, instance_of(Proc)).and_yield
        subject
      end
    end

    describe '#unlock' do
      it 'does not unlock keys it does not own' do
        jid = UntilExecutedJob.perform_async
        item = Sidekiq::Queue.new(QUEUE).find_job(jid).item

        unique_digest = digest_for(item)

        Sidekiq.redis do |conn|
          conn.set(unique_digest, 'NOT_DELETED')
        end

        expect(Sidekiq.logger).to receive(:fatal)
          .with("the unique_key: #{unique_digest} needs to be unlocked manually")

        middleware.call(UntilExecutedJob.new, item, QUEUE) do
          Sidekiq.redis do |conn|
            expect(conn.get(unique_digest)).to eq('NOT_DELETED')
          end
        end
      end
    end

    describe ':before_yield' do
      it 'removes the lock before yielding to the worker' do
        jid = UntilExecutingJob.perform_async
        item = Sidekiq::Queue.new(QUEUE).find_job(jid).item
        worker = UntilExecutingJob.new

        middleware.call(worker, item, QUEUE) do
          Sidekiq.redis do |conn|
            expect(conn.ttl(digest_for(item))).to eq(-2) # key does not exist
          end
        end
      end
    end

    describe ':after_yield' do
      it 'removes the lock after yielding to the worker' do
        jid = UntilExecutedJob.perform_async
        item = Sidekiq::Queue.new(QUEUE).find_job(jid).item

        middleware.call('UntilExecutedJob', item, QUEUE) do
          Sidekiq.redis do |conn|
            expect(conn.get(digest_for(item))).to eq jid
          end
        end
      end
    end
  end
end
