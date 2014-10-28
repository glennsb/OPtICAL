# Copyright (c) 2014, Stuart Glenn, OMRF
# Distributed under a BSD 3-Clause
# Full license available in LICENSE.txt distributed with this software

class Optical::Library
  attr_reader :run, :lane, :fastq_paths, :fastqc_paths
  attr_accessor :aligned_path, :qc_path, :filtered_path

  def initialize(opts)
    @run = opts[:run] || ""
    @lane = opts[:lane] || ""
    @fastq_paths = opts[:inputs] || []
    @fastqc_paths = []
  end

  def is_paired?()
    2 == @fastq_paths.size
  end

  def add_fastqc_path(path)
    @fastqc_paths << path
  end

  def load_stats()
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
