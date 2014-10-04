# Copyright (c) 2014, Stuart Glenn, OMRF
# Distributed under a BSD 3-Clause
# Full license available in LICENSE.txt distributed with this software

class Optical::ChipBamVisual
  def initialize(output_base,input_bam)
    @output_base = output_base
    @bam_path = input_bam
  end

  def create_files()
    @errors = []
    unless Dir.exists?(@output_base)
      @errors << "Output directory #{o@utput_base} does not exist"
      return false
    end
    unless File.exists?(@bam_path)
      @errors << "Input bam #{@bam_path} does not exist"
      return false
    end

    return parse_bam_to_intermediate_files() && false
  end

  # we need to the number of alignments, a temp bed, and, TLEN counts
  def parse_bam_to_intermediate_files()
  end

  def error()
    @errors.join("; ")
  end
end
