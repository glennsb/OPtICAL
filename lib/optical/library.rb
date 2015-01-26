# Copyright (c) 2014, Stuart Glenn, OMRF
# Distributed under a BSD 3-Clause
# Full license available in LICENSE.txt distributed with this software

Optical::LibraryPart = Struct.new(:run, :lane, :fastq_paths, :downsample, :bam_path)

class Optical::Library
  attr_reader :fastqc_paths, :mapping_counts
  attr_accessor :aligned_path, :qc_path, :filtered_path

  def initialize(parts)
    @library_parts = parts
    @fastqc_paths = []
  end

  def is_paired?()
    @library_parts.map {|p| 2 == p.fastq_paths.size}.any?
  end

  def fastq_paths()
    @library_parts.map {|p| p.fastq_paths}.flatten
  end

  def add_fastqc_path(path)
    @fastqc_paths << path
  end

  def parts()
    @library_parts
  end

  def load_stats()
    if is_paired?()
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
