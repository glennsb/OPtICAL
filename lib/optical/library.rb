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
end
