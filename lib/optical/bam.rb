# Copyright (c) 2014, Stuart Glenn, OMRF
# Distributed under a BSD 3-Clause
# Full license available in LICENSE.txt distributed with this software

class Optical::Bam

  attr_reader :path

  attr_accessor :fragment_size, :num_alignments, :dupes_removed

  def initialize(path,paired)
    @path = path
    @paired = paired
  end

  def paired?
    return @paired
  end

  def to_s
    @path
  end
end
