# Copyright (c) 2014, Stuart Glenn, OMRF
# Distributed under a BSD 3-Clause
# Full license available in LICENSE.txt distributed with this software

class Optical::PeakCaller::MacsMerged < Optical::PeakCaller::Macs

  def initialize(name,treatments,controls,opts)
    super
    raise ArgumentError,"Too few treatments (< 2) for #{@name}" if @treatments.size < 2
    @opts = opts
    @treatments_name = (@opts.delete(:treatment_name) || @treatments.first.safe_name).tr(" ",'_').tr("/","_")
    @controls_name = (@opts.delete(:control_name) || @controls.first.safe_name).tr(" ",'_').tr("/","_")
  end

  def find_peaks(output_base,conf)
    # We want a single merged CONTROL sample for all peak calling
    if @controls.size > 1
      control = Optical::Sample.new("#{@controls_name}_pooled",[])
      control.analysis_ready_bam = pool_bams_of_samples(@controls,
                                             File.join(conf.output_base,output_base,@controls_name),
                                             conf)
      return false unless control.analysis_ready_bam
      @controls = [control]
    end

    # We will also use a merged TREATMENT for pseudo reps & final peak calling
    if @treatments.size > 1
      treatment = Optical::Sample.new("#{@treatments_name}_pooled",[])
      treatment.analysis_ready_bam = pool_bams_of_samples(@treatments,
                                                  File.join(conf.output_base,output_base,@treatments_name),
                                                  conf)
      return false unless treatment.analysis_ready_bam
      @treatments = [treatment]
    end

    # We probably want to visualize this merged bams
    vis_output_base = File.join(Optical::ChipAnalysis::DIRS[:vis],name)
    Dir.mkdir(vis_output_base) unless Dir.exists?(vis_output_base)
    (@controls+@treatments).each do |ct|
      next if nil == ct
      dir = File.join(vis_output_base,ct.safe_name)
      Dir.mkdir(dir) unless Dir.exists?(dir)
      ct.checkpointed(dir) do |out,s|
        ct.bam_visual = Optical::ChipBamVisual.new(out,s.analysis_ready_bam,conf)
        ct.bam_visual.create_files()
      end
    end
    super
  end
end
