# Copyright (c) 2014, Stuart Glenn, OMRF
# Distributed under a BSD 3-Clause
# Full license available in LICENSE.txt distributed with this software

class Optical::CLI::Analyze
  def self.command_name
    "analyze"
  end

  def self.desc
    "Run full CHiPSeq analysis pipeline"
  end

  def self.opts(options)
    OptionParser.new do |opts|
      opts.banner = "Usage: optical [global options] #{command_name()} [options] -c conf.yml"

      opts.on("-c","--configuration YAML","Load analysis configuration from YAML") do |conf|
        options.conf_file = File.expand_path(conf)
      end

      opts.on("-o","--outdir DIR","Use Dir as the base output directory") do |conf|
        options.output_base = File.expand_path(conf)
      end

      opts.on("-h","--help","Show this help message") do
        puts opts
        exit(0)
      end
    end
  end

  def initialize(options,args)
    @options = options
    @args = args
    @errs = []
  end

  def run!()
    if !cli_opts_parsed?() || !cli_opts_valid?()
      @errs.each do |e|
        $stderr.puts "Error: #{e}"
      end
      $stderr.puts self.class.opts({}).help()
      exit(1)
    end

    @conf.verbose = @options.verbose

    puts @conf if @conf.verbose

    begin
      chip_analysis = Optical::ChipAnalysis.new($stdout,$stderr,@conf)
      ret = chip_analysis.run
    rescue => err
      $stderr.puts "Failure in analysis: #{err} (#{err.backtrace.first})"
      exit(1)
    end
    exit(0) if ret
    $stderr.puts "Failure in analysis: #{chip_analysis.errs.join("\n")}"
    exit(1)
  end

  def cli_opts_parsed?()
    opts = self.class.opts(@options)
    begin
      opts.parse!(@args)
    rescue => err
      @errs << err.to_s
      return false
    end

    return true
  end

  def cli_opts_valid?()
    loaded_config?() &&
    output_base_valid?()
  end

  def loaded_config?()
    begin
      @conf = Optical::Configuration::from_yaml(@options.conf_file)
    rescue => err
      @errs << "Error loading analysis configuration file: #{err} (#{err.backtrace.first})"
      return false
    end
    return true
  end

  def output_base_valid?()
    if nil != @options.output_base && @options.output_base != "" then
      begin
        Dir.mkdir(@options.output_base) unless File.exist?(@options.output_base)
        @conf.output_base = @options.output_base
      rescue => err
        @errs << "Error with output base directory: #{err} (#{err.backtrace.first})"
        return false
      end
    end
    return true
  end
end
