# Copyright (c) 2014, Stuart Glenn, OMRF
# Distributed under a BSD 3-Clause
# Full license available in LICENSE.txt distributed with this software

require 'optical/peak_callers/idr'

class Optical::PeakCaller::FseqIdr < Optical::PeakCaller::Idr

  private

  def score_sort_column()
    7
  end

  def peak_caller()
    Fseq
  end
end
