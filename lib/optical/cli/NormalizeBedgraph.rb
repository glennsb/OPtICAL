# Copyright (c) 2014, Stuart Glenn, OMRF
# Distributed under a BSD 3-Clause
# Full license available in LICENSE.txt distributed with this software

class Optical::CLI::NormalizeBedgraph

  def self.command_name
    "normalizeBedgraph"
  end

  def self.desc
    "Normalize a bedgraph file based on a given count"
  end

  def self.opts(options)
    OptionParser.new do |opts|
      opts.banner = "Usage: optical [global options] #{command_name()} [options] -b input.bedgraph"

      opts.on("-b","--bedgraph FILE","The input bedgraph file to translate") do |bg|
        options.bedgraph_path = File.expand_path(bg)
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
      ret = normalize_bedgraph()
    rescue => err
      $stderr.puts "Failure: #{err} (#{err.backtrace.first})"
      exit(1)
    end
    exit(0) if ret
    exit()
  end

  # TODO make this a classy object
  def normalize_bedgraph()
    o = @options.output
    IO.foreach(@options.bedgraph_path) do |line|
      if $. == 1
        o.print line.gsub(/raw/,'normalized')
      else
        (chr,start,stop,score) = line.chomp.split(/\t/)
        score = (score.to_i/@options.count)*1000000.0
        o.puts "#{chr}\t#{start}\t#{stop}\t#{format("%.2f",score)}"
      end
    end
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
    bedgraph_readable?() &&
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

  def bedgraph_readable?()
    unless @options.bedgraph_path
      @errs << "Missing bedgraph argument"
      return false
    end
    unless File.file?(@options.bedgraph_path) && File.readable?(@options.bedgraph_path)
      @errs << "Bedgraph, #{@options.bedgraph_path} is not a readable file"
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
