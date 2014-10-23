# Copyright (c) 2014, Stuart Glenn, OMRF
# Distributed under a BSD 3-Clause
# Full license available in LICENSE.txt distributed with this software

class Optical::PeakCaller

  include Optical::Checkpointable

  Dir[File.join( File.dirname(__FILE__),"peak_callers","*.rb")].each do |rb|
    require rb
  end

  def self.create(algo,name,treatments,controls,opts)
    raise InvalidArgument, "No treatments" unless treatments && treatments.size > 0
    raise InvalidArgument, "No controls" unless controls && controls.size > 0
    klass = "Optical::PeakCaller::#{algo}" unless klass =~ /::/
    klass = klass.split("::").inject(Object) {|o,c| o.const_get c}
    klass.new(name,treatments,controls,opts)
  end

  attr_reader :cmd_args, :name, :treatments, :controls

  def initialize(name,treatments,controls,opts)
    @name = name
    @cmd_args = (opts[:args]||"").split(/ /)
    @treatments = treatments
    @controls = controls
    @errors = []
  end

  def to_s
    "#{@name} of #{@treatments[0]} vs #{@controls[0]}"
  end

  def safe_name
    "#{@name.tr(" ",'_').tr("/","_")}_#{@treatments[0].safe_name}_vs_#{@controls[0].safe_name}"
  end

  def find_peaks(output_base,conf)
    @errors << "The subclass did not define how to find peaks"
    return false
  end

  def calculate_cross_correlation(output_base,conf)
    return true if File.exists?( File.basename(@treatments[0].analysis_ready_bam.path,"bam") + "pdf" )
    spp = if @treatments[0].analysis_ready_bam.dupes_removed
            "run_spp_nodups.R"
          else
            "run_spp.R"
          end
    cmd = conf.cluster_cmd_prefix(wd:output_base, free:4, max:8, sync:true, name:"crosscorr_#{safe_name()}") +
      %W(#{spp} -c=#{@treatments[0].analysis_ready_bam.path.shellescape} -rf -savp -out=strand_cross_correlation.txt)
    puts cmd.join(" ") if conf.verbose
    unless system(*cmd)
      @errors << "Failed to execute xcorspp for #{self}: #{$?.exitstatus}"
      return false
    end
    return true
  end

  def trim_peaks!(limit,conf)
    return unless peak_path() && File.exists?(peak_path())
    return unless limit > 0
    base = File.dirname(peak_path())
    out = File.basename(peak_path())+"_#{limit}_limited.tmp"
    cmd = conf.cluster_cmd_prefix(wd:base, free:1, max:2, sync:true, name:"sort_peaks_#{safe_name()}") +
      ["sort -k8 -n -r #{File.basename(peak_path()).shellescape} | head -n #{limit} | sort -k1,1 -k2,2n -k3,3n > #{out.shellescape}"]
    puts cmd.join(" ") if conf.verbose
    unless system(*cmd)
      @errors << "Failure in limiting #{peak_path()} to #{limit} peaks"
      return false
    end
    File.delete(peak_path())
    File.rename(File.join(File.dirname(peak_path()),out),peak_path())
    return true
  end


  def num_peaks()
    unless @num_peaks
      @num_peaks = 0
      IO.foreach(peak_path()) do
        @num_peaks+=1
      end
    end
    return @num_peaks
  end

  def treatment_samples
    return @treatments.to_enum unless block_given?
    @treatments.each do |p|
      yield p
    end
  end

  def control_samples
    return @controls.to_enum unless block_given?
    @controls.each do |p|
      yield p
    end
  end

  def sample_ready?(s)
    s.analysis_ready_bam && File.exists?(s.analysis_ready_bam.path)
  end

  def error()
    @errors.join("\n")
  end

  def has_errors?()
    @errors.size > 0
  end

  def add_error(msg)
    @errors << msg
  end
end
