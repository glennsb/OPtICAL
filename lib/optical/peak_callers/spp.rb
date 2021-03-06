# Copyright (c) 2014, Stuart Glenn, OMRF
# Distributed under a BSD 3-Clause
# Full license available in LICENSE.txt distributed with this software

class Optical::PeakCaller::Spp < Optical::PeakCaller

  attr_accessor :region_peak_path

  def find_peaks(output_base,conf)
    if already_called?(output_base,conf)
      return true
    end
    [@treatments[0], @controls[0]].each do |s|
      unless sample_ready?(s)
        @errors << "The sample #{s} is not ready, the bam (#{s.analysis_ready_bam}) is missing"
        return false
      end
    end
    return false unless run_spp(output_base,conf)

    @region_peak_path = File.join(output_base,
                                  "#{part_name(@treatments[0])}_VS_#{part_name(@controls[0])}.regionPeak.gz")

    return false unless uncompress_peaks_file(output_base,conf)

    @region_peak_path.sub!(/\.gz$/,'')
    @cross_corelation_plot_path = output_base + "#{part_name(@treatments[0])}.pdf"

    @peak_bed_path = create_peak_bed(@region_peak_path,@conf)

    return calculate_cross_correlation(output_base,conf)
  end

  def peak_path()
    [@region_peak_path]
  end

  def peak_bed_path()
    if @peak_bed_path && File.exists?(@peak_bed_path)
      return [@peak_bed_path]
    end
    @peak_bed_path = create_peak_bed(@region_peak_path)
    return [@peak_bed_path]
  end

  def already_called?(output_base,conf)
    region_peak_path = File.join(output_base,
                                  "#{part_name(@treatments[0])}_VS_#{part_name(@controls[0])}.regionPeak")

    if File.size?(region_peak_path)
      @region_peak_path = region_peak_path
      @cross_corelation_plot_path = output_base + "#{part_name(@treatments[0])}.pdf"
      @peak_bed_path = @region_peak_path.sub(/\.([^.]+$)/,".bed")
      return true
    end
  end

  private

  def part_name(p)
    File.basename(p.analysis_ready_bam.to_s,".bam")
  end

  def uncompress_peaks_file(output_base,conf)
    cmd = conf.cluster_cmd_prefix(wd:output_base, free:4, max:8, sync:true, name:"#{safe_name()}") +
      %W(gunzip #{File.basename(region_peak_path).shellescape})

    puts cmd.join(" ") if conf.verbose
    unless system(*cmd)
      @errors << "Failed to uncompress region peaks for #{self}: #{$?.exitstatus}"
      return false
    end
    return true
  end

  def run_spp(output_base,conf)
    spp = if @treatments[0].analysis_ready_bam.dupes_removed
            "run_spp_nodups.R"
          else
            "run_spp.R"
          end
    cmd = conf.cluster_cmd_prefix(wd:output_base, free:5, max:16, sync:true, name:"spp_#{safe_name()}") +
      %W(#{spp} -c=#{bam_path(@treatments[0].analysis_ready_bam,conf).shellescape}
         -i=#{bam_path(@controls[0].analysis_ready_bam,conf).shellescape} -odir=. -savr -savp -rf) + @cmd_args

    puts cmd.join(" ") if conf.verbose
    unless system(*cmd)
      @errors << "Failed to execute spp for #{self}: #{$?.exitstatus}"
      return false
    end
    return true
  end
end
