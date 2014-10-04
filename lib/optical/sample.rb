# Copyright (c) 2014, Stuart Glenn, OMRF
# Distributed under a BSD 3-Clause
# Full license available in LICENSE.txt distributed with this software

class Optical::Sample
  attr_reader :name

  attr_accessor :analysis_ready_bam, :bam_visual

  def initialize(name,libraries)
    @name = name
    @libs = libraries
  end

  def libraries
    return @libs.to_enum unless block_given?
    @libs.each do |l|
      yield l
    end
  end

  def has_paired?()
    @libs.any?{|l| l.is_paired?}
  end

  def safe_name()
    @safe_name ||= @name.tr(" ",'_').tr("/","_")
  end

  def to_s
    @name
  end
end
