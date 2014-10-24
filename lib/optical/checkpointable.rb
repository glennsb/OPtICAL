# Copyright (c) 2014, Stuart Glenn, OMRF
# Distributed under a BSD 3-Clause
# Full license available in LICENSE.txt distributed with this software

module Optical::Checkpointable
  def checkpointed(outbase)
    unless outbase
      add_error("Failed to get output base #{outbase} for #{self}")
      return false
    end
    cp_path = File.join(outbase,"checkpoint.yml")
    if File.exists?(cp_path)
      ser = YAML::load_file(cp_path)
      (ser.instance_variables-[:@conf]).each do |v|
        self.instance_variable_set(v,ser.instance_variable_get(v))
      end
      return true
    end
    if yield(outbase,self)
      File.open(cp_path,"w") do |out|
        out.puts YAML::dump(self)
      end
      return true
    else
      return false
    end
  end
end
