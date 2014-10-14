# Copyright (c) 2014, Stuart Glenn, OMRF
# Distributed under a BSD 3-Clause
# Full license available in LICENSE.txt distributed with this software

class Optical::PeakCaller::Macs < Optical::PeakCaller
  MACS_OUTPUT_SUFFICES = {control_bdg:"_control_lambda.bdg", model_r:"_model.r", model_pdf:"_model.pdf",
    peak_bed:"_peaks.bed", encode_peak:"_peaks.encodePeak", peak_xls:"_peaks.xls",
    summit_bed:"_summits.bed", pileup:"_treat_pileup.bdg"}

  attr_reader :control_bdg_path, :peak_bed_path, :encode_peak_path, :peak_xls_path, :summit_bed_path,
    :pileup_path, :model_pdf_path, :encode_peak_vs_gene_path

  def find_peaks(output_base,conf)
    full_output_base = File.join(output_base,safe_name)
    [@treatments[0], @controls[0]].each do |s|
      unless sample_ready?(s)
        @errors << "The sample #{s} is not ready, the bam (#{s.analysis_ready_bam}) is missing"
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
        strip_name_prefix_from_peak_names(conf) &&
        add_track_header_to_file(@peak_bed_path,conf) &&
        (@encode_peak_vs_gene_path = find_genes_near_peaks(@encode_peak_path,full_output_base,conf))
    end
    return false
  end

  def num_peaks()
    unless @num_peaks
      @num_peaks = 0
      IO.foreach(@encode_peak_path) do
        @num_peaks+=1
      end
    end
    return @num_peaks
  end
  private

  def find_genes_near_peaks(in_path,out_path,conf)
    output = "#{out_path}_peak_vs_gene.xls"
    cmd = conf.cluster_cmd_prefix(free:1, max:1, sync:true, name:"findgenes_#{safe_name()}") +
      %W(find_nearby_genes.pl #{in_path} #{conf.ucsc_refflat_path} #{output}
         #{conf.gene_peak_neighbor_distance} 1,2,3,8)

    unless conf.skip_peak_calling
      puts cmd.join(" ") if conf.verbose
      unless system(*cmd)
        @errors << "Failed to fine genes near peaks for #{self}: #{$?.exitstatus}"
        return nil
      end
    end
    return output
  end

  def add_track_header_to_file(path,conf)
    name=File.basename(path)
    header=<<-EOF
track name="#{name}" description="#{name}" visibility=full color="#{conf.random_visualization_color()}"
    EOF
    cmd = conf.cluster_cmd_prefix(free:1, max:1, sync:true, name:"trackname_#{safe_name()}") +
      %W(sed -i '1i#{header.chomp}' #{path})

    unless conf.skip_peak_calling
      puts cmd.join(" ") if conf.verbose
      unless system(*cmd)
        @errors << "Failed to add track header for #{self}: #{$?.exitstatus}"
        return false
      end
    end
    return true
  end

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
    rscript = "#{safe_name()}#{MACS_OUTPUT_SUFFICES[:model_r]}"
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
      %W(macs2 callpeak --bdg -f BAM -t #{@treatments[0].analysis_ready_bam.path}
         -c #{@controls[0].analysis_ready_bam.path} -n #{safe_name()}
         --bw #{@treatments[0].analysis_ready_bam.fragment_size}) + @cmd_args

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
