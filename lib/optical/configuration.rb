# Copyright (c) 2014, Stuart Glenn, OMRF
# Distributed under a BSD 3-Clause
# Full license available in LICENSE.txt distributed with this software

require 'yaml'

class Optical::Configuration
  def self.from_yaml(file_path)
    confy = YAML::load_file(file_path)
    raise "Configuration file missing 'settings' section" unless confy['settings']
    raise "Configuration file mssing 'samples' section" unless confy['samples']
    raise "Configuration file mssing 'peak_callers' section" unless confy['peak_callers']
    samples = {}
    confy['samples'].each do |name,libs|
      samples[name] = Optical::Sample.new(name,create_libs(libs))
    end
    callers = []
    confy['peak_callers'].each do |caller_name,settings|
      settings[:comparisons].each do |comp|
        treatments = comp[:treatments].split(/\s+/).map do |s|
          raise "Invalid sample #{s} in treatment section for #{caller_name}" unless samples.has_key?(s)
          samples[s]
        end
        controls = (comp[:controls]||"").split(/\s+/).map do |s|
          raise "Invalid sample #{s} in control section for #{caller_name}" unless samples.has_key?(s)
          samples[s]
        end
        callers << Optical::PeakCaller.create(settings[:algorithm],caller_name,treatments,
                                              controls,settings[:opts])
      end
    end
    self.new(samples,callers,confy['settings'])
  end

  def self.create_libs(sample)
    libs = []
    return libs unless Array == sample.class
    if Hash == sample.first.class
      #old style listing all libs inline under the sample
      parts = sample.map {|l| Optical::LibraryPart.new(l[:run],l[:lane],l[:inputs],l[:downsample])}
      libs = [Optical::Library.new(parts)]
    else
      #new style listing separate libraries under the sample
      libs = sample.map do |l|
        Optical::Library.new(l.map {|p| Optical::LibraryPart.new(p[:run],p[:lane],p[:inputs],p[:downsample]) } )
      end
    end
    return libs
  end

  attr_reader :output_base, :bwa_threads, :reference_path, :min_map_quality_score,
    :alignment_filter, :remove_duplicates,
    :default_fragment_size, :wig_step_size, :genome_table_path, :igv_reference,
    :gene_peak_neighbor_distance, :ucsc_refflat_path, :idr_script,
    :idr_plot_script, :alignment_masking_bed_path

  attr_accessor :verbose

  def initialize(samples,callers,settings = {})
    @verbose = false
    @samples = samples
    @callers = callers
    @reference_path = settings.fetch(:reference)
    @qsub_opts = settings.fetch(:qsub_opts,"").split(" ")
    @use_qsub = settings.fetch(:use_qsub,true)
    @remove_duplicates = settings.fetch(:remove_duplicates,false)
    @bwa_threads = settings.fetch(:bwa_threads,1)
    self.output_base = settings.fetch(:output_base,Dir.getwd)
    @min_map_quality_score = settings.fetch(:min_map_quality_score,0)
    @default_fragment_size= settings.fetch(:default_fragment_size,0)
    @wig_step_size = settings.fetch(:wig_step_size,20)
    self.alignment_filter = settings.fetch(:alignment_filter,"NullFilter")
    @viz_color_list_path = settings.fetch(:viz_color_list,nil)
    @genome_table_path = get_path_conf(:genome_table_path,settings)
    @ucsc_refflat_path = get_path_conf(:ucsc_refflat,settings)
    @idr_script = get_path_conf(:idr_script,settings)
    @idr_plot_script = get_path_conf(:idr_plot_script,settings)
    @igv_reference = get_path_conf(:igv_reference,settings)
    @alignment_masking_bed_path = get_path_conf(:alignment_masking_bed,settings)
    @gene_peak_neighbor_distance = settings.fetch(:gene_peak_neighbor_distance,10000)
  end

  def get_path_conf(key,settings)
    path = settings.fetch(key,nil)
    return nil unless path
    File.expand_path(path)
  end

  def alignment_filter=(filter_klass)
    filter_klass = "Optical::Filters::#{filter_klass}" unless filter_klass =~ /::/
    klass = filter_klass.split("::").inject(Object) {|o,c| o.const_get c}
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
qsub_opts: #{@qsub_opts}
output_base: #{@output_base}
EOF
  end
end
