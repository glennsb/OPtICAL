# Copyright (c) 2015, Stuart Glenn, OMRF
# Distributed under a BSD 3-Clause
# Full license available in LICENSE.txt distributed with this software

require 'fileutils'

class Optical::PeakCaller::Fseq < Optical::PeakCaller

  TMP_BED_SUFFIX = "-tmp.bed"
  NARROW_SUFFIX = ".narrowPeak"

  attr_reader :peak_bed_path

  def find_peaks(output_base,conf)
    (@treatments).each do |s|
      unless sample_ready?(s)
        @errors << "the sample #{s} is not ready, the bam (#{s.analysis_ready_bam}) is missing"
        return false
      end
    end
    return run_fseq(output_base,conf) &&
      calculate_cross_correlation(output_base,conf)
  end

  def peak_path()
    [@peak_bed_path]
  end

  def peak_bed_path()
    [@peak_bed_path]
  end

  private

  def run_fseq(output_base,conf)
    cleanup(output_base,conf) &&
    bam_to_bed(output_base,conf) &&
    call_peaks(output_base,conf) &&
    merge_results(output_base,conf) &&
    cleanup(output_base,conf)
  end

  def bam_to_bed(output_base,conf)
    basename = File.basename(@treatments[0].analysis_ready_bam.path,".bam")
    cmd = conf.cluster_cmd_prefix(wd:output_base, free:4, max:8, sync:true, name:"bam2bed_#{safe_name()}") +
      %W(/bin/bash -o pipefail -o errexit -c)
    cmd << "\"bamToBed -i #{@treatments[0].analysis_ready_bam.path} > #{basename}#{TMP_BED_SUFFIX}\""
    puts cmd.join(" ") if conf.verbose
    unless system(*cmd)
      @errors << "Failed to convert bam to bed for #{self}:#{__FILE__}:#{__LINE__}:#{$?.exitstatus}"
      return false
    end
    return true
  end

  def call_peaks(output_base,conf)
    basename = File.basename(@treatments[0].analysis_ready_bam.path,".bam")
    Dir.mkdir(File.join(output_base,basename))
    cmd = conf.cluster_cmd_prefix(wd:output_base, free:4, max:32, sync:true, name:"fseq_#{safe_name()}") +
      %W(fseq #{basename}#{TMP_BED_SUFFIX} -of npf -o #{basename}) + @cmd_args
    puts cmd.join(" ") if conf.verbose
    unless system(*cmd)
      @errors << "Failed to convert fseq for #{self}: #{$?.exitstatus}"
      return false
    end
    return true
  end

  def merge_results(output_base,conf)
    basename = File.basename(@treatments[0].analysis_ready_bam.path,".bam")
    cmd = conf.cluster_cmd_prefix(wd:output_base, free:4, max:40, sync:true, name:"fseq_#{safe_name()}") +
      %W(/bin/bash -o pipefail -o errexit -c)
    cmd << "\"cat #{basename}/*.npf > #{basename}#{NARROW_SUFFIX}\""
    puts cmd.join(" ") if conf.verbose
    unless system(*cmd)
      @errors << "Failed to convert merge fseq results for #{self}: #{$?.exitstatus}"
      return false
    end
    @peak_bed_path = File.join(output_base,basename+NARROW_SUFFIX)
    return true
  end

  def cleanup(output_base,conf)
    basename = File.basename(@treatments[0].analysis_ready_bam.path,".bam")
    FileUtils.remove_dir(File.join(output_base,basename),true)
    f = File.join(output_base,basename + TMP_BED_SUFFIX)
    File.unlink(f) if File.exists?(f)
    return true
  end
end
