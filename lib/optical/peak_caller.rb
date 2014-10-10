# Copyright (c) 2014, Stuart Glenn, OMRF
# Distributed under a BSD 3-Clause
# Full license available in LICENSE.txt distributed with this software

class Optical::PeakCaller

  Dir[File.join( File.dirname(__FILE__),"peak_callers","*.rb")].each do |rb|
    require rb
  end

  def self.create(algo,name,treatments,controls,opts)
    raise InvalidArgument, "No treatments" unless treatments && treatments.size > 0
    raise InvalidArgument, "No controls" unless controls && controls.size > 0
    klass = "Optical::PeakCaller::#{algo}" unless klass =~ /::/
    klass = klass.split("::").inject(Object) {|o,c| o.const_get c}
    klass.new(name,treatments,controls,opts)
  end

  attr_reader :cmd_args, :name

  def initialize(name,treatments,controls,opts)
    @name = name
    @cmd_args = opts[:args].split(/ /)
    @treatments = treatments
    @controls = controls
    @errors = []
  end

  def to_s
    "#{@name} of #{@treatments[0]} vs #{@controls[0]}"
  end

  def safe_name
    "#{@name.tr(" ",'_').tr("/","_")}_#{@treatments[0].safe_name}_vs_#{@controls[0].safe_name}"
  end

  def find_peaks(output_base,conf)
    @errors << "The subclass did not define how to find peaks"
    return false
  end

  def treatment_samples
    return @treatments.to_enum unless block_given?
    @treatments.each do |p|
      yield p
    end
  end

  def control_samples
    return @controls.to_enum unless block_given?
    @controls.each do |p|
      yield p
    end
  end

  def sample_ready?(s)
    s.analysis_ready_bam && File.exists?(s.analysis_ready_bam.path)
  end

  def error()
    @errors.join("\n")
  end
end
