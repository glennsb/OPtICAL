# Copyright (c) 2014, Stuart Glenn, OMRF
# Distributed under a BSD 3-Clause
# Full license available in LICENSE.txt distributed with this software

class Optical::CLI::PeakToBed

  def self.command_name
    "peakToBed"
  end

  def self.desc
    "Convert a regionpeak or encodepeak file to a bed file"
  end

  def self.opts(options)
    OptionParser.new do |opts|
      opts.banner = "Usage: optical [global options] #{command_name()} [options] -p input.peak"

      opts.on("-p","--peakfile FILE","The input peak file to translate") do |p|
        options.peak_path = File.expand_path(p)
      end

      opts.on("-o","--out FILE","Save output bed to FILE, defaults to STDOUT") do |out|
        options.output_path = File.expand_path(out)
      end

      opts.on("-c","--color N,N,N",String,"Specify a hex color string, defaults to random") do |conf|
        options.color = conf
      end

      opts.on("-f","--force","Force the run, overwriting the output if it already exists") do
        options.overwrite = true
      end

      opts.on("-h","--help","Show this help message") do
        puts opts
        exit(0)
      end
    end
  end

  def initialize(options,args)
    @options = options
    @options.color = "#{(0..255).to_a.sample},#{(0..255).to_a.sample},#{(0..255).to_a.sample}"
    @options.overwrite = false
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

    begin
      ret = convert_peak_to_bed()
    rescue => err
      $stderr.puts "Failure: #{err} (#{err.backtrace.first})"
      exit(1)
    end
    exit(0) if ret
    exit(1)
  end

  def convert_peak_to_bed()
    o = @options.output
    name = if $stdout == o
             File.basename(@options.peak_path).sub(/\.([^.]+$)/,".bed")
           else
             File.basename(@options.output_path)
           end
    o.puts "track name=\"#{name}\" description=\"#{name}\" visibility=full color=#{@options.color}"
    IO.foreach(@options.peak_path) do |line|
      parts = line.chomp.split(/\t/)
      begin
        o.puts "#{parts[0]}\t#{parts[1]}\t#{parts[2]}\t#{parts[8]}"
      rescue Errno::EPIPE
        break
      end
    end
    return true
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
    peak_readable?() &&
    output_valid?()
  end

  def peak_readable?()
    unless @options.peak_path
      @errs << "Missing peak argument"
      return false
    end
    unless File.file?(@options.peak_path) && File.readable?(@options.peak_path)
      @errs << "Peak, #{@options.peak_path} is not a readable file"
      return false
    end
    return true
  end

  def output_valid?()
    if nil != @options.output_path && @options.output_path != "" then
      if File.exists?(@options.output_path) && !@options.overwrite
        @errs << "Output file #{@options.output_path} already exists, refusing to overwrite it"
        return false
      end
      base = File.dirname(@options.output_path)
      unless base && Dir.exists?(base) && File.writable?(base)
        @errs << "Unable to write to named output location, #{base}"
        return false
      end
      @options.output = File.open(@options.output_path,"w")
    else
      @options.output = $stdout
    end
    return true
  end
end
