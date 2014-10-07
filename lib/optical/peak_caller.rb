# Copyright (c) 2014, Stuart Glenn, OMRF
# Distributed under a BSD 3-Clause
# Full license available in LICENSE.txt distributed with this software

class Optical::PeakCaller

  Dir[File.join( File.dirname(__FILE__),"peak_callers","*.rb")].each do |rb|
    require rb
  end

  def self.create(algo,name,pair,opts)
    klass = "Optical::PeakCaller::#{algo}" unless klass =~ /::/
    klass = Kernel.const_get(klass)
    klass.new(name,pair,opts)
  end

  attr_reader :cmd_args, :name

  def initialize(name,pair,opts)
    @name = name
    @cmd_args = opts[:args].split(/ /)
    @pair = pair
    @errors = []
  end

  def to_s
    "#{@name} of #{@pair[0]} vs #{@pair[1]}"
  end

  def safe_name
    "#{@name.tr(" ",'_').tr("/","_")}_#{@pair[0].safe_name}_vs_#{@pair[1].safe_name}"
  end

  def find_peaks(output_base,conf)
    @errors << "The subclass did not define how to find peaks"
    return false
  end

  def sample_ready?(s)
    s.analysis_ready_bam && File.exists?(s.analysis_ready_bam.path)
  end

  def error()
    @errors.join("\n")
  end
end
