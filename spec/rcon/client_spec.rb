# frozen_string_literal: true

# Minimal RCON server for testing. Implements auth and EXECCOMMAND handling.
#
# inject_unexpected: send a type=2 packet before the real response to exercise
#                    the `next unless type == RESPONSE_VALUE` branch.
# inject_stale:      send a RESPONSE_VALUE with an unrelated id before the real
#                    response to exercise the `if response.id == cmd_id` branch.
class FakeRCONServer
  def initialize(password:, responses: {}, inject_unexpected: false, inject_stale: false, disconnect_on_command: false)
    @server = TCPServer.new("127.0.0.1", 0)
    @password = password
    @responses = responses
    @inject_unexpected = inject_unexpected
    @inject_stale = inject_stale
    @disconnect_on_command = disconnect_on_command
    @client_socket = nil
    @thread = nil
  end

  def port = @server.addr[1]

  def start
    @thread = Thread.new { run }
    self
  end

  def stop
    [@client_socket, @server].each do |socket|
      socket&.close
    rescue IOError
      nil
    end
    @thread&.join(1)
  end

  private def run
    @client_socket = @server.accept
    handle_client(@client_socket)
  rescue IOError, Errno::EBADF
    nil
  end

  private def handle_client(socket)
    auth = read_packet(socket)
    write_packet(socket, RCon::Client::Packet.new(id: auth.id, type: RCon::Client::PacketType::RESPONSE_VALUE, body: ""))

    if auth.body.b == @password.b
      write_packet(socket, RCon::Client::Packet.new(id: auth.id, type: 2, body: ""))
      handle_commands(socket)
    else
      write_packet(socket, RCon::Client::Packet.new(id: -1, type: 2, body: ""))
    end
  end

  private def handle_commands(socket)
    loop do
      packet = read_packet(socket)
      return unless packet

      if @disconnect_on_command && !packet.body.empty?
        socket.close
        return
      end

      if packet.body.empty?
        # sentinel: echo back to signal end of response
        write_packet(socket, RCon::Client::Packet.new(id: packet.id, type: RCon::Client::PacketType::RESPONSE_VALUE, body: ""))
      else
        inject_unexpected_packet(socket, packet.id) if @inject_unexpected
        inject_stale_packet(socket, packet.id) if @inject_stale

        command = packet.body.force_encoding("UTF-8")
        Array(@responses[command]).each do |part|
          write_packet(socket, RCon::Client::Packet.new(id: packet.id, type: RCon::Client::PacketType::RESPONSE_VALUE, body: part))
        end
      end
    end
  end

  private def inject_unexpected_packet(socket, _cmd_id)
    # type=2 is not RESPONSE_VALUE(0); client should skip it
    write_packet(socket, RCon::Client::Packet.new(id: 999, type: 2, body: ""))
    @inject_unexpected = false
  end

  private def inject_stale_packet(socket, cmd_id)
    # id differs from cmd_id and sentinel_id; client should ignore it
    write_packet(socket, RCon::Client::Packet.new(id: cmd_id + 1000, type: RCon::Client::PacketType::RESPONSE_VALUE, body: "stale"))
    @inject_stale = false
  end

  private def read_packet(socket)
    raw_size = socket.read(4)
    return nil unless raw_size&.bytesize == 4

    size = raw_size.unpack1("l<")
    raw_body = socket.read(size)
    return nil unless raw_body&.bytesize == size

    RCon::Client::Packet.decode(raw_size + raw_body)
  end

  private def write_packet(socket, packet)
    socket.write(packet.encode)
  end
end

