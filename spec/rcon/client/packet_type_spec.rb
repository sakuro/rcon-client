# frozen_string_literal: true

RSpec.describe RCon::Client::PacketType do
  it { expect(RCon::Client::PacketType::AUTH).to eq(3) }
  it { expect(RCon::Client::PacketType::EXECCOMMAND).to eq(2) }
  it { expect(RCon::Client::PacketType::RESPONSE_VALUE).to eq(0) }
end
