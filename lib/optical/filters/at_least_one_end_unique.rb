# Copyright (c) 2014, Stuart Glenn, OMRF
# Distributed under a BSD 3-Clause
# Full license available in LICENSE.txt distributed with this software

class Optical::Filters::AtLeastOneEndUnique < Optical::Filters::NullFilter
  def filter_to(output_bam)
    if ! @lib.is_paired?
      # A single end with at least one end unique, is really just only unique, duh
      Optical::Filters::OnlyUnique.new(@lib,@name,@conf).filter_to(output_bam)
    else
      filter_through_awk_script([File.join(File.dirname(__FILE__),"paired_end_filters.awk"),"at_least_one_unique"],
                                  output_bam,@conf.min_map_quality_score,true)
    end
  end
end
