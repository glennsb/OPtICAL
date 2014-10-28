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
        "number unique mapped reads" => number_unique_mapped_reads.to_i,
        "number multiple hit reads" => number_multiple_hit_reads.to_i,
        "number unmapped reads" => number_unmapped_reads.to_i,
        "number total reads" => number_total_reads.to_i,
        "number total mapped reads" => number_total_mapped_reads.to_i,
        "number genomic positions with single unique read mapped" => number_genomic_positions_with_single_unique_read_mapped.to_i,
        "number genomic positions with greater than one unique read mapped" => number_genomic_positions_with_greater_than_one_unique_read_mapped.to_i,
        "number total genomic positions with unique read mapped" => number_total_genomic_positions_with_unique_read_mapped.to_i
      }
    end
  end
end
