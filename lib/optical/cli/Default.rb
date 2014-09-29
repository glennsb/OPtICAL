# Copyright (c) 2014, Stuart Glenn, OMRF
# Distributed under a BSD 3-Clause
# Full license available in LICENSE.txt distributed with this software

class Optical::CLI::Default
  def self.command_name
    "_default"
  end

  def self.desc
    "The global options"
  end

  def self.opts(options)
    OptionParser.new do |opts|
      opts.banner = "Usage: optical [global options] COMMAND [command specific options]"

      opts.on("-h","--help","Show this help message") do
        options.show_global_help = true
      end

      opts.on("-v","--verbose","Increase verbosity") do
        options.verbose = true
      end

      opts.on("-V","--version","Print version information") do
        puts <<-EOF
optical - OMRF Pipeline for CHiPSeq Analysis
Version: #{Optical::VERSION}
Released: #{Optical::RELEASEDATE}
        EOF
        exit(0)
      end
    end
  end
end
