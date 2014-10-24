# Copyright (c) 2014, Stuart Glenn, OMRF
# Distributed under a BSD 3-Clause
# Full license available in LICENSE.txt distributed with this software

class Optical::ChipBamVisual
  FRAGMENT_SIZE_SUFFIX = "_estimated_size.txt"

  attr_reader :raw_bedgraph_path, :normalized_bedgraph_path, :raw_wig_path, :normalized_wig_path,
    :tdf_wig_path

  def initialize(output_base,input_bam,conf)
    @output_base = output_base
    @bam = input_bam
    @conf = conf
    @color = @conf.random_visualization_color()
    @raw_bedgraph_path = nil
    @normalized_bedgraph_path = nil
    @raw_wig_path = nil
    @normalized_wig_path = nil
    @tdf_wig_path = nil
  end

  def encode_with(coder)
    (instance_variables-[:@conf]).each do |v|
      #next if "@conf" == v.to_s
      coder[v.to_s.sub(/^@/, '')] = instance_variable_get(v)
    end
  end

  def create_files()
    @errors = []
    unless Dir.exists?(@output_base)
      @errors << "Output directory #{@utput_base} does not exist"
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
      normalize_bedgraph(output_prefix) &&
      normalize_wig(output_prefix) &&
      (@tdf_wig_path = wig_to_tdf(@normalized_wig_path)) &&
      compress_outputs()
  end

  def wig_to_tdf(wig_path)
    if (nil == wig_path || !File.exists?(wig_path))
      @errors << "The given wig #{wig_path} doesn't exist"
      return false
    end
    out_path = wig_path.sub(/\.wig$/,'.tdf')
    cmd = @conf.cluster_cmd_prefix(free:6, max:12, sync:true, name:"wig_tdf_#{File.basename(@bam.path)}") +
      %W(igvtools toTDF #{wig_path} #{out_path} #{@conf.igv_reference})
    puts cmd.join(" ") if @conf.verbose
    unless system(*cmd)
      @errors << "Failure wig to totdf for #{@bam} #{$?.exitstatus}"
      return false
    end
    File.delete("igv.log") if File.exists?("igv.log")
    return out_path
  end

  def clean_tmp_bed(out_prefix)
    bed = "#{out_prefix}_tmp.bed"
    File.delete(bed) if File.exists?(bed)
    return true
  end

  def compress_outputs()
    files = [@raw_wig_path, @raw_bedgraph_path, @normalized_bedgraph_path, @normalized_wig_path]
    cmd = @conf.cluster_cmd_prefix(free:2, max:4, sync:true, name:"compress_viz_#{File.basename(@bam.path)}") +
      %W(gzip) + files
    puts cmd.join(" ") if @conf.verbose
    unless system(*cmd)
      @errors << "Failure compressing visuals for #{@bam} #{$?.exitstatus}"
      return false
    end
    files.each do |f|
      f = f += ".gz"
    end
    return true
  end

  def normalize_wig(out_prefix)
    if (nil == @raw_wig_path || !File.exists?(@raw_wig_path))
      @errors << "Raw wig file doesn't exist, can't normalize for #{@bam}"
      return false
    end
    out_path = "#{out_prefix}_normalized.wig"
    cmd = @conf.cluster_cmd_prefix(free:1, max:2, sync:true, name:"normalize_wig_#{File.basename(@bam.path)}") +
      %W(optical normalizeWig -w #{@raw_wig_path} -c #{@bam.num_alignments} -o #{out_path})
    puts cmd.join(" ") if @conf.verbose
    unless system(*cmd)
      @errors << "Failure normalizing wig for #{@bam} #{$?.exitstatus}"
      return false
    end
    @normalized_wig_path = out_path
    return true
  end

  def normalize_bedgraph(out_prefix)
    if @raw_bedgraph_path && !File.exists?(@raw_bedgraph_path)
      @errors << "Raw bedgraph doesn't exist, can't normalize for #{@bam}"
      return false
    end
    out_path = "#{out_prefix}_normalized.bedgraph"
    cmd = @conf.cluster_cmd_prefix(free:1, max:2, sync:true, name:"normalize_bedgraph_#{File.basename(@bam.path)}") +
      %W(optical normalizeBedgraph -b #{@raw_bedgraph_path} -c #{@bam.num_alignments} -o #{out_path})
    puts cmd.join(" ") if @conf.verbose
    unless system(*cmd)
      @errors << "Failure normalizing bedgraph for #{@bam} #{$?.exitstatus}"
      return false
    end
    @normalized_bedgraph_path = out_path
    return true
  end

  def convert_bed_to_wig(out_prefix)
    if !File.exists?(@raw_bedgraph_path)
      @errors << "Raw bedgraph doesn't exist, can't convert to wig for #{@bam}"
      return false
    end
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
    end
    IO.foreach(out_prefix+"_num_alignments.txt") do |line|
      @bam.num_alignments = line.chomp.to_i
      break
    end
    return true
  end

  def error()
    @errors.join("; ")
  end
end
