# Copyright (c) 2015, Stuart Glenn, OMRF
# Distributed under a BSD 3-Clause
# Full license available in LICENSE.txt distributed with this software

class Optical::Spotter

  attr_writer :base_dir

  def initialize(opts)
    @treatments = opts[:treatments].sort
    @controls = opts[:controls].sort
    @base_dir = Dir.pwd
  end

  def ==(b)
    self.treatments == b.treatments && self.controls == b.controls
  end

  def calculate(conf)
  end

  def calculated?()
  end

  def score
  end

  def name
    name = @treatments.first.safe_name.tr(" ",'_').tr("/","_")
    if @controls.size > 0 && @controls[0]
      name += "_" + @controls.first.safe_name.tr(" ",'_').tr("/","_")
    end
    name
  end

  private

  def data_dir()
  end
end
