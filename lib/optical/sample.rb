# Copyright (c) 2014, Stuart Glenn, OMRF
# Distributed under a BSD 3-Clause
# Full license available in LICENSE.txt distributed with this software

require 'optical/checkpointable'

class Optical::Sample
  include Optical::Checkpointable

  attr_reader :name

  attr_accessor :analysis_ready_bam, :bam_visual

  def initialize(name,libraries)
    @analysis_ready_bam = nil
    @bam_visual = nil
    @name = name
    @libs = libraries
  end

  def libraries
    return @libs.to_enum unless block_given?
    @libs.each do |l|
      yield l
    end
  end

  def has_paired?()
    @libs.any?{|l| l.is_paired?}
  end

  def safe_name()
    @safe_name ||= @name.tr(" ",'_').tr("/","_")
  end

  def to_s
    @name
  end

  def create_pseudo_replicates(num_replicates,output_base,conf)
    return nil unless analysis_ready_bam && File.exists?(analysis_ready_bam.path)
    return nil unless Dir.exists?(output_base)
    # shuffle the bam, and ever %num_replicates goes to different file, then sort those
    rep_base_name = "#{safe_name}_pseudo_replicate"
    outname = File.join(output_base,rep_base_name)
    cmd = conf.cluster_cmd_prefix(free:10, max:40, sync:true, name:"replicate_#{safe_name}") +
          %W(optical pseudoReplicateBam -b #{analysis_ready_bam.path} -o #{outname} -r #{num_replicates})
    unless system(*cmd)
      return nil
    end
    replicate_samples = []
    num_replicates.times do |r|
      rep = (r+1).to_s.rjust(2,"0")
      path = "#{outname}_#{rep}.bam"
      b = Optical::Bam.new(path,has_paired?())
      b.fragment_size = analysis_ready_bam.fragment_size()
      b.dupes_removed = analysis_ready_bam.dupes_removed
      rep = Optical::Sample.new("#{rep_base_name}_#{rep}",[])
      rep.analysis_ready_bam=b
      replicate_samples << rep
    end
    return replicate_samples
  end

  def add_error(msg)
    @errors ||= []
    @errors << msg
  end
end
