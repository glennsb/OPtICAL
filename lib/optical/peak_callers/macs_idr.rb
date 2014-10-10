# Copyright (c) 2014, Stuart Glenn, OMRF
# Distributed under a BSD 3-Clause
# Full license available in LICENSE.txt distributed with this software

class Optical::PeakCaller::MacsIdr < Optical::PeakCaller

  def initialize(name,treatments,controls,opts)
    super
    @opts = opts
    @treatments_name = (@opts.delete(:treatment_name) || @treatments.first.safe_name).tr(" ",'_').tr("/","_")
    @controls_name = (@opts.delete(:control_name) || @controls.first.safe_name).tr(" ",'_').tr("/","_")
  end

  def to_s
    "#{@name} of #{@treatments_name} vs #{@controls_name}"
  end

  def safe_name
    "#{@name}_#{@treatments_name}_vs_#{@controls_name}".tr(" ",'_').tr("/","_")
  end

  def find_peaks(output_base,conf)
    # Alright IDR peak finding game plane of things TOOD
    # merge all controls to CONTROL
    control_rep_bam = pool_control_replicates(output_base,conf)
    return false unless control_rep_bam
    control = Optical::Sample.new("#{@controls_name}_pooled",[])
    control.analysis_ready_bam=control_rep_bam

    peakers = @treatments.map do |t|
      # peak each treatment against CONTROL
      Macs.new(@name,[t],[control],@opts)
    end

    errs_mutex = Mutex.new()
    on_error = Proc.new do |msg|
      errs_mutex.synchronize { @errors << msg }
    end

    peakers_mutex = Mutex.new()
    # split each treatment to 2 pseudo replicates, peak each against CONTROL
    problem = !Optical.threader(@treatments,on_error) do |t|
      pseudo_replicates = t.create_pseudo_replicates(2,output_base,conf)
      if pseudo_replicates && 2 == pseudo_replicates.size
        pseudo_replicates.each do |pr|
          peakers_mutex.synchronize { peakers << Macs.new(@name,[pr],[control],@opts) }
        end
      else
        on_error.call("Failed to make pseudo replicates for #{t}")
        false
      end
    end
    return false if problem

    if @treatments.size > 1
      # merge all treatments to TREATMENT
      # peak TREAMENT against CONTROL
      # split TREAMENT to 2 pseudo replicates, peak each against CONTROL
    end


    Optical.threader(peakers,on_error) do |p|
      puts "Calling peaks for #{p}" if conf.verbose
      #p.find_peaks(output_base,conf)
    end

    # Do we need/want to save this pooled bam?
    File.delete(control.analysis_ready_bam.path) if File.exists?(control.analysis_ready_bam.path)
    return true
  end

  private
  def pool_control_replicates(output_base,conf)
    pooled_path = File.join(Dir.getwd,output_base,"#{@controls_name}_pooled.bam")
    if 1 == @controls.size then
      require 'fileutils'
      FileUtils.ln_s(@controls[0].analysis_ready_bam.path,pooled_path) unless File.exists?(pooled_path)
    else
      return nil unless merge_bams_to(@controls.map{|c| c.analysis_ready_bam.path},pooled_path,conf)
    end
    b = Optical::Bam.new(pooled_path,@controls[0].analysis_ready_bam.paired?)
    b.fragment_size = @controls.reduce(0) {|sum,c| sum+=c.analysis_ready_bam.fragment_size}/@controls.size
    return b
  end

  def merge_bams_to(inputs,output,conf)
    cmd = conf.cluster_cmd_prefix(free:8, max:56, sync:true, name:"merge_#{name}") +
      %W(picard MergeSamFiles OUTPUT=#{output} VALIDATION_STRINGENCY=LENIENT MAX_RECORDS_IN_RAM=6000000
         COMPRESSION_LEVEL=8 USE_THREADING=True ASSUME_SORTED=true SORT_ORDER=coordinate) +
         inputs.map {|l| "INPUT=#{l}" }
    unless !conf.skip_peak_calling
      puts cmd.join(" ") if conf.verbose
      unless system(*cmd)
        @errors << "Failure in merging a pool of bams in #{name} #{$?.exitstatus}"
        return false
      end
    end
    return true
  end
end
