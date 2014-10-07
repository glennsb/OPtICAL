# Copyright (c) 2014, Stuart Glenn, OMRF
# Distributed under a BSD 3-Clause
# Full license available in LICENSE.txt distributed with this software

class Optical::PeakCaller::Macs < Optical::PeakCaller
  def find_peaks(output_base,conf)
    output_base = File.join(output_base,safe_name)
    @pair.each do |s|
      unless sample_ready?(s)
        @errors << "The sample #{s} is not ready, the bam is missing"
        return false
      end
    end

    #if @pair[0].has_paired? != @pair[1].has_paired?
      #@errors << "This comparison mixes Singled & Paired end samples, that might be bad"
      #return false
    #end

    cmd = conf.cluster_cmd_prefix(free:4, max:8, sync:true, name:"#{self.safe_name}") +
      %W(macs2 callpeak --bdg -f BAM -t #{@pair[0].analysis_ready_bam.path} -c #{@pair[1].analysis_ready_bam.path}
         -n #{output_base} --bw #{@pair[0].analysis_ready_bam.fragment_size}) +
      @cmd_args
    puts cmd.join(" ") if conf.verbose
    unless system(*cmd)
      @errors << "Failed to execute macs for #{self}: #{$?.exitstatus}"
      return false
    end
    return true
  end
end
