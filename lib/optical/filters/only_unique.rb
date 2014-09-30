# Copyright (c) 2014, Stuart Glenn, OMRF
# Distributed under a BSD 3-Clause
# Full license available in LICENSE.txt distributed with this software

class Optical::Filters::OnlyUnique < Optical::Filters::NullFilter
  def filter_to(output_bam)
    if @lib.is_paired?
      only_unique_pairs(output_bam)
    else
      only_unique_singles(output_bam)
    end
  end

  def only_unique_pairs(output_bam)
    return false
  end

  def only_unique_singles(output_bam)
    File.delete(output_bam)
    cmd = @conf.cluster_cmd_prefix(free:1, max:12, sync:true, name:"filt_#{@name}") +
      %W(/bin/bash -o pipefail -o errexit -c)

    filt_cmd = "samtools view -h -q #{@conf.min_map_quality_score} #{@lib.aligned_path} |" +
      "awk -f #{File.join(File.dirname(__FILE__),"single_end_only_unique.awk")} | " +
      "samtools view -Sbh - > #{output_bam}"
    cmd << "\"#{filt_cmd}\""
    puts cmd.join(" ") if @conf.verbose
    unless system(*cmd)
      return false
    end
    @lib.filtered_path = output_bam
    return true
  end
end
