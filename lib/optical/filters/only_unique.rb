# Copyright (c) 2014, Stuart Glenn, OMRF
# Distributed under a BSD 3-Clause
# Full license available in LICENSE.txt distributed with this software

class Optical::Filters::OnlyUnique < Optical::Filters::NullFilter
  def filter_to(output_bam)
    if @lib.is_paired?
      filter_through_awk_script([File.join(File.dirname(__FILE__),
                                           "paired_end_filters.awk"),
                                "only_unique"],
                                output_bam,@conf.min_map_quality_score,
                                true)
    else
      filter_through_awk_script(File.join(File.dirname(__FILE__),"single_end_only_unique.awk"),
                                output_bam,@conf.min_map_quality_score)
    end
  end
end
