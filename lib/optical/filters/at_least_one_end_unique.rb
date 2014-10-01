# Copyright (c) 2014, Stuart Glenn, OMRF
# Distributed under a BSD 3-Clause
# Full license available in LICENSE.txt distributed with this software

class Optical::Filters::AtLeastOneEndUnique < Optical::Filters::NullFilter
  def filter_to(output_bam)
    if ! @lib.is_paired?
      raise ArgumentError.new("This filter only works for paired end data")
    end

    filter_through_awk_script([File.join(File.dirname(__FILE__),"paired_end_filters.awk"),"at_least_one_unique"],
                                output_bam,@conf.min_map_quality_score,true)
  end
end
