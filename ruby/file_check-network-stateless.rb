#!/usr/bin/env ruby
#===============================================================================
#
#         FILE: file_check-local-stateless.rb
#
#        USAGE: ./file_check-local-stateless.rb
#
#  DESCRIPTION: An exmple of a local, stateless plugin in ruby. Checks a to see
#               a file to see if it exists, and checks the contents.
#
#      OPTIONS: ---
# REQUIREMENTS: ---
#         BUGS: ---
#        NOTES: ---
#       AUTHOR: Ryan Quinn (RQ)
# ORGANIZATION: OP5
#      VERSION: 0.0.1
#      CREATED: 08/22/2018 10:06:54 PM
#      LICENSE: MIT
#===============================================================================

# Standard libs
require 'optparse'
require 'pp'
require 'pathname'

# Gems
require 'rubygems'
require 'net/ssh'

class OptParsing
  Version = '0.0.1'

  @warning = nil
  @critical = nil
  @filepath = nil
  @timeout = nil
  @host = nil
  @username = nil
  @passphrase = nil
  @identity = nil
  @port = nil

  class ScriptOptions
    attr_accessor :verbose,
                  :delay,
                  :extension,
                  :record_separator,
                  :warning,
                  :critical,
                  :filepath,
                  :timeout,
                  :host,
                  :username,
                  :passphrase,
                  :identity,
                  :port

    def initialize
      self.verbose = false
      self.delay = 0
      self.timeout = 10
      self.warning = Hash.new
      self.warning[:check] = false
      self.warning[:inclusive] = false
      self.critical = Hash.new
      self.critical[:check] = false
      self.critical[:inclusive] = false
      self.port = 22
      self.passphrase = nil
    end

    def define_options(parser)
      parser.banner = "Usage: #{$0} [options]"
      parser.separator ""
      parser.separator "Specific options:"

      verbose_enable(parser)
      exec_delay(parser)
      threshold_warning(parser)
      threshold_critical(parser)
      set_filepath(parser)
      set_timeout(parser)
      set_host(parser)
      set_username(parser)
      set_passphrase(parser)
      set_identity(parser)
      set_port(parser)

      parser.separator "Common options:"
      parser.on_tail("-h", "--help", "Show usage information.") do
        puts parser
        exit 3
      end
      parser.on_tail("-V", "--version", "Shows version number.") do
        puts Version
        exit 3
      end
    end

    #TODO: Allow 'v' multiple times to increase the verbosity of the output.
    def verbose_enable(parser)
      parser.on("-v", "Enable more output.") do |v|
        self.verbose = v
      end
    end

    def exec_delay(parser)
      parser.on("-d N", "--delay N", Integer, "Delays the execution of the check for X seconds.") do |n|
        self.delay = n
      end
    end

    def set_timeout(parser)
      parser.on("-t N", "--timeout N", Integer, "Sets the maximum execution time in seconds.") do |n|
        self.timeout = n
      end
    end

    def threshold_warning(parser)
      parser.on("-w RANGE", "--warning RANGE", String, "Warning thresholds.") do |w|
        self.warning[:string_orig] = w

        if w.include? '@'
          self.warning[:inclusive] = true
          w = w.tr('@', '')
        end

        if w.include? ':'
          range_start, range_end = w.split(':')
          if range_start == '~'
            range_start = nil
          else
            range_start = range_start.to_i
          end
          if range_end != nil
            range_end = range_end.to_i
          end
        else
          range_start = 0
          range_end = w.to_i
        end

        self.warning[:range_start] = range_start
        self.warning[:range_end] = range_end
        self.warning[:check] = true
      end
    end

    def threshold_critical(parser)
      parser.on("-c RANGE", "--critical RANGE", String, "Critical thresholds.") do |c|
        self.critical[:string_orig] = c

        if c.include? '@'
          self.critical[:inclusive] = true
          c = c.tr('@', '')
        end

        if c.include? ':'
          range_start, range_end = c.split(':')
          if range_start == '~'
            range_start = nil
          else
            range_start = range_start.to_i
          end
          if range_end != nil
            range_end = range_end.to_i
          end
        else
          range_start = 0
          range_end = c.to_i
        end

        self.critical[:range_start] = range_start
        self.critical[:range_end] = range_end
        self.critical[:check] = true
      end
    end

    def set_filepath(parser)
      parser.on("-f FN", "--filepath FN", String, "Path to file.") do |f|
        #TODO: Make mandatory
        #self.filepath = File.absolute_path(f)
        self.filepath = f
      end
    end

    def set_host(parser)
      parser.on("-u URI", "--uri URI", String, "Hostname of target.") do |u|
        self.host = u
      end
    end

    def set_username(parser)
      parser.on("-l USER", "--logname USER", String, "Username on target.") do |u|
        self.username = u
      end
    end

    def set_passphrase(parser)
      parser.on("-a PASS", "--authentication PASS", String, "Password on target.") do |p|
        self.passphrase = p
      end
    end

    def set_identity(parser)
      parser.on("-i KEY", "--identity KEY", String, "SSH Key for target.") do |i|
        self.identity = i
      end
    end

    def set_port(parser)
      parser.on("-p PORT", "--port PORT", String, "SSH Port.") do |p|
        self.port = p
      end
    end
  end

  def parse_args(args)
    @options = ScriptOptions.new
    @args = OptionParser.new do |parser|
      @options.define_options(parser)
      begin
        parser.parse!(args)
      rescue OptionParser::ParseError => error
        puts error
        puts parser
        exit 3
      end
    end
    @options
  end

  attr_reader :parser, :options
