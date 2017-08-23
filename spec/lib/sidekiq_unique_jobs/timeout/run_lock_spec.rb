# frozen_string_literal: true

require 'spec_helper'

RSpec.describe SidekiqUniqueJobs::Timeout::RunLock do
  subject { calculator }

  let(:calculator) { described_class.new(args) }
  let(:args)       { { 'class' => 'JustAWorker' } }

  it { is_expected.to respond_to(:seconds) }

  describe '#seconds' do
    subject { calculator.seconds }

    let(:expiration)          { nil }
    let(:run_lock_expiration) { nil }

    before do
      allow(calculator).to receive(:worker_class_expiration).and_return(expiration)
      allow(calculator).to receive(:worker_class_run_lock_expiration).and_return(run_lock_expiration)
    end

    context 'when worker_class_expiration is configured' do
      let(:expiration) { 9 }
      it { is_expected.to eq(9) }
    end

    context 'when worker_class_run_lock_expiration is not configured' do
      let(:run_lock_expiration) { 11 }
      it { is_expected.to eq(11) }
    end

    context 'when neither worker_class_run_lock_expiration or worker_class_expiration is configured' do
      it { is_expected.to eq(60) }
    end
  end
end
