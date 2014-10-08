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

      return model_to_pdf(full_output_base,conf) &&
        strip_name_prefix_from_peak_names(conf)
    end
    return false
  end
  private

  def strip_name_prefix_from_peak_names(conf)
    cmd = conf.cluster_cmd_prefix(free:2, max:4, sync:true, name:"name_strip_#{safe_name()}") +
      %W(sed -i '/^chr/ s/#{safe_name()}_//') +
      [@peak_bed_path, @encode_peak_path, @peak_xls_path, @summit_bed_path]

    unless conf.skip_peak_calling
      puts cmd.join(" ") if conf.verbose
      unless system(*cmd)
        @errors << "Failed to strip peak name prefix of macs for #{self}: #{$?.exitstatus}"
        return false
      end
    end
    return true
  end

  def model_to_pdf(output_base,conf)
    rscript = "#{safe_name()}_#{MACS_OUTPUT_SUFFICES[:model_r]}"
    cmd = conf.cluster_cmd_prefix(wd:File.dirname(output_base), free:2, max:4, sync:true, name:"r_#{safe_name()}") +
      %W(Rscript #{rscript})

    unless conf.skip_peak_calling
      puts cmd.join(" ") if conf.verbose
      unless system(*cmd)
        @errors << "Failed to make pdf of macs for #{self}: #{$?.exitstatus}"
        return false
      end
      rscript = File.join( File.dirname(output_base), rscript )
      File.delete(rscript) if File.exists?(rscript)
    end
    @model_pdf_path = output_base + MACS_OUTPUT_SUFFICES[:model_pdf]
    return true
  end

  def run_macs(output_base,conf)
    cmd = conf.cluster_cmd_prefix(wd:output_base, free:4, max:8, sync:true, name:"#{safe_name()}") +
      %W(macs2 callpeak --bdg -f BAM -t #{@pair[0].analysis_ready_bam.path}
         -c #{@pair[1].analysis_ready_bam.path} -n #{safe_name()}
         --bw #{@pair[0].analysis_ready_bam.fragment_size}) + @cmd_args

    unless conf.skip_peak_calling
      puts cmd.join(" ") if conf.verbose
      unless system(*cmd)
        @errors << "Failed to execute macs for #{self}: #{$?.exitstatus}"
        return false
      end
    end
    return true
  end
end
