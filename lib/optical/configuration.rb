# Copyright (c) 2014, Stuart Glenn, OMRF
# Distributed under a BSD 3-Clause
# Full license available in LICENSE.txt distributed with this software

require 'yaml'

class Optical::Configuration
  def self.from_yaml(file_path)
    confy = YAML::load_file(file_path)
    raise "Configuration file missing 'settings' section" unless confy['settings']
    raise "Configguration file mssing 'samples' section" unless confy['samples']
    samples = {}
    confy['samples'].each do |name,libs|
      samples[name] = Optical::Sample.new(name,libs.map{|l| Optical::Library.new(l)})
    end
    self.new(samples,confy['settings'])
  end

  attr_reader :output_base, :skip_fastqc, :bwa_threads, :reference_path

  attr_accessor :verbose

  def initialize(samples,settings = {})
    @verbose = false
    @samples = samples
    @reference_path = settings.fetch(:reference)
    @alignment_filter = settings.fetch(:alignment_filter)
    @peak_caller = settings.fetch(:peak_caller)
    @qsub_opts = settings.fetch(:qsub_opts,"").split(" ")
    @use_qsub = settings.fetch(:use_qsub,true)
    @skip_fastqc = settings.fetch(:skip_fastqc,false)
    @bwa_threads = settings.fetch(:bwa_threads,1)
    self.output_base = settings.fetch(:output_base,Dir.getwd)
  end

  def cluster_cmd_prefix(opts = {})
    prefix = []
    if @use_qsub
      job_opts = {sync:true, free:1, max:2}.merge(opts)
      prefix = %W(qsub -o logs -b y -j y -V -cwd -l virtual_free=#{job_opts[:free]}G,h_vmem=#{job_opts[:max]}G)
      prefix += %w(-sync y) if job_opts.fetch(:sync,false)
      prefix += %W(-N #{job_opts[:name]}) if job_opts[:name] && !job_opts[:name].empty?
      prefix += %W(-pe threaded #{job_opts[:threads]}) if job_opts[:threads]
      prefix += @qsub_opts unless @qsub_opts.empty?
    end
    return prefix
  end

  def samples()
    return @samples.to_enum unless block_given?
    @samples.each do |name,sample|
      yield sample
    end
  end

  def output_base=(new_out)
    @output_base = nil
    return unless new_out

    full_path = File.expand_path(new_out)
    if File.exists?(full_path)
      if !File.directory?(full_path)
        raise "#{new_out} already exists as a non directory"
      elsif !File.writable?(full_path)
        raise "#{new_out} is not writable"
      end
    else
      raise "#{new_out} does not exist"
    end
    @output_base = full_path
  end

  def to_s
<<-EOF
#{@samples.size} sample(s)
reference_path: #{@reference_path}
alignment_filter: #{@alignment_filter}
peak_caller: :#{@peak_caller}
qsub_opts: #{@qsub_opts}
output_base: #{@output_base}
EOF
  end
end
