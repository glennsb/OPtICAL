# Copyright (c) 2014, Stuart Glenn, OMRF
# Distributed under a BSD 3-Clause
# Full license available in LICENSE.txt distributed with this software

class Optical::Filters::PrimaryAlignment < Optical::Filters::NullFilter
  def filter_to(output_bam)
    if @lib.is_paired?
      primary_alignment_pairs(output_bam)
    else
      primary_alignment_singles(output_bam)
    end
  end

  def primary_alignment_pairs(output_bam)
    return false
  end

  def primary_alignment_singles(output_bam)
    filter_through_awk_script(File.join(File.dirname(__FILE__),"single_primary_alignment.awk"),
                              output_bam,@conf.min_map_quality_score)
  end
end
