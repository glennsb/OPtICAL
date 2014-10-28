# Copyright (c) 2014, Stuart Glenn, OMRF
# Distributed under a BSD 3-Clause
# Full license available in LICENSE.txt distributed with this software

module Optical::Checkpointable

  @@mutex = Mutex.new

  def self.included(base)
    base.extend ClassMethods
  end

  module ClassMethods
    def deserialize(source,target)
      (source.instance_variables-[:@conf]).each do |v|
        if source.instance_variable_get(v).class.to_s.split("::").first == "Optical" && nil != target.instance_variable_get(v)
          deserialize(source.instance_variable_get(v), target.instance_variable_get(v))
        elsif source.instance_variable_get(v).class == Array
          t = target.instance_variable_get(v)
          source.instance_variable_get(v).each_with_index do |va,i|
            if i >= t.size
              t << va
            end
            deserialize(va,t[i])
          end
        else
          target.instance_variable_set(v,source.instance_variable_get(v))
        end
      end
    end
  end

  def checkpointed(outbase)
    unless outbase
      add_error("Failed to get output base #{outbase} for #{self}")
      return false
    end
    cp_path = File.join(outbase,"checkpoint.yml")
    if File.exists?(cp_path)
      ser = YAML::load_file(cp_path)
      @@mutex.synchronize { self.class.deserialize(ser,self) }
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
