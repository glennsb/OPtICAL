# Copyright (c) 2015, Stuart Glenn, OMRF
# Distributed under a BSD 3-Clause
# Full license available in LICENSE.txt distributed with this software

require 'open3'

class Optical::CLI::Spot

  def self.command_name
    "spot"
  end

  def self.desc
    "Get SPOT score using hotspot"
  end

  def self.opts(options)
    OptionParser.new do |opts|
      opts.banner = "Usage: optical [global options] #{command_name()} [-o DIR] [-i INPUT] [-t TAG...] -c CONF -t TAG"

      opts.on("-t","--tag FILE","The treatment tag bam") do |o|
        options.tag_paths ||= []
        options.tag_paths << File.expand_path(o)
      end

      opts.on("-o","--out DIR","Save the output under DIR, defaults to CWD") do |o|
        options.output_prefix = File.expand_path(o)
      end

      opts.on("-i","--input FILE","The input bam, not used if not given") do |o|
        options.input_path = File.expand_path(o)
      end

      opts.on("-c","--conf FILE","The base hotspot config file") do |o|
        options.conf_path = File.expand_path(o)
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
      ret = calculate_spot()
    rescue => err
      $stderr.puts "Failure: #{err} (#{err.backtrace.first})"
      exit(1)
    end
    if ret
      additional_cleanup()
      exit(0)
    end
    exit(1)
  end

  def additional_cleanup()
    paths = @options.tag_paths
    paths << @options.input_path if @options.input_path
    paths.each do |p|
      base = File.basename(p,".bam")
      %w(bed.starch lib.filter.txt.counts).each do |ext|
        f = File.join(@options.output_prefix,base) + ".#{ext}"
        begin
          File.delete(f) if File.exists?(f)
        rescue
        end
      end
    end
  end

  def calculate_spot()
    if run_hotspot()
      return report_spot() if has_spot_output()
    end
    $stderr.puts "Failure running hotspot"
    return false
  end

  def report_spot()
    read_header = false
    had_error = true
    IO.foreach(spotfile_path()) do |line|
      if $. > 2
        $stderr.puts "Incorrect spot result file format"
        $stderr.puts "Read too many lines before finding header and data"
        had_error = true
        break
      elsif read_header
        spot = line.chomp.split(/\s+/).last
        puts spot
        had_error = false
        break
      elsif line =~ /\s*total tags\s+/
        read_header = true
      end
    end
    return !had_error
  end

  def has_spot_output()
    if File.exists?(spotfile_path()) && File.size(spotfile_path()) > 0
      return true
    end
    $stderr.puts "Unable to find spot output in #{spotfile_path()}"
    return false
  end

  def run_hotspot()
    cmd = %W(runhotspot -m spot -o . -c #{@options.conf_path})
    if @options.input_path
      cmd += %W(-i #{@options.input_path})
    end
    cmd += @options.tag_paths
    puts cmd.join(" ") if @options.verbose
    exit_status = nil
    ::Open3.popen3(*cmd,{:chdir => @options.output_prefix, :err => [:child,:out]}) do |stdin, stdout, stderr, wait_thr|
      stdin.close
      while l = stdout.gets
        $stderr.puts "HOTSPOT: #{l.chomp}" if @options.verbose
      end
      exit_status = wait_thr.value
    end
    return 0 == exit_status.exitstatus
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
    tags_readable?() &&
    input_readable?() &&
    output_valid?() &&
    conf_readable?()
  end

  def tags_readable?()
    unless @options.tag_paths && @options.tag_paths.size > 0
      @errs << "Missing tag(s) argument"
      return false
    end
    if ( (@options.tag_paths.map{|f| File.file?(f) && File.readable?(f)}).any?{|s| !s})
      @errs << "Tag(s) is missing or unreadable"
      return false
    end
    return true
  end


  def input_readable?()
    unless @options.input_path
      return true
    end
    unless File.file?(@options.input_path) && File.readable?(@options.input_path)
      @errs << "Input bam, #{@options.input_path} is not a readable file"
      return false
    end
    return true
  end

  def conf_readable?()
    unless @options.conf_path
      @errs << "Missing conf option"
      return false
    end
    unless File.file?(@options.conf_path) && File.readable?(@options.conf_path)
      @errs << "conf file, #{@options.conf_path} is not a readable file"
      return false
    end
    return true
  end

  def output_valid?()
    if nil == @options.output_prefix || "" == @options.output_prefix
      @options.output_prefix = File.expand_path(".")
    end
    unless Dir.exists?(@options.output_prefix) && File.writable?(@options.output_prefix)
      @errs << "Unable to write to named output location, #{base}"
      return false
    end
    if File.exists?(spotfile_path())
      @errs << "An existing #{spotfile_path()} result file exists in #{@options.output_prefix}"
      return false
    end
    return true
  end

  def spotfile_path()
    base = File.basename(@options.tag_paths.first,".bam")
    File.join(@options.output_prefix,base) + ".spot.out"
  end
end