end

def get_status(options, data)
  ret_val = 0
  status = "OK"
  description = "Everything is good."

  if options.critical[:check] == true
    if options.critical[:inclusive] == false
      if options.critical[:range_end] == nil
        if data < options.critical[:range_start]
          ret_val = 2
          status = "CRITICAL"
          description = "Service is in a critical state."
          return ret_val, status, description
        end
      elsif options.critical[:range_start] == nil
        if data < options.critical[:range_end]
          ret_val = 2
          status = "CRITICAL"
          description = "Service is in a critical state."
          return ret_val, status, description
        end
      elsif data < options.critical[:range_start] ||
              data > options.critical[:range_end]
        ret_val = 2
        status = "CRITICAL"
        description = "Service is in a critical state."
        return ret_val, status, description
      end
    elsif options.critical[:inclusive] == true
      if data >= options.critical[:range_start] &&
          data <= options.critical[:range_end]
        ret_val = 2
        status = "CRITICAL"
        description = "Service is in a critical state."
        return ret_val, status, description
      end
    end
  end

  if options.warning[:check] == true
    if options.warning[:inclusive] == false
      if options.warning[:range_end] == nil
        if data < options.warning[:range_start]
          ret_val = 1
          status = "WARNING"
          description = "Service is in a warning state."
          return ret_val, status, description
        end
      elsif options.warning[:range_start] == nil
        if data > options.warning[:range_end]
          ret_val = 1
          status = "WARNING"
          description = "Service is in a warning state."
          return ret_val, status, description
        end
      elsif data < options.warning[:range_start] ||
              data > options.warning[:range_end]
        ret_val = 1
        status = "WARNING"
        description = "Service is in a warning state."
        return ret_val, status, description
      end
    elsif options.warning[:inclusive] == true
      if data >= options.warning[:range_start] &&
          data <= options.warning[:range_end]
        ret_val = 1
        status = "WARNING"
        description = "Service is in a warning state."
        return ret_val, status, description
      end
    end
  end

  return ret_val, status, description
end

ret_val = 3

optionparser = OptParsing.new
options = optionparser.parse_args(ARGV)

if options.verbose
  puts "Exec delay: #{options.delay}"
  puts "Warning thresholds: #{options.warning}"
  puts "Critical thresholds: #{options.critical}"
  puts "Path to file: #{options.filepath}"
  puts "Timeout: #{options.timeout}"
  puts "Hostname: #{options.host}"
  puts "Port: #{options.port}"
  puts "Username: #{options.username}"
  puts "Passphrase #{options.passphrase}"
  puts "SSH Identity: #{options.identity}"
  puts ''
  pp options
  puts "ARGV dump: #{ARGV}", ''
end

if options.warning[:check] == false && options.critical[:check] == false
  puts "UNKNOWN - At least one range needs to be defined."
  exit 3
end

if options.delay
  if options.verbose
    puts "Delaying for #{options.delay} seconds..."
  end
  sleep options.delay
end

data = nil

Net::SSH.start(options.host, options.username,
              :port => options.port,
              :timeout => options.timeout,
              :keys => [options.identity],
              :passphrase => options.passphrase,
              :host_key => "ssh-ed25519",
              :keys_only => true,
              :non_interactive => true,
              :compression => true,
              :config => false
              ) do |ssh|
  if options.verbose
    puts "Trying to contact the server."
  end
  results = ssh.exec!("cat #{options.filepath}")
  data = results.to_i
end

if options.verbose
  puts "Data from file: #{data}"
end

ret_val, service_status, service_description = get_status(options, data)

puts "#{service_status} - #{service_description} | 'output'=#{data};#{options.warning[:string_orig]};#{options.critical[:string_orig]}"

exit ret_val
