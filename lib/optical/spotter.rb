# Copyright (c) 2015, Stuart Glenn, OMRF
# Distributed under a BSD 3-Clause
# Full license available in LICENSE.txt distributed with this software

class Optical::Spotter

  attr_accessor :error, :treatments, :controls, :base_dir
  attr_writer :base_dir

  def initialize(opts)
    @treatments = opts[:treatments].sort
    @controls = opts[:controls].sort
    @base_dir = Dir.pwd
  end

  def eql?(b)
    self.class == b.class &&
    self.treatments == b.treatments &&
    self.controls == b.controls &&
    self.base_dir == b.base_dir
  end

  def hash()
    [name(), @base_dir].hash
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
    File.join(@base_dir,name)
  end

  def spotfile_path()
    base = File.basename(@treatments.first.safe_name,".bam")
    File.join(data_dir(),base) + ".spot.out"
  end
end
