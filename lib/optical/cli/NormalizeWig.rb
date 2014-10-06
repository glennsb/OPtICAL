# Copyright (c) 2014, Stuart Glenn, OMRF
# Distributed under a BSD 3-Clause
# Full license available in LICENSE.txt distributed with this software

class Optical::CLI::NormalizeWig

  def self.command_name
    "normalizeWig"
  end

  def self.desc
    "Normalize a wig file based on a given count"
  end

  def self.opts(options)
    OptionParser.new do |opts|
      opts.banner = "Usage: optical [global options] #{command_name()} [options] -w input.wig"

      opts.on("-w","--wig FILE","The input wig file to translate") do |bg|
        options.wig_path = File.expand_path(bg)
      end

      opts.on("-o","--out FILE","Save output wig to FILE, defaults to STDOUT") do |out|
        options.output_path = File.expand_path(out)
      end

      opts.on("-c","--count SIZE",Integer,"The normalize count (number of reads or peaks") do |conf|
        options.count = conf.to_i
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

    begin
      ret = normalize_wig()
    rescue => err
      $stderr.puts "Failure: #{err} (#{err.backtrace.first})"
      exit(1)
    end
    exit(0) if ret
    exit(1)
  end

  # TODO make this a classy object
  def normalize_wig()
    o = @options.output
    delim = /\t/
    IO.foreach(@options.wig_path) do |line|
      if $. == 1
        o.print line.gsub(/raw/,'normalized')
      else
        (start,score) = line.split(delim)
        if start && score
          score = score.to_i
          next unless score >= 1
          score = (score/@options.count)*10000000.0
          o.puts "#{start}\t#{format("%.2f",score)}"
        else
          o.print line
        end
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
    wig_readable?() &&
    output_valid?() && count_given?()
  end

  def count_given?()
    unless @options.count && @options.count > 0
      @errs << "Invalid count argument"
      return false
    end
    @options.count = @options.count.to_f
    return true
  end

  def wig_readable?()
    unless @options.wig_path
      @errs << "Missing wig argument"
      return false
    end
    unless File.file?(@options.wig_path) && File.readable?(@options.wig_path)
      @errs << "Wig, #{@options.wig_path} is not a readable file"
      return false
    end
    return true
  end

  def output_valid?()
    if nil != @options.output_path && @options.output_path != "" then
      if File.exists?(@options.output_path)
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
