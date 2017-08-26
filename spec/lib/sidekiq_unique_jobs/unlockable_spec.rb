# frozen_string_literal: true

require 'spec_helper'

RSpec.describe SidekiqUniqueJobs::Unlockable, redis: :redis do
  def item_with_digest
    SidekiqUniqueJobs::UniqueArgs.digest(item)
    item
  end
  let(:item) do
    { 'class' => MyUniqueJob,
      'queue' => 'customqueue',
      'args' => [1, 2] }
  end

  let(:unique_digest) { item_with_digest[SidekiqUniqueJobs::UNIQUE_DIGEST_KEY] }

  describe '.unlock' do
    subject { described_class.unlock(item_with_digest) }

    let(:expected_keys) do
      %W[#{unique_digest}:EXISTS #{unique_digest}:GRABBED #{unique_digest}:VERSION]
    end

    specify do
      expect(SidekiqUniqueJobs::Util.keys.count).to eq(0)
      Sidekiq::Client.push(item_with_digest)

      expect(SidekiqUniqueJobs::Util.keys.count).to eq(3)
      expect(SidekiqUniqueJobs::Util.keys).to match_array(expected_keys)

      subject

      expect(SidekiqUniqueJobs::Util.keys.count).to eq(0)
      expect(SidekiqUniqueJobs::Util.keys).not_to match_array(expected_keys)
    end
  end
end
