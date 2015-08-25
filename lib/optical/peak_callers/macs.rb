# Copyright (c) 2014, Stuart Glenn, OMRF
# Distributed under a BSD 3-Clause
# Full license available in LICENSE.txt distributed with this software

class Optical::PeakCaller::Macs < Optical::PeakCaller
  MACS_OUTPUT_SUFFICES = {control_bdg:"_control_lambda.bdg", model_r:"_model.r", model_pdf:"_model.pdf",
    peak_bed:"_peaks.bed", encode_peak:"_peaks.narrowPeak", peak_xls:"_peaks.xls",
    summit_bed:"_summits.bed", pileup:"_treat_pileup.bdg"}

  attr_reader :control_bdg_path, :encode_peak_path, :peak_xls_path, :summit_bed_path,
    :pileup_path, :model_pdf_path, :encode_peak_vs_gene_path

  def find_peaks(output_base,conf)
    full_output_base = File.join(output_base,safe_name())
    short_output_base = File.join(output_base,fs_name())
    (@treatments + @controls).compact.each do |s|
      unless sample_ready?(s)
        @errors << "The sample #{s} is not ready, the bam (#{s.analysis_ready_bam}) is missing"
        return false
      end
    end
    if run_macs(output_base,conf)
      @control_bdg_path = short_output_base + MACS_OUTPUT_SUFFICES[:control_bdg]
      @peak_bed_path = short_output_base + MACS_OUTPUT_SUFFICES[:peak_bed]
      @encode_peak_path = short_output_base + MACS_OUTPUT_SUFFICES[:encode_peak]
      @peak_xls_path = short_output_base + MACS_OUTPUT_SUFFICES[:peak_xls]
      @summit_bed_path = short_output_base + MACS_OUTPUT_SUFFICES[:summit_bed]
      @pileup_path = short_output_base + MACS_OUTPUT_SUFFICES[:pileup]

      return model_to_pdf(short_output_base,conf) &&
        strip_name_prefix_from_peak_names(conf) &&
        add_track_header_to_file(@peak_bed_path,conf) &&
        (@encode_peak_vs_gene_path = find_genes_near_peaks(@encode_peak_path,short_output_base,conf)) &&
        calculate_cross_correlation(output_base,conf) &&
        fix_names(short_output_base,full_output_base)
    end
    return false
  end

  def fix_names(short,full)
    begin
      if File.size?(@control_bdg_path)
        File.rename(@control_bdg_path ,full + MACS_OUTPUT_SUFFICES[:control_bdg])
        @control_bdg_path = full + MACS_OUTPUT_SUFFICES[:control_bdg]
      end
      if File.size?(@peak_bed_path)
        File.rename(@peak_bed_path ,full + MACS_OUTPUT_SUFFICES[:peak_bed])
        @peak_bed_path = full + MACS_OUTPUT_SUFFICES[:peak_bed]
      end
      if File.size?(@encode_peak_path )
        File.rename(@encode_peak_path ,full + MACS_OUTPUT_SUFFICES[:encode_peak])
        @encode_peak_path = full + MACS_OUTPUT_SUFFICES[:encode_peak]
      end
      if File.size?(@peak_xls_path)
        File.rename(@peak_xls_path ,full + MACS_OUTPUT_SUFFICES[:peak_xls])
        @peak_xls_path = full + MACS_OUTPUT_SUFFICES[:peak_xls]
      end
      if File.size?(@summit_bed_path)
        File.rename(@summit_bed_path ,full + MACS_OUTPUT_SUFFICES[:summit_bed])
        @summit_bed_path = full + MACS_OUTPUT_SUFFICES[:summit_bed]
      end
      if File.size?(@pileup_path)
        File.rename(@pileup_path ,full + MACS_OUTPUT_SUFFICES[:pileup])
        @pileup_path = full + MACS_OUTPUT_SUFFICES[:pileup]
      end
      if File.size?(short + "_model.pdf")
        File.rename(short + "_model.pdf",full + "_model.pdf")
      end
      if File.size?(@encode_peak_vs_gene_path)
        File.rename(@encode_peak_vs_gene_path , full + "_peak_vs_gene.xls")
        @encode_peak_vs_gene_path = full + "_peak_vs_gene.xls"
      end
    rescue Exception => e
      @errors << "Trouble fixing file names for #{self}: #{e} - #{e.message}"
      return false
    end
    return true
  end

  def already_called?(output_base,conf)
    full_output_base = File.join(output_base,safe_name())
    encode_peak_path = full_output_base + MACS_OUTPUT_SUFFICES[:encode_peak]
    peak_bed_path = full_output_base + MACS_OUTPUT_SUFFICES[:peak_bed]

    if File.size?(encode_peak_path) && File.size?(peak_bed_path)
      @encode_peak_path = encode_peak_path
      @peak_bed_path = peak_bed_path
      @control_bdg_path = full_output_base + MACS_OUTPUT_SUFFICES[:control_bdg]
      @peak_xls_path = full_output_base + MACS_OUTPUT_SUFFICES[:peak_xls]
      @summit_bed_path = full_output_base + MACS_OUTPUT_SUFFICES[:summit_bed]
      @pileup_path = full_output_base + MACS_OUTPUT_SUFFICES[:pileup]
      @model_pdf_path = full_output_base + MACS_OUTPUT_SUFFICES[:model_pdf]
      @encode_peak_vs_gene_path = "#{full_out_path}_peak_vs_gene.xls"
      return true
    end
    return false
  end

  def peak_path()
    [@encode_peak_path]
  end

  def peak_bed_path()
    [@peak_bed_path]
  end

  def clean
    [@control_bdg_path, @encode_peak_path, @peak_xls_path, @summit_bed_path,
     @pileup_path, @model_pdf_path, @encode_peak_vs_gene_path].keep_if do |f|
      f && File.exists?(f)
    end.each do |f|
      File.delete(f)
    end
  end

  private

  def find_genes_near_peaks(in_path,out_path,conf)
    output = "#{out_path}_peak_vs_gene.xls"
    cmd = conf.cluster_cmd_prefix(free:2, max:8, sync:true, name:"findgenes_#{safe_name()}") +
      %W(find_nearby_genes.pl #{in_path} #{conf.ucsc_refflat_path} #{output}
         #{conf.gene_peak_neighbor_distance} 1,2,3,8)

    puts cmd.join(" ") if conf.verbose
    unless system(*cmd)
      @errors << "Failed to fine genes near peaks for #{self}: #{$?.exitstatus}"
      return nil
    end
    return output
  end

  def add_track_header_to_file(path,conf)
    return true unless File.exists?(path)
    name=File.basename(path)
    header=<<-EOF
track name="#{name}" description="#{name}" visibility=full color="#{conf.random_visualization_color()}"
    EOF
    cmd = conf.cluster_cmd_prefix(free:1, max:1, sync:true, name:"trackname_#{safe_name()}") +
      %W(sed -i '1i#{header.chomp}' #{path})

    puts cmd.join(" ") if conf.verbose
    unless system(*cmd)
      @errors << "Failed to add track header for #{self}: #{$?.exitstatus}"
      return false
    end
    return true
  end

  def strip_name_prefix_from_peak_names(conf)
    cmd = conf.cluster_cmd_prefix(free:2, max:4, sync:true, name:"name_strip_#{safe_name()}") +
      %W(sed -i '/^chr/ s/#{fs_name()}_//') +
      [@peak_bed_path, @encode_peak_path, @peak_xls_path, @summit_bed_path].keep_if do |f|
        File.exists?(f)
      end

    puts cmd.join(" ") if conf.verbose
    unless system(*cmd)
      @errors << "Failed to strip peak name prefix of macs for #{self} using: '#{cmd}': #{$?.exitstatus}"
      return false
    end
    return true
  end

  def model_to_pdf(output_base,conf)
    return true if @cmd_args.include?("--nomodel")
    rscript = "#{fs_name()}#{MACS_OUTPUT_SUFFICES[:model_r]}"
    cmd = conf.cluster_cmd_prefix(wd:File.dirname(output_base), free:2, max:4,
                                  sync:true, name:"r_#{safe_name()}") +
      %W(Rscript #{rscript})

    puts cmd.join(" ") if conf.verbose
    unless system(*cmd)
      @errors << "Failed to make pdf of macs for #{self}: #{$?.exitstatus}"
      return false
    end
    rscript = File.join( File.dirname(output_base), rscript )
    File.delete(rscript) if File.exists?(rscript)
    @model_pdf_path = output_base + MACS_OUTPUT_SUFFICES[:model_pdf]
    return true
  end

  def run_macs(output_base,conf)
    controls_cmd = if @controls && @controls.size > 0 && nil != @controls[0]
                     %W(-c #{bam_path(@controls[0].analysis_ready_bam,conf)})
                   else
                     []
                   end
   cmd = conf.cluster_cmd_prefix(wd:output_base, free:8, max:32, sync:true,
                                 name:"#{safe_name()}") +
      %W(macs2 callpeak -f BAM -t) + @treatments.map{|t| bam_path(t.analysis_ready_bam,conf)} +
         controls_cmd + %W(-n #{fs_name()}
         --bw #{@treatments[0].analysis_ready_bam.fragment_size}) + @cmd_args

    puts cmd.join(" ") if conf.verbose
    unless system(*cmd)
      @errors << "Failed to execute macs for #{self}: #{$?.exitstatus}: #{cmd.join(" ")}"
      return false
    end
    return true
  end
end
