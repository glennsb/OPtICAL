# Copyright (c) 2014, Stuart Glenn, OMRF
# Distributed under a BSD 3-Clause
# Full license available in LICENSE.txt distributed with this software

class Optical::ChipBamVisual
  FRAGMENT_SIZE_SUFFIX = "_estimated_size.txt"

  def initialize(output_base,input_bam,conf)
    @output_base = output_base
    @bam = input_bam
    @conf = conf
  end

  def create_files()
    @errors = []
    unless Dir.exists?(@output_base)
      @errors << "Output directory #{o@utput_base} does not exist"
      return false
    end
    unless File.exists?(@bam.path)
      @errors << "Input bam #{@bam} does not exist"
      return false
    end
    output_prefix = File.join(@output_base,File.basename(@bam.path,".bam"))

    return parse_bam_to_intermediate_files(output_prefix) && false
  end

  # we need to the number of alignments, a temp bed, and, TLEN counts
  def parse_bam_to_intermediate_files()
  end

  def error()
    @errors.join("; ")
  end
end
