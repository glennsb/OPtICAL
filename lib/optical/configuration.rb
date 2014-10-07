# Copyright (c) 2014, Stuart Glenn, OMRF
# Distributed under a BSD 3-Clause
# Full license available in LICENSE.txt distributed with this software

require 'yaml'

class Optical::Configuration
  def self.from_yaml(file_path)
    confy = YAML::load_file(file_path)
    raise "Configuration file missing 'settings' section" unless confy['settings']
    raise "Configguration file mssing 'samples' section" unless confy['samples']
    raise "Configguration file mssing 'samples' section" unless confy['peak_callers']
    samples = {}
    confy['samples'].each do |name,libs|
      samples[name] = Optical::Sample.new(name,libs.map{|l| Optical::Library.new(l)})
    end
    callers = []
    confy['peak_callers'].each do |caller_name,settings|
      settings[:sample_pairs].each do |pair|
        sample_pair = []
        pair.each do |s|
          raise "Invalid configuration to peak call of #{s}, not in sample list" unless samples[s]
          sample_pair << samples[s]
        end
        callers << Optical::PeakCaller.create(settings[:algorithm],caller_name,sample_pair,settings[:opts])
      end
    end
    self.new(samples,callers,confy['settings'])
  end

  attr_reader :output_base, :skip_fastqc, :bwa_threads, :reference_path, :min_map_quality_score,
    :alignment_filter, :remove_duplicates, :skip_alignment, :skip_visualization,
    :default_fragment_size, :wig_step_size, :genome_table_path, :igv_reference

  attr_accessor :verbose

  def initialize(samples,callers,settings = {})
    @verbose = false
    @samples = samples
    @callers = callers
    @reference_path = settings.fetch(:reference)
    @peak_caller = settings.fetch(:peak_caller)
    @qsub_opts = settings.fetch(:qsub_opts,"").split(" ")
    @use_qsub = settings.fetch(:use_qsub,true)
    @skip_fastqc = settings.fetch(:skip_fastqc,false)
    @skip_alignment = settings.fetch(:skip_alignment,false)
    @skip_visualization = settings.fetch(:skip_visualization,false)
    @remove_duplicates = settings.fetch(:remove_duplicates,false)
    @bwa_threads = settings.fetch(:bwa_threads,1)
    self.output_base = settings.fetch(:output_base,Dir.getwd)
    @min_map_quality_score = settings.fetch(:min_map_quality_score,0)
    @default_fragment_size= settings.fetch(:default_fragment_size,0)
    @wig_step_size = settings.fetch(:wig_step_size,20)
    self.alignment_filter = settings.fetch(:alignment_filter,"NullFilter")
    @viz_color_list_path = settings.fetch(:viz_color_list,nil)
    @genome_table_path = get_path_conf(:genome_table_path,settings)
    @igv_reference = get_path_conf(:igv_reference,settings)
  end

  def get_path_conf(key,settings)
    path = settings.fetch(key,nil)
    return nil unless path
    File.expand_path(path) unless nil == path
  end

  def alignment_filter=(filter_klass)
    filter_klass = "Optical::Filters::#{filter_klass}" unless filter_klass =~ /::/
    klass = Kernel.const_get(filter_klass)
    @alignment_filter = klass
  end

  def random_visualization_color()
    unless @color_list
      @color_list = IO.readlines(File.expand_path(@viz_color_list_path)).map{|x| x.chomp}
    end
    if @color_list
      @color_list.sample()
    else
      "54,54,54"
    end
  end

  def cluster_cmd_prefix(opts = {})
    prefix = []
    if @use_qsub
      job_opts = {sync:true, free:1, max:2, wd:'-cwd'}.merge(opts)
      prefix = %W(qsub -b y -j y -V -l virtual_free=#{job_opts[:free]}G,h_vmem=#{job_opts[:max]}G)
      prefix += case job_opts[:wd]
                when '-cwd'
                  %W(-o logs -cwd)
                when /^\//
                  %W(-wd #{job_opts[:wd]} -o #{File.join(Dir.getwd(),"logs")})
                when /^[^\\]+\//
                  %W(-wd #{File.join(Dir.getwd(),job_opts[:wd])} -o #{File.join(Dir.getwd(),"logs")})
                end
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

  def peak_callers()
    return @callers.to_enum unless block_given?
    @callers.each do |c|
      yield c
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
