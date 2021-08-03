# frozen_string_literal: true

require 'socket'
require_relative './http/request_parser'
require_relative './http/responder'

module MultiThread
  class ThreadPool
    attr_accessor :queue, :running, :size

    def initialize(size:)
      self.size = size

      # threadsafe queue to manage work
      self.queue = Queue.new

      size.times do
        Thread.new(queue) do |queue|
          # "catch" in Ruby is a lesser known
          # way to change flow of the program,
          # similar to propagating exceptions
          catch(:exit) do
            loop do
              # `pop` blocks until there's
              # something in the queue
              task = queue.pop
              task.call
            end
          end
        end
      end
    end

    def perform(&block)
      queue << block
    end

    def shutdown
      size.times do
        # this is going to make threads
        # break out of the infinite loop
        perform { throw :exit }
      end
    end
  end

  class Server
    PORT = ENV.fetch('PORT', 3000)
    HOST = ENV.fetch('HOST', '127.0.0.1').freeze
    # number of incoming connections to keep in a buffer
    SOCKET_READ_BACKLOG = ENV.fetch('TCP_BACKLOG', 12).to_i
    WORKER_COUNT = ENV.fetch('WORKERS', 4).to_i

    attr_accessor :app

    def initialize(app)
      self.app = app
    end

    def start
      pool = ThreadPool.new(size: WORKER_COUNT)
      socket = TCPServer.new(HOST, PORT)
      socket.listen(SOCKET_READ_BACKLOG)
      puts "--- Server started on host #{HOST} and port #{PORT}"
      puts "--- Server is working in #{WORKER_COUNT} Threads"
      loop do
        conn, _addr_info = socket.accept
        # execute the request in one of the threads
        pool.perform do
          request = HTTP::RequestParser.call(conn)
          status, header, body = app.call(request)
          HTTP::Responder.call(conn, status, header, body)
        rescue StandardError => e
          puts e.message
        ensure
          conn&.close
        end
      end
    rescue Interrupt
      puts '-- Server stopped successfully'
    ensure
      pool&.shutdown
    end
  end
end

class FileServingApp
  # read file from the filesystem based on a path from
  # a request, e.g. "/test.txt"
  def call(env)
    # this is totally unsecure, but good enough for the demo
    path = Dir.getwd + env['PATH_INFO']
    if File.exist?(path)
      body = File.read(path)
      [200, { 'Content-Type' => 'text/html' }, [body]]
    else
      [404, { 'Content-Type' => 'text/html' }, ['']]
    end
  end
end

MultiThread::Server.new(FileServingApp.new).start
