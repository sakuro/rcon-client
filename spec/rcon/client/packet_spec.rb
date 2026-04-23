# frozen_string_literal: true

RSpec.describe RCon::Client::Packet do
  describe "#encode" do
    context "when body is empty" do
      it "produces minimum packet size of 10" do
        packet = RCon::Client::Packet.new(id: 1, type: 0)
        expect(packet.encode.unpack1("l<")).to eq(10)
      end
    end

    context "when body is within the limit" do
      it "encodes with size = 10 + body bytesize" do
        packet = RCon::Client::Packet.new(id: 1, type: 3, body: "secret")
        expect(packet.encode.unpack1("l<")).to eq(16)
      end
    end

    context "when body is exactly 511 bytes" do
      it "does not raise" do
        packet = RCon::Client::Packet.new(id: 1, type: 2, body: "x" * 511)
        expect { packet.encode }.not_to raise_error
      end
    end

    context "when body exceeds 511 bytes" do
      it "raises Error" do
        packet = RCon::Client::Packet.new(id: 1, type: 2, body: "x" * 512)
        expect { packet.encode }.to raise_error(RCon::Client::Error, /body too long \(512 > 511\)/)
      end
    end
  end

  describe ".decode" do
    it "restores id, type, and body" do
      original = RCon::Client::Packet.new(id: 5, type: 3, body: "secret")
      decoded = RCon::Client::Packet.decode(original.encode)
      expect(decoded.id).to eq(5)
      expect(decoded.type).to eq(3)
      expect(decoded.body).to eq("secret".b)
    end

    it "handles empty body" do
      original = RCon::Client::Packet.new(id: 42, type: 0)
      decoded = RCon::Client::Packet.decode(original.encode)
      expect(decoded.id).to eq(42)
      expect(decoded.body).to eq("".b)
    end

    it "handles negative id" do
      original = RCon::Client::Packet.new(id: -1, type: 2)
      decoded = RCon::Client::Packet.decode(original.encode)
      expect(decoded.id).to eq(-1)
    end
  end
end
