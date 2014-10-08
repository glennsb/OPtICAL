# Copyright (c) 2014, Stuart Glenn, OMRF
# Distributed under a BSD 3-Clause
# Full license available in LICENSE.txt distributed with this software

class Optical::PeakCaller::Macs < Optical::PeakCaller
  MACS_OUTPUT_SUFFICES = {control_bdg:"control_lambda.bdg", model_r:"model.r", model_pdf:"model.pdf",
    peak_bed:"peaks.bed", encode_peak:"peaks.encodePeak", peak_xls:"peaks.xls",
    summit_bed:"summits.bed", pileup:"treat_pileup.bdg"}

  def find_peaks(output_base,conf)
    output_base = File.join(output_base,safe_name)
    @pair.each do |s|
      unless sample_ready?(s)
        @errors << "The sample #{s} is not ready, the bam is missing"
        return false
      end
    end
    if run_macs(output_base,conf)
      @control_bdg_path = full_output_base + MACS_OUTPUT_SUFFICES[:control_bdg]
      @peak_bed_path = full_output_base + MACS_OUTPUT_SUFFICES[:peak_bed]
      @encode_peak_path = full_output_base + MACS_OUTPUT_SUFFICES[:encode_peak]
      @peak_xls_path = full_output_base + MACS_OUTPUT_SUFFICES[:peak_xls]
      @summit_bed_path = full_output_base + MACS_OUTPUT_SUFFICES[:summit_bed]
      @pileup_path = full_output_base + MACS_OUTPUT_SUFFICES[:pileup]

    #if @pair[0].has_paired? != @pair[1].has_paired?
      #@errors << "This comparison mixes Singled & Paired end samples, that might be bad"
      #return false
    #end

    cmd = conf.cluster_cmd_prefix(free:4, max:8, sync:true, name:"#{self.safe_name}") +
      %W(macs2 callpeak --bdg -f BAM -t #{@pair[0].analysis_ready_bam.path} -c #{@pair[1].analysis_ready_bam.path}
         -n #{output_base} --bw #{@pair[0].analysis_ready_bam.fragment_size}) +
      @cmd_args
    puts cmd.join(" ") if conf.verbose
    unless system(*cmd)
      @errors << "Failed to execute macs for #{self}: #{$?.exitstatus}"
      return false
    end
    return true
  end
end
