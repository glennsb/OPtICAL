# Copyright (c) 2014, Stuart Glenn, OMRF
# Distributed under a BSD 3-Clause
# Full license available in LICENSE.txt distributed with this software

class Optical::CLI::BedgraphToWig
  DEFAULT_STEP_SIZE = 50

  def self.command_name
    "bedgraphToWig"
  end

  def self.desc
    "Convert a bedgraph file to a wig file"
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

      opts.on("-s","--step-size SIZE",Integer,"Step size, defaults to #{DEFAULT_STEP_SIZE}") do |conf|
        options.step_size = conf.to_i
      end

      opts.on("-c","--color N,N,N",String,"Specify a hex color string, defaults to random") do |conf|
        options.color = conf
      end

      opts.on("-h","--help","Show this help message") do
        puts opts
        exit(0)
      end
    end
  end

  def initialize(options,args)
    @options = options
    @options.step_size = DEFAULT_STEP_SIZE
    @options.color = "#{(0..255).to_a.sample},#{(0..255).to_a.sample},#{(0..255).to_a.sample}"
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
      ret = convert_bed_graph_to_wig()
    rescue => err
      $stderr.puts "Failure: #{err} (#{err.backtrace.first})"
      exit(1)
    end
    exit(0) if ret
    exit(1)
  end

  # TODO make this a classy object
  def convert_bed_graph_to_wig()
    o = @options.output
    name = File.basename(@options.bedgraph_path,".bedgraph")+".wig"
    last_chr = nil
    last_pos = nil
    IO.foreach(@options.bedgraph_path) do |line|
      if $. == 1
        o.puts "track type=wiggle_0 name=\"#{name}\" description=\"#{name}\" visibility=full color=#{@options.color}"
      else
        (chr,start,stop,score) = line.chomp.split(/\t/)
        start = start.to_i
        stop = stop.to_i
        if last_chr != chr
          o.puts "variableStep chrom=#{chr} span=1"
          last_pos = nil
        end
        while start <= stop
          pos = start+1
          if last_pos != pos
            o.puts "#{pos}\t#{score}"
            last_pos = pos
          end
          start+=@options.step_size
        end
        last_chr = chr
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
    bedgraph_readable?() &&
    output_valid?()
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
