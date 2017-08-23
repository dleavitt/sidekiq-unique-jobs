# frozen_string_literal: true

require 'spec_helper'

RSpec.describe SidekiqUniqueJobs::Timeout::QueueLock do
  let(:calculator) { described_class.new('class' => 'JustAWorker') }

  describe 'public api' do
    subject { calculator }
    it { is_expected.to respond_to(:seconds) }
    it { is_expected.to respond_to(:expiration) }
  end

  describe '#seconds' do
    subject { calculator.seconds }

    before do
      allow(calculator).to receive(:time_until_scheduled).and_return(10)
      allow(calculator).to receive(:worker_class_queue_lock_expiration).and_return(9)
    end

    it { is_expected.to eq(19) }
  end

  describe '#expiration' do
    subject { calculator.expiration }

    context 'using default unique_expiration' do
      before do
        allow(calculator).to receive(:worker_class_expiration).and_return(nil)
        allow(calculator).to receive(:worker_class_queue_lock_expiration).and_return(nil)
      end

      it { is_expected.to eq(1_800) }
    end

    context 'using specified sidekiq option unique_expiration' do
      before { allow(calculator).to receive(:worker_class_queue_lock_expiration).and_return(9) }

      it { is_expected.to eq(9) }
    end
  end
end
