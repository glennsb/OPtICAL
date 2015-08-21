# Copyright (c) 2014, Stuart Glenn, OMRF
# Distributed under a BSD 3-Clause
# Full license available in LICENSE.txt distributed with this software

require 'optical/checkpointable'

class Optical::Sample
  include Optical::Checkpointable
  using Optical::StringExensions

  attr_reader :name

  attr_accessor :analysis_ready_bam, :bam_visual, :qc_path

  def initialize(name,libraries)
    @analysis_ready_bam = nil
    @bam_visual = nil
    @qc_path = nil
    @name = name
    @libs = libraries
  end

  def libraries
    return @libs.to_enum unless block_given?
    @libs.each do |l|
      yield l
    end
  end

  def has_paired?()
    @libs.any?{|l| l.is_paired?}
  end

  def safe_name()
    @safe_name ||= @name.tr(" ",'_').tr("/","_")
  end

  def to_s
    @name
  end

  def pseudo_replicate_names(num_replicates,output_base)
    rep_base_name = "#{safe_name}_pseudo_replicate"
    outname = File.join(output_base,rep_base_name)
    replicate_samples = []
    num_replicates.times do |r|
      rep = (r+1).to_s.rjust(2,"0")
      path = "#{outname}_#{rep}.bam"
      b = Optical::Bam.new(path,has_paired?())
      b.fragment_size = analysis_ready_bam.fragment_size()
      b.dupes_removed = analysis_ready_bam.dupes_removed
      rep = Optical::Sample.new("#{rep_base_name}_#{rep}",[])
      rep.analysis_ready_bam=b
      replicate_samples << rep
    end
    return replicate_samples
  end

  def create_pseudo_replicates(num_replicates,output_base,conf)
    return nil unless analysis_ready_bam && File.exists?(analysis_ready_bam.path)
    return nil unless Dir.exists?(output_base)
    # shuffle the bam, and ever %num_replicates goes to different file, then sort those
    rep_base_name = "#{safe_name}_pseudo_replicate"
    outname = File.join(output_base,rep_base_name)
    free = 10
    if analysis_ready_bam.num_alignments >= 100000000
      free = 100
    end
    cmd = conf.cluster_cmd_prefix(free:free, max:90, sync:true, name:"replicate_#{safe_name}") +
          %W(optical pseudoReplicateBam -b #{analysis_ready_bam.path} -o #{outname} -r #{num_replicates})
    puts cmd.join(" ") if conf.verbose
    unless system(*cmd)
      return nil
    end
    pseudo_replicate_names(num_replicates,output_base)
  end

  def add_error(msg)
    @errors ||= []
    @errors << msg
  end

  def mapping_counts
    unless @mapping_counts
      load_stats()
    end
    return @mapping_counts
  end

  def load_stats()
    if has_paired?()
      load_paired_stats()
    else
      load_single_stats()
    end
  end

  def load_paired_stats()
    IO.foreach(@qc_path) do |line|
      next if 0 == $.
       parts = line.chomp.split(/\t/)
      @name = parts.shift
      @mapping_counts = {
        unique_mapped_pairs:parts.shift.to_i,
        multiple_hit_both_of_pairs:parts.shift.to_i,
        multiple_hit_one_of_pairs:parts.shift.to_i,
        unmapped_pairs:parts.shift.to_i,
        total_pairs:parts.shift.to_i,
        total_mapped_pairs:parts.shift.to_i,
        half_mapped_pairs:parts.shift.to_i,
        unproperly_mapped_pairs:parts.shift.to_i,
        genomic_positions_with_single_unique_pair_mapped:parts.shift.to_i,
        genomic_positions_with_greater_than_one_unique_pair_mapped:parts.shift.to_i,
        total_genomic_positions_with_unique_pairs_mapped:parts.shift.to_i
      }
    end
  end

  def load_single_stats()
    IO.foreach(@qc_path) do |line|
      next if 0 == $.
      (name,number_unique_mapped_reads,number_multiple_hit_reads,
       number_unmapped_reads,number_total_reads,number_total_mapped_reads,
       number_genomic_positions_with_single_unique_read_mapped,
       number_genomic_positions_with_greater_than_one_unique_read_mapped,
       number_total_genomic_positions_with_unique_read_mapped) = line.chomp.split(/\t/)
      @name = name
      @mapping_counts = {
        unique_mapped_reads:number_unique_mapped_reads.to_i,
        multiple_hit_reads:number_multiple_hit_reads.to_i,
        unmapped_reads:number_unmapped_reads.to_i,
        total_reads:number_total_reads.to_i,
        total_mapped_reads:number_total_mapped_reads.to_i,
        genomic_positions_with_single_unique_read_mapped:number_genomic_positions_with_single_unique_read_mapped.to_i,
        genomic_positions_with_greater_than_one_unique_read_mapped:number_genomic_positions_with_greater_than_one_unique_read_mapped.to_i,
        total_genomic_positions_with_unique_read_mapped:number_total_genomic_positions_with_unique_read_mapped.to_i
      }
    end
  end
end
