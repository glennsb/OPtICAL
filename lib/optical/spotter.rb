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
    @error = ""
    return true if calculated?()

    Dir.mkdir data_dir() unless Dir.exists?(data_dir())

    cmd = conf.cluster_cmd_prefix(free:2, max:16, sync:true, name:"spot_#{name()}") +
      %W(optical spot -o #{data_dir()} -c #{conf.hotspot_config})
    if has_control?()
      cmd += %W(-i #{@controls.first.analysis_ready_bam.path})
    end
    @treatments.each do |t|
      cmd += %W(-t #{t.analysis_ready_bam.path})
    end
    puts cmd.join(" ") if conf.verbose
    unless system(*cmd)
      @error = "Failure hotspotting for #{name()} #{$?.exitstatus}"
      return false
    end
    true
  end

  def calculated?()
    File.exists?(spotfile_path())
  end

  def score
  end

  def name
    name = @treatments.first.safe_name.tr(" ",'_').tr("/","_")
    if has_control?()
      name += "_" + @controls.first.safe_name.tr(" ",'_').tr("/","_")
    end
    name
  end

  private

  def has_control?()
    @controls.size > 0 && @controls[0]
  end

  def data_dir()
    File.join(@base_dir,name)
  end

  def spotfile_path()
    base = File.basename(@treatments.first.safe_name,".bam")
    File.join(data_dir(),base) + ".spot.out"
  end
end
