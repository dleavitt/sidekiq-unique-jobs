# frozen_string_literal: true

require 'spec_helper'

RSpec.describe SidekiqUniqueJobs::Lock::WhileExecuting do
  let(:lock)              { described_class.new(lock_item, lock_options) }
  let(:multilock)         { described_class.new(multilock_item, multilock_options) }
  let(:lock_options)      { {} }
  let(:multilock_options) { { resources: 2 } }
  let(:lock_item) do
    {
      'jid' => 'maaaahjid',
      'queue' => 'dupsallowed',
      'class' => 'UntilAndWhileExecuting',
      'unique' => 'until_executed',
      'unique_digest' => 'test_mutex_key',
      'args' => [1],
    }
  end
  let(:multilock_item) do
    {
      'jid' => 'maaaahjid',
      'queue' => 'dupsallowed',
      'class' => 'UntilAndWhileExecuting',
      'unique' => 'until_executed',
      'unique_digest' => 'test_mutex_key',
      'args' => [1],
    }
  end

  describe 'redis' do
    shared_examples_for 'a lock' do
      it 'has the correct amount of available resources' do
        lock.lock
        expect(lock.unlock).to eq(1)
        expect(lock.available_count).to eq(1)
      end

      it 'has the correct amount of available resources before locking' do
        expect(lock.available_count).to eq(1)
      end

      it 'should not exist from the start' do
        expect(lock.exists?).to eq(false)
        lock.lock
        expect(lock.exists?).to eq(true)
      end

      it 'should be unlocked from the start' do
        expect(lock.locked?).to eq(false)
      end

      it 'should lock and unlock' do
        lock.lock(1)
        expect(lock.locked?).to eq(true)
        lock.unlock
        expect(lock.locked?).to eq(false)
      end

      it 'should not lock twice as a mutex' do
        expect(lock.lock(1)).not_to eq(false)
        expect(lock.lock(1)).to eq(false)
      end

      it 'should not lock three times when only two available' do
        expect(multilock.lock(1)).not_to eq(false)
        expect(multilock.lock(1)).not_to eq(false)
        expect(multilock.lock(1)).to eq(false)
      end

      it 'should always have the correct lock-status' do
        multilock.lock(1)
        multilock.lock(1)

        expect(multilock.locked?).to eq(true)
        multilock.unlock
        expect(multilock.locked?).to eq(true)
        multilock.unlock
        expect(multilock.locked?).to eq(false)
      end

      it 'should get all different tokens when saturating' do
        ids = []
        2.times do
          ids << multilock.lock(1)
        end

        expect(ids).to eq(%w[0 1])
      end

      it 'should execute the given code block' do
        code_executed = false
        lock.lock(1) do
          code_executed = true
        end
        expect(code_executed).to eq(true)
      end

      it 'should pass an exception right through' do
        expect do
          lock.lock(1) do
            raise Exception, 'redis lock exception'
          end
        end.to raise_error(Exception, 'redis lock exception')
      end

      it 'should not leave the lock locked after raising an exception' do
        expect do
          lock.lock(1) do
            raise Exception, 'redis lock exception'
          end
        end.to raise_error(Exception, 'redis lock exception')

        expect(lock.locked?).to eq(false)
      end

      it 'should return the value of the block if block-style locking is used' do
        block_value = lock.lock(1) do
          42
        end
        expect(block_value).to eq(42)
      end

      it 'can return the passed in token to replicate old behaviour' do
        lock_token = lock.lock(1)
        lock.unlock

        block_value = lock.lock(1) do |token|
          token
        end
        expect(block_value).to eq(lock_token)
      end

      it 'should disappear without a trace when calling `delete!`' do
        original_key_size = SidekiqUniqueJobs.connection { |conn| conn.keys.count }

        lock.exists_or_create!
        lock.delete!

        expect(SidekiqUniqueJobs.connection { |conn| conn.keys.count }).to eq(original_key_size)
      end

      it 'should not block when the timeout is zero' do
        did_we_get_in = false

        lock.lock do
          lock.lock(0) do
            did_we_get_in = true
          end
        end

        expect(did_we_get_in).to be false
      end

      it 'should be locked when the timeout is zero' do
        lock.lock(0) do
          expect(lock.locked?).to be true
        end
      end
    end

    describe 'lock with expiration' do
      let(:lock_options) { { expiration: 1 } }
      let(:multilock_options) { { resources: 2, expiration: 2 } }

      it_behaves_like 'a lock'

      def current_keys
        SidekiqUniqueJobs.connection(&:keys)
      end

      it 'expires keys' do
        Sidekiq.redis(&:flushdb)
        lock.exists_or_create!
        keys = current_keys
        sleep 3.0
        expect(current_keys).not_to include(keys)
      end

      it 'expires keys after unlocking' do
        Sidekiq.redis(&:flushdb)
        lock.lock do
          # noop
        end
        keys = current_keys
        sleep 3.0
        expect(current_keys).not_to include(keys)
      end
    end

    describe 'lock without staleness checking' do
      it_behaves_like 'a lock'

      it 'can dynamically add resources' do
        lock.exists_or_create!

        SidekiqUniqueJobs.connection do |conn|
          3.times do
            lock.signal(conn)
          end
        end

        expect(lock.available_count).to eq(4)

        lock.wait(1)
        lock.wait(1)
        lock.wait(1)

        expect(lock.available_count).to eq(1)
      end

      it 'can have stale locks released by a third process' do
        watchdog = described_class.new(lock_item, stale_client_timeout: 1)
        lock.lock

        sleep 0.5
        watchdog.release_stale_locks!
        expect(lock.locked?).to eq(true)

        sleep 0.6

        watchdog.release_stale_locks!
        expect(lock.locked?).to eq(false)
      end
    end

    describe 'lock with staleness checking' do
      let(:lock_options) { { stale_client_timeout: 5 } }
      let(:multilock_options) { { resources: 2, stale_client_timeout: 5 } }

      it_behaves_like 'a lock'

      it 'should restore resources of stale clients' do
        hyper_aggressive_lock = described_class.new(lock_item, resources: 1, stale_client_timeout: 1)

        expect(hyper_aggressive_lock.lock(1)).not_to eq(false)
        expect(hyper_aggressive_lock.lock(1)).to eq(false)
        expect(hyper_aggressive_lock.lock(1)).not_to eq(false)
      end
    end

    describe 'redis time' do
      let(:lock_options) { { stale_client_timeout: 5 } }

      before(:all) do
        Timecop.freeze(Time.local(1990))
      end

      it 'with time support should return a different time than frozen time' do
        expect(lock.send(:current_time)).not_to eq(Time.now)
      end

      context 'when use_local_time is true' do
        let(:lock_options) { { stale_client_timeout: 5, use_local_time: true } }

        it 'with use_local_time should return the same time as frozen time' do
          expect(lock.send(:current_time)).to eq(Time.now)
        end
      end
    end

    describe 'all_tokens' do
      let(:lock_options) { { stale_client_timeout: 5 } }

      it 'includes tokens from available and grabbed keys' do
        lock.exists_or_create!
        available_keys = lock.all_tokens
        lock.lock(1)
        grabbed_keys = lock.all_tokens

        expect(available_keys).to eq(grabbed_keys)
      end
    end

    describe 'version' do
      context 'with an existing versionless lock' do
        let(:old_sem) { described_class.new(lock_item) }
        let(:version_key) { old_sem.send(:version_key) }

        before do
          old_sem.exists_or_create!
          SidekiqUniqueJobs.connection { |conn| conn.del(version_key) }
        end

        it 'sets the version key' do
          lock.exists_or_create!
          expect(SidekiqUniqueJobs.connection { |conn| conn.get(version_key) }).not_to be_nil
        end
      end
    end
  end
end
