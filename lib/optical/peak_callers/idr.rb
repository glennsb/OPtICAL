# Copyright (c) 2014, Stuart Glenn, OMRF
# Distributed under a BSD 3-Clause
# Full license available in LICENSE.txt distributed with this software

class Optical::PeakCaller::Idr < Optical::PeakCaller

  Idr = Struct.new(:peak_pair, :results, :passing_peaks)

  def initialize(name,treatments,controls,opts)
    super
    @idr_args = (opts[:idr_args] || "0.3 F p.value hg19").split(/ /)
    @idr_threshold = (opts[:idr_threshold] || 0.01).to_f
    @individual_peaks_limit = (opts[:individual_peaks_limit] || 0)
    @opts = opts
    @treatments_name = (@opts.delete(:treatment_name) || @treatments.first.safe_name).tr(" ",'_').tr("/","_")
    @controls_name = (@opts.delete(:control_name) || @controls.first.safe_name).tr(" ",'_').tr("/","_")
  end

  def to_s
    "#{@name} of #{@treatments_name} vs #{@controls_name}"
  end

  def safe_name
    "#{@name}_#{@treatments_name}_vs_#{@controls_name}".tr(" ",'_').tr("/","_")
  end

  def find_peaks(output_base,conf)
    # We want a single merged CONTROL sample for all peak calling
    control = Optical::Sample.new("#{@controls_name}_pooled",[])
    control.analysis_ready_bam = pool_bams_of_samples(@controls,
                                           File.join(Dir.getwd,output_base,@controls_name),
                                           conf)
    return false unless control.analysis_ready_bam

    # We will also use a merged TREATMENT for pseudo reps & final peak calling
    treatment = Optical::Sample.new("#{@treatments_name}_pooled",[])
    treatment.analysis_ready_bam = pool_bams_of_samples(@treatments,
                                                File.join(Dir.getwd,output_base,@treatments_name),
                                                conf)
    return false unless treatment.analysis_ready_bam

    # We probably want to visualize this merged bams
    vis_output_base = File.join(Optical::ChipAnalysis::DIRS[:vis],name)
    Dir.mkdir(vis_output_base) unless Dir.exists?(vis_output_base)
    {control => @control_vis, treatment => @treatment_vis}.each do |ct,vis|
      dir = File.join(vis_output_base,ct.safe_name)
      Dir.mkdir(dir) unless Dir.exists?(dir)
      ct.checkpointed(dir) do |out,s|
        vis = Optical::ChipBamVisual.new(out,s.analysis_ready_bam,conf)
        vis.create_files()
      end
    end

    peakers = @treatments.map do |t|
      peak_caller().new("idr",[t],[control],@opts)
    end
    individual_peakers = peakers.dup
    idrs = {}
    peakers.combination(2).each do |peak_pair|
      idrs[:individual] ||= []
      idrs[:individual] << Idr.new(peak_pair,nil)
    end

    errs_mutex = Mutex.new()
    on_error = Proc.new do |msg|
      errs_mutex.synchronize { @errors << msg }
    end

    idrs[:self_pseudo_replicates] = add_self_replicate_peakers(@treatments,control,output_base,
                                                               conf,peakers,on_error)
    return false unless idrs[:self_pseudo_replicates]

    idrs[:pooled_pseudo_replicates] = add_self_replicate_peakers([treatment],control,output_base,
                                                                 conf,peakers,on_error)
    return false unless idrs[:pooled_pseudo_replicates]

    merged_vs_merged_peaker = peak_caller().new("idr",[treatment],[control],@opts)
    peakers << merged_vs_merged_peaker

    Optical.threader(peakers,on_error) do |p|
      puts "Calling peaks for #{p}" if conf.verbose
      unless p.find_peaks(output_base,conf)
        on_error.call(p.error())
      else
        if individual_peakers.include?(p)
          p.trim_peaks!(@individual_peaks_limit,conf) if @individual_peaks_limit
        end
        puts "#{p.num_peaks.first} peaks for #{p}" #we get it here once, to avoid thread errors later
        true
      end
    end
    return false if has_errors?()

    # Do we need/want to save the intermediate bams?
    (idrs[:self_pseudo_replicates] + idrs[:pooled_pseudo_replicates] + [Idr.new([merged_vs_merged_peaker],nil)]).flatten.each do |idr|
      idr.peak_pair.each do |p|
        (p.treatments + p.controls).each do |s|
          File.delete(s.analysis_ready_bam.path) if File.exists?(s.analysis_ready_bam.path)
        end
      end
    end

    return false unless run_idr!(idrs,output_base,conf,on_error)

    plot_idrs!(idrs,output_base,conf,on_error)

    summarize_idr_peak_counts(idrs,output_base)

    return false unless create_final_peak_files(merged_vs_merged_peaker,
                                                output_base,conf,on_error)

    return @errors.empty?
  end

  def conservative_peak_path()
    @final_peak_paths["conservative"]
  end

  def optimal_peak_path()
    @final_peak_paths["optimal"]
  end

  def peak_path
    [conservative_peak_path, optimal_peak_path]
  end

  def num_peaks
    [@conservative_count, @optimal_count]
  end

  private

  def create_final_peak_files(peaker,output_base,conf,on_error)
    mutex = Mutex.new()
    @final_peak_paths = {}
    types_counts = {"conservative" => @conservative_count, "optimal" => @optimal_count}
    return Optical.threader(types_counts,on_error) do |type,count|
      puts "Getting #{type} #{count} of final peaks from #{peaker}"
      out = "final_#{type}_#{File.basename(peaker.peak_path)}"
      mutex.synchronize { @final_peak_paths[type] = File.join(output_base,out) }
      cmd = conf.cluster_cmd_prefix(wd:output_base, free:1, max:2, sync:true, name:"idr_final_#{type}_#{safe_name()}") +
        ["sort -k#{score_sort_column()} -n -r #{File.basename(peaker.peak_path)} | head -n #{count} | sort -k1,1 -k2,2n -k3,3n > #{out}"]
      puts cmd.join(" ") if conf.verbose
      unless system(*cmd)
        on_error.call("Failure in creating final #{type} for #{safe_name}")
        false
      else
        true
      end
    end
  end

  def summarize_idr_peak_counts(idrs,output_base)
    File.open( File.join(output_base,"idr_summary.txt"),"w" ) do |out|
      out.puts %W(type idr1_name idr1_peaks idr2_name idr2_peaks ratio).join("\t")
      idrs.each do |type,idr_set|
        idr_set.combination(2).each do |set_comparison|
          line = [type]
          set_comparison.each do |sc|
            name = sc.peak_pair.map {|pp| pp.to_s.sub(/^idr of /,'').sub(/ vs #{@controls_name}_pooled$/,'')}
            line += [name.join(" overlapped "), sc.passing_peaks]
          end
          if 0 == set_comparison[0].passing_peaks || 0 == set_comparison[1].passing_peaks
            line << 0
          else
            line << format("%.2f",set_comparison[0].passing_peaks.to_f/set_comparison[1].passing_peaks.to_f)
          end
          out.puts line.join("\t")
        end
        lines = idr_set.map {|i| i.passing_peaks}
        non_zeros = lines.select {|x| x>0}
        puts "#{type} had a max of #{lines.max} peaks under the #{@idr_threshold} threshold from #{non_zeros.size}"
        if non_zeros.size != lines.size
          puts "WARNING: #{type} had #{lines.size-non_zeros.size} with 0 passing overlaps"
        end
        non_zeros.combination(2) do |pair|
          pair.sort!
          if pair[1]/pair[0].to_f > 2.0
            puts "WARNING: #{type} had some passing not within the 2x (#{pair.join(", ")})"
          end
        end
      end
      @conservative_count = idrs[:individual].map {|i| i.passing_peaks}.max
      @optimal_count = idrs[:pooled_pseudo_replicates].map {|i| i.passing_peaks}.max
      line = ["final", "conservative (max individuals)", @conservative_count, "(original) optimal (pooled pseudo)", @optimal_count]
      if 0 == @conservative_count || 0 == @optimal_count
        line << 0
      else
        line << format("%.2f",@conservative_count.to_f/@optimal_count.to_f)
      end
      out.puts line.join("\t")
      c = [@conservative_count, @optimal_count].sort
      if c[1]/c[0].to_f > 2.0
        puts "WARNING: The conservative count & optimal count not within 2x #{c.join(", ")})"
      end
      @optimal_count = c.max
    end
  end

  def plot_idrs!(idrs,output_base,conf,on_error)
    script = "$11 <= #{@idr_threshold} {count++} END{print count}"
    idrs.each do |type,idr_set|
      passed = []
      idr_set.each do |i|
        if i.results != ""
          passed << File.basename(i.results)
          cmd = %W(awk #{script} #{i.results}-overlapped-peaks.txt)
          pipe = IO.popen(cmd)
          i.passing_peaks = pipe.readlines.last.chomp.to_i
          pipe.close
        else
          i.passing_peaks = 0
        end
      end
      if passed.size > 0
        out = "#{type}_"
        cmd = conf.cluster_cmd_prefix(wd:output_base, free:2, max:8, sync:true, name:"idr_plot_#{type}_#{safe_name()}") +
          %W(Rscript #{conf.idr_plot_script} #{passed.size} #{out}) + passed
        puts cmd.join(" ") if conf.verbose
        system(*cmd)
        true
      end
     end
  end

  def run_idr!(idrs,output_base,conf,on_error)
    Optical.threader(idrs.values.flatten(1),on_error) do |idr|
      if 0 == idr.peak_pair[0].num_peaks.first || 0 == idr.peak_pair[1].num_peaks.first
        idr.results = ""
      else
        out = File.join(output_base, "#{idr.peak_pair[0].safe_name}_AND_#{idr.peak_pair[1].safe_name}")
        cmd = conf.cluster_cmd_prefix(free:2, max:8, sync:true, name:"idr_#{File.basename(out)}") +
          %W(Rscript #{conf.idr_script} #{idr.peak_pair[0].peak_path} #{idr.peak_pair[1].peak_path}) +
          %W(-1 #{out}) + @idr_args + %W(--genometable=#{conf.genome_table_path})
        puts cmd.join(" ") if conf.verbose
        unless system(*cmd)
          #this can fail "safely", we'll just say in such a case there are no results
          out = ""
        end
        idr.results = out
      end
      true
    end
  end

  def add_self_replicate_peakers(treatments,control,output_base,conf,peakers,on_error)
    mutex = Mutex.new()
    peakers_mutex = Mutex.new()
    idr_set = []
    # split each treatment to 2 pseudo replicates, peak each against CONTROL
    problem = !Optical.threader(treatments,on_error) do |t|
      pseudo_replicates = t.create_pseudo_replicates(2,File.expand_path(output_base),conf)
      if pseudo_replicates && 2 == pseudo_replicates.size
        to_idr = []
        pseudo_replicates.each do |pr|
          p = peak_caller().new("idr",[pr],[control],@opts)
          to_idr << p
          peakers_mutex.synchronize { peakers << p }
        end
        mutex.synchronize { idr_set << Idr.new(to_idr,nil) }
      else
        on_error.call("Failed to make pseudo replicates for #{t}")
        false
      end # enough PRs
    end #thread each treatment
    return nil if problem
    return idr_set
  end

  def pool_bams_of_samples(samples,output_base,conf)
    pooled_path = "#{output_base}_pooled.bam"
    if 1 == samples.size then
      require 'fileutils'
      FileUtils.ln_s(samples[0].analysis_ready_bam.path,pooled_path) unless File.exists?(pooled_path)
    else
      return nil unless merge_bams_to(samples.map{|c| c.analysis_ready_bam.path},pooled_path,conf)
    end
    b = Optical::Bam.new(pooled_path,samples[0].analysis_ready_bam.paired?)
    b.fragment_size = samples.reduce(0) {|sum,c| sum+=c.analysis_ready_bam.fragment_size}/samples.size
    b.dupes_removed = samples[0].analysis_ready_bam.dupes_removed
    return b
  end

  def merge_bams_to(inputs,output,conf)
    cmd = conf.cluster_cmd_prefix(free:8, max:56, sync:true, name:"merge_#{safe_name}_#{File.basename(output)}") +
      %W(picard MergeSamFiles OUTPUT=#{output} VALIDATION_STRINGENCY=LENIENT MAX_RECORDS_IN_RAM=6000000
         COMPRESSION_LEVEL=8 USE_THREADING=True ASSUME_SORTED=true SORT_ORDER=coordinate) +
         inputs.map {|l| "INPUT=#{l}" }
    puts cmd.join(" ") if conf.verbose
    unless system(*cmd)
      @errors << "Failure in merging a pool of bams in #{name} #{$?.exitstatus}"
      return false
    end
    return true
  end
end
