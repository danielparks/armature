require 'open3'

module Gofer::Run
  extend self

  class CommandFailureError < StandardError
    attr_reader :status
    attr_reader :command

    def initialize(status, command)
      @status = status
      @command = command
    end
  end

  def command(*command)
    out, status = Open3.capture2e(*command)
    if ! status.success?
      raise CommandFailureError.new(status, command, out)
    end
    out
  end
end
