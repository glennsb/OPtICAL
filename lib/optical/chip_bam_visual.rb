# Copyright (c) 2014, Stuart Glenn, OMRF
# Distributed under a BSD 3-Clause
# Full license available in LICENSE.txt distributed with this software

class Optical::ChipBamVisual
  FRAGMENT_SIZE_SUFFIX = "_estimated_size.txt"

  attr_reader :raw_bedgraph_path, :normalized_bedgraph_path, :raw_wig_path

  def initialize(output_base,input_bam,conf)
    @output_base = output_base
    @bam = input_bam
    @conf = conf
    @color = @conf.random_visualization_color()
  end

  def create_files()
    @errors = []
    unless Dir.exists?(@output_base)
      @errors << "Output directory #{o@utput_base} does not exist"
      return false
    end
    unless File.exists?(@bam.path)
      @errors << "Input bam #{@bam} does not exist"
      return false
    end
    output_prefix = File.join(@output_base,File.basename(@bam.path,".bam"))

    return parse_bam_to_intermediate_files(output_prefix) &&
      make_bedgraph(output_prefix) &&
      clean_tmp_bed(output_prefix) &&
      convert_bed_to_wig(output_prefix) &&
      normalize_bedgraph(output_prefix) && false
  end

  def clean_tmp_bed(out_prefix)
    bed = "#{out_prefix}_tmp.bed"
    File.delete(bed) if File.exists?(bed)
    return true
  end

  def normalize_bedgraph(out_prefix)
    return false unless @raw_bedgraph_path && File.exists?(@raw_bedgraph_path)
    out_path = "#{out_prefix}_normalized.bedgraph"
    cmd = @conf.cluster_cmd_prefix(free:1, max:2, sync:true, name:"normalize_bedgraph_#{File.basename(@bam.path)}") +
      %W(optical normalizeBedgraph -b #{@raw_bedgraph_path} -c #{@bam.num_alignments} -o #{out_path})
    puts cmd.join(" ") if @conf.verbose
    unless system(*cmd)
      @errors << "Failure normalizing bedgraph for #{@bam} #{$?.exitstatus}"
      return false
    end
    @noramlized_bedgraph_path = out_path
    return true
  end

  def convert_bed_to_wig(out_prefix)
    return false unless @raw_bedgraph_path && File.exists?(@raw_bedgraph_path)
    out_path = @raw_bedgraph_path.sub(/bedgraph$/,'wig')
    cmd = @conf.cluster_cmd_prefix(free:1, max:4, sync:true, name:"wig_#{File.basename(@bam.path)}") +
      %W(optical bedgraphToWig -b #{@raw_bedgraph_path} -c #{@color} -s #{@conf.wig_step_size} -o #{out_path})
    puts cmd.join(" ") if @conf.verbose
    unless system(*cmd)
      @errors << "Failure creating wig for #{@bam} #{$?.exitstatus}"
      return false
    end
    @raw_wig_path = out_path
    return true
  end

  def make_bedgraph(out_prefix)
    base = File.basename(@bam.path,".bam")
    out_path = "#{out_prefix}_raw.bedgraph"
    cmd = @conf.cluster_cmd_prefix(free:1, max:4, sync:true, name:"bedgraph_#{File.basename(@bam.path)}")
    trackopts = <<-EOF
name="#{base}_raw.bedgraph" description="#{base}_raw.bedgraph" visibility=full color="#{@color}"
    EOF
    cov = "genomeCoverageBed -i #{out_prefix}_tmp.bed -g #{@conf.genome_table_path} -bg -trackline -trackopts '#{trackopts.chomp}'"
    cov += " > #{out_path}"
    cmd << cov
    puts cmd.join(" ") if @conf.verbose
    unless system(*cmd)
      @errors << "Failure creating bedgraph for #{@bam} #{$?.exitstatus}"
      return false
    end
    @raw_bedgraph_path = "#{out_prefix}_raw.bedgraph"
    return true
  end

  # we need to the number of alignments, a temp bed, and, TLEN counts
  def parse_bam_to_intermediate_files(out_prefix)
    script=File.join(File.dirname(__FILE__),"bam_to_insert_size_bed.awk")
    cmd = @conf.cluster_cmd_prefix(free:1, max:12, sync:true, name:"bed_prep_#{File.basename(@bam.path)}") +
      %W(/bin/bash -o pipefail -o errexit -c)
    filt = "samtools view #{@bam.path} | awk -f #{script} -vbase=#{out_prefix} -vendness="
    if @bam.paired?
      filt += "pe"
    else
      filt += "se -vsize=#{@bam.fragment_size}"
    end
    cmd << "\"#{filt}\""
    puts cmd.join(" ") if @conf.verbose
    unless system(*cmd)
      @errors << "Failure prepping bedfiles for #{@bam} #{$?.exitstatus}"
      return false
    end
    if @bam.paired?
      IO.foreach(out_prefix+FRAGMENT_SIZE_SUFFIX) do |line|
        @bam.fragment_size = line.chomp.to_i
        break
      end
      #File.delete(out_prefix+FRAGMENT_SIZE_SUFFIX)
    end
    IO.foreach(out_prefix+"_num_alignments.txt") do |line|
      @bam.num_alignments = line.chomp.to_i
      break
    end
    #File.delete(out_prefix+"_num_alignments.txt")
    return true
  end

  def error()
    @errors.join("; ")
  end
end
