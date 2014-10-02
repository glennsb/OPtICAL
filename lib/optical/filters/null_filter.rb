# Copyright (c) 2014, Stuart Glenn, OMRF
# Distributed under a BSD 3-Clause
# Full license available in LICENSE.txt distributed with this software

class Optical::Filters::NullFilter
  def initialize(lib,name,conf)
    @lib = lib
    @name = name
    @conf = conf
  end

  def filter_to(output_bam)
    @lib.filtered_path = @lib.aligned_path
    return true
  end

  def filter_through_awk_script(script,output_bam,min_score=0,name_sort_first=false)
    File.delete(output_bam) if File.exists?(output_bam)
    bam_to_filter = @lib.aligned_path

    cmd = @conf.cluster_cmd_prefix(free:1, max:12, sync:true, name:"filt_#{@name}") +
      %W(/bin/bash -o pipefail -o errexit -c)

    if script.kind_of?(Array)
      script = "#{script[0]} -vfilt=#{script[1]}"
    end
    filt_cmd = "samtools view -h -q #{min_score} #{bam_to_filter} |" +
      "awk -f #{script} "
    if name_sort_first
      filt_cmd += "| samtools view -Sbuh - | samtools sort -@ 2 -m 4G -o - /tmp/sort_#{$$} > #{output_bam}"
    else
      filt_cmd += "| samtools view -Sbh - > #{output_bam}"
    end
    cmd << "\"#{filt_cmd}\""
    puts cmd.join(" ") if @conf.verbose
    unless system(*cmd)
      return false
    end
    @lib.filtered_path = output_bam
    return true
  end
end
