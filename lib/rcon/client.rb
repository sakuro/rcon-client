# frozen_string_literal: true

require "zeitwerk"
require_relative "client/version"

module RCon
  # RCon::Client provides [description of your gem].
  #
  # This module serves as the namespace for the gem's functionality.
  module Client
    class Error < StandardError; end

    loader = Zeitwerk::Loader.for_gem
    loader.ignore("#{__dir__}/client/version.rb")
    loader.inflector.inflect(
      "rcon" => "RCon"
    )
    loader.setup
  end
end
