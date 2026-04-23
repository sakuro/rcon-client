# frozen_string_literal: true

RSpec.describe RCon::Client::Connection do
  let(:tcp_server) { TCPServer.new("127.0.0.1", 0) }
  let(:port) { tcp_server.addr[1] }

  after do
    tcp_server.close
  rescue IOError
    nil
  end

  describe "#open" do
    it "returns self on success" do
      connection = RCon::Client::Connection.new("127.0.0.1", port)
      result = connection.open
      connection.close
      expect(result).to be(connection)
    end

    it "raises ConnectionError when connection is refused" do
      closed_port = tcp_server.addr[1]
      tcp_server.close
      expect {
        RCon::Client::Connection.new("127.0.0.1", closed_port).open
      }.to raise_error(RCon::Client::ConnectionError)
    end
  end

  describe "#close" do
    it "is a no-op when not opened" do
      connection = RCon::Client::Connection.new("127.0.0.1", port)
      expect { connection.close }.not_to raise_error
    end
  end

  describe "#send_packet / #receive_packet" do
    it "raises ConnectionError when the server closes before sending any data" do
      thread = Thread.new do
        socket = tcp_server.accept
        socket.close
      end

      connection = RCon::Client::Connection.new("127.0.0.1", port).open
      thread.join
      expect { connection.receive_packet }.to raise_error(RCon::Client::ConnectionError, "connection closed by server")
      connection.close
    end

    it "raises ConnectionError when the server closes after sending the size field" do
      thread = Thread.new do
        socket = tcp_server.accept
        socket.write([10].pack("l<")) # valid size, but no body follows
        socket.close
      end

      connection = RCon::Client::Connection.new("127.0.0.1", port).open
      thread.join
      expect { connection.receive_packet }.to raise_error(RCon::Client::ConnectionError, "connection closed by server")
      connection.close
    end

    it "round-trips a packet through a loopback server" do
      thread = Thread.new do
        socket = tcp_server.accept
        raw_size = socket.read(4)
        size = raw_size.unpack1("l<")
        socket.write(raw_size + socket.read(size))
        socket.close
      end

      packet = RCon::Client::Packet.new(id: 7, type: 3, body: "hello")
      connection = RCon::Client::Connection.new("127.0.0.1", port).open
      connection.send_packet(packet)
      received = connection.receive_packet
      connection.close
      thread.join

      expect(received.id).to eq(7)
      expect(received.type).to eq(3)
      expect(received.body).to eq("hello".b)
    end
  end
end
