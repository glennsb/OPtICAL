# Copyright (c) 2014, Stuart Glenn, OMRF
# Distributed under a BSD 3-Clause
# Full license available in LICENSE.txt distributed with this software

require 'optparse'
require 'ostruct'

class Optical::CLI
  attr_reader :args

  def initialize(args)
    @args = args.dup
    @options = OpenStruct.new()
  end

  def run()
    commands = get_commands()
    default_opts = Optical::CLI::Default.opts(@options)
    default_opts.order!(@args)

    if @options.show_global_help
      show_global_help(default_opts,commands,$stdout,0)
    end

    command = commands[@args.shift]
    if command
      command = command.new(@options,@args)
      command.run!()
    else
      show_global_help($stderr,1)
    end
  end

  private

  def show_global_help(default_opts,commands,out=$stderr,exit_val=0)
    out.puts "Missing command\n"
    out.puts default_opts.help
    out.puts "\nKnown commands are"
    commands.each do |name,klass|
      out.puts "\t#{name} - #{klass.desc}" unless Optical::CLI::Default == klass
    end
    exit(exit_val)
  end

  def get_commands()
    commands = {}
    Dir[File.join(File.dirname(__FILE__),"cli","*.rb")].each do |rb|
      require rb
      klass = Kernel.const_get("Optical::CLI::#{File.basename(rb,".rb")}")
      commands[klass.command_name] = klass
    end
    commands
  end
end