RSpec.describe RCon::Client do
  let(:password) { "secret" }
  let(:responses) { {} }
  let(:fake_server) { FakeRCONServer.new(password:, responses:).start }

  after { fake_server.stop }

  describe "#connect" do
    it "returns self on success" do
      client = RCon::Client.new("127.0.0.1", fake_server.port, password:)
      expect(client.connect).to be(client)
      client.close
    end

    it "raises AuthenticationError on wrong password" do
      client = RCon::Client.new("127.0.0.1", fake_server.port, password: "wrong")
      expect { client.connect }.to raise_error(RCon::Client::AuthenticationError, "authentication failed")
    end

    it "raises ConnectionError when server is not listening" do
      server = TCPServer.new("127.0.0.1", 0)
      port = server.addr[1]
      server.close

      client = RCon::Client.new("127.0.0.1", port, password:)
      expect { client.connect }.to raise_error(RCon::Client::ConnectionError)
    end
  end

  describe "#execute" do
    let(:responses) { {"status" => "hostname: example"} }
    let(:client) { RCon::Client.new("127.0.0.1", fake_server.port, password:).tap(&:connect) }

    after do
      client.close
    rescue RCon::Client::Error, IOError
      nil
    end

    it "returns the server response" do
      expect(client.execute("status")).to eq("hostname: example".b)
    end

    it "returns empty string when the command produces no output" do
      expect(client.execute("unknown")).to eq("".b)
    end

    context "when a non-RESPONSE_VALUE packet arrives before the response" do
      # type=2 (AUTH_RESPONSE) can appear unexpectedly; execute should skip it.
      let(:responses) { {"ping" => "pong"} }
      let(:fake_server) { FakeRCONServer.new(password:, responses:, inject_unexpected: true).start }

      it "ignores the unexpected packet and returns the correct response" do
        expect(client.execute("ping")).to eq("pong".b)
      end
    end

    context "when a RESPONSE_VALUE with an unrelated id arrives" do
      # Stale response from a previous command; execute should ignore it.
      let(:responses) { {"info" => "data"} }
      let(:fake_server) { FakeRCONServer.new(password:, responses:, inject_stale: true).start }

      it "ignores the stale packet and returns the correct response" do
        expect(client.execute("info")).to eq("data".b)
      end
    end

    context "when response is split across multiple packets" do
      let(:responses) { {"cvarlist" => %w[alpha beta gamma]} }

      it "concatenates all parts" do
        expect(client.execute("cvarlist")).to eq("alphabetagamma".b)
      end
    end

    context "when the server disconnects unexpectedly" do
      let(:fake_server) { FakeRCONServer.new(password:, disconnect_on_command: true).start }

      it "raises ConnectionError" do
        expect { client.execute("anything") }.to raise_error(RCon::Client::ConnectionError)
      end
    end

    context "when called concurrently from multiple threads" do
      let(:responses) { {"cmd1" => "res1", "cmd2" => "res2", "cmd3" => "res3"} }

      it "returns the correct response for each thread" do
        results = {}
        threads = %w[cmd1 cmd2 cmd3].map {|cmd| Thread.new { results[cmd] = client.execute(cmd) } }
        threads.each(&:join)
        expect(results["cmd1"]).to eq("res1".b)
        expect(results["cmd2"]).to eq("res2".b)
        expect(results["cmd3"]).to eq("res3".b)
      end
    end
  end

  describe "#close" do
    it "is a no-op when not connected" do
      client = RCon::Client.new("127.0.0.1", fake_server.port, password:)
      expect { client.close }.not_to raise_error
    end
  end

  describe "#connected?" do
    it "is false before connect" do
      client = RCon::Client.new("127.0.0.1", fake_server.port, password:)
      expect(client.connected?).to be(false)
    end

    it "is true after connect" do
      client = RCon::Client.new("127.0.0.1", fake_server.port, password:)
      client.connect
      expect(client.connected?).to be(true)
      client.close
    end

    it "is false after close" do
      client = RCon::Client.new("127.0.0.1", fake_server.port, password:)
      client.connect
      client.close
      expect(client.connected?).to be(false)
    end
  end

  describe ".open" do
    context "with a block" do
      it "yields the connected client and disconnects after the block" do
        yielded = nil
        RCon::Client.open("127.0.0.1", fake_server.port, password:) do |client|
          yielded = client
          expect(client.connected?).to be(true)
        end
        expect(yielded.connected?).to be(false)
      end
    end

    context "without a block" do
      it "returns the connected client" do
        client = RCon::Client.open("127.0.0.1", fake_server.port, password:)
        expect(client.connected?).to be(true)
        client.close
      end
    end
  end
end
