# frozen_string_literal: true

module RCon
  class Client
    module PacketType
      AUTH = 3
      public_constant :AUTH

      EXECCOMMAND = 2
      public_constant :EXECCOMMAND

      RESPONSE_VALUE = 0
      public_constant :RESPONSE_VALUE
    end
  end
end
