# Copyright (c) 2014, Stuart Glenn, OMRF
# Distributed under a BSD 3-Clause
# Full license available in LICENSE.txt distributed with this software

class Optical::Filters::NullFilter
  def initialize(lib,name,conf)
    @lib = lib
    @name = name
    @conf = conf
  end

  def filter_to(output_bam)
    @lib.filtered_path = @lib.aligned_path
    return true
  end
end
