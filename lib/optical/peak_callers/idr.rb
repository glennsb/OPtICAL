# Copyright (c) 2014, Stuart Glenn, OMRF
# Distributed under a BSD 3-Clause
# Full license available in LICENSE.txt distributed with this software

require 'pathname'
require 'securerandom'

class Optical::PeakCaller::Idr < Optical::PeakCaller
  using Optical::StringExensions

  Idr = Struct.new(:peak_pair, :results, :passing_peaks, :name)

  REQUIRED_REPS = 2

  def initialize(name,treatments,controls,opts)
    super
    raise ArgumentError,"Too few treatments (< #{REQUIRED_REPS}) for #{@name}" if @treatments.size < REQUIRED_REPS
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
    control = nil
    # We want a single merged CONTROL sample for all peak calling
    if nil != @controls && @controls.size > 0
      control = conf.sample(@controls.map {|s| s.name}.join(" and ").tr(" ","_") + "_pooled")
    end

    # We will also use a merged TREATMENT for pseudo reps & final peak calling
    treatment = conf.sample(@treatments.map {|s| s.name}.join(" and ").tr(" ","_") + "_pooled")

    peakers = @treatments.map do |t|
      peak_caller().new("idr",[t],[control],@opts)
    end
    individual_peakers = peakers.dup
    idrs = {}
    peakers.combination(2).each do |peak_pair|
      idrs[:individual] ||= []
      idrs[:individual] << Idr.new(peak_pair,nil,nil,SecureRandom.hex(2))
    end

    unless idrs[:individual]
      @errors << "Not enough treatment samples for IDR"
      return false
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
        if individual_peakers.include?(p) && ! p.already_called?(output_base,conf)
          p.trim_peaks!(@individual_peaks_limit,conf) if @individual_peaks_limit
        end
        puts "#{p.num_peaks.first} peaks for #{p}" #we get it here once, to avoid thread errors later
        true
      end
    end
    return false if has_errors?()

    # Do we need/want to save the intermediate bams?
    (idrs[:self_pseudo_replicates] + idrs[:pooled_pseudo_replicates]).flatten.each do |idr|
      idr.peak_pair.each do |p|
        (p.treatments + p.controls).compact.each do |s|
          next if s == control || s == treatment
          File.delete(s.analysis_ready_bam.path) if File.exists?(s.analysis_ready_bam.path)
        end
      end
    end

    return false unless run_idr!(idrs,output_base,conf,on_error)

    plot_idrs!(idrs,output_base,conf,on_error)

    summarize_idr_peak_counts(idrs,output_base)

    return false unless create_final_peak_files(merged_vs_merged_peaker,
                                                output_base,conf,on_error)

    @merged_vs_merged_peaker = merged_vs_merged_peaker

    %w(conservative optimal).each do |type|
      type_peak_bed_path(type)
    end
    (idrs[:self_pseudo_replicates] + idrs[:pooled_pseudo_replicates]).flatten.each do |idr|
      idr.peak_pair.each do |p|
        p.clean()
      end
    end
    return @errors.empty?
  end

  def load_cross_correlation()
    if @merged_vs_merged_peaker
      @merged_vs_merged_peaker.load_cross_correlation()
    else
      if @normalized_strand_xcorr_coef && @relative_strand_xcorr_coef then
        return [@normalized_strand_xcorr_coef,@relative_strand_xcorr_coef]
      end
      treatment = File.basename(@treatments.last.analysis_ready_bam.path)
      IO.foreach( File.join( File.dirname(peak_path().first), "strand_cross_correlation.txt") ) do |line|
        if line =~ /^#{treatment}/
          parts = line.chomp.split(/\t/)
          @normalized_strand_xcorr_coef = parts[8]
          @relative_strand_xcorr_coef = parts[9]
        end
      end
      return [@normalized_strand_xcorr_coef,@relative_strand_xcorr_coef]
    end
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

  def type_peak_bed_path(type)
    @peak_bed_paths ||= {}
    if @peak_bed_paths[type] && File.exists?(@peak_bed_paths[type])
      return @peak_bed_paths[type]
    end
    @peak_bed_paths[type] = create_peak_bed(@final_peak_paths[type])
    @peak_bed_paths[type]
  end

  def conservative_peak_bed_path()
    type_peak_bed_path("conservative")
  end

  def optimal_peak_bed_path()
    type_peak_bed_path("optimal")
  end

  def peak_bed_path()
    [conservative_peak_bed_path(), optimal_peak_bed_path()]
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
      out = "final_#{type}_#{File.basename(peaker.peak_path.first)}"
      mutex.synchronize { @final_peak_paths[type] = File.join(output_base,out) }
      cmd = conf.cluster_cmd_prefix(wd:output_base, free:1, max:8, sync:true, name:"idr_final_#{type}_#{safe_name()}") +
        ["sort -k#{score_sort_column()} -n -r #{File.basename(peaker.peak_path.first)} | head -n #{count} | sort -k1,1 -k2,2n -k3,3n > #{out}"]
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
        new_dir = "idr_#{idr.name}"
        new_dir = File.join(output_base,new_dir)
        Dir.mkdir(new_dir) unless Dir.exists?(new_dir)
        out = "idr"
        p1 = Pathname.new(idr.peak_pair[0].peak_path.first).each_filename.to_a[-1]
        p2 = Pathname.new(idr.peak_pair[1].peak_path.first).each_filename.to_a[-1]
        cmd = conf.cluster_cmd_prefix(free:4, max:48, sync:true,
                                      name:"idr_#{idr.name}",
                                      wd:new_dir) +
          %W(Rscript #{conf.idr_script}
             #{File.join("..",p1)}
             #{File.join("..",p2)})+
          %W(-1 #{out}) + @idr_args + %W(--genometable=#{conf.genome_table_path})
        puts cmd.join(" ") if conf.verbose
        File.open( File.join(new_dir,"command.txt"), "w") do |o|
          o.puts cmd.join(" ")
        end
        unless system(*cmd)
          #this can fail "safely", we'll just say in such a case there are no results
          out = ""
        end
        idr.results = File.join(new_dir,out)
      end
      true
    end
  end

  def add_self_replicate_peakers(treatments,control,output_base,conf,peakers,on_error)
    mutex = Mutex.new()
    peakers_mutex = Mutex.new()
    idr_set = []

    # split each treatment to REQUIRED_REPS pseudo replicates, peak each against CONTROL
    problem = !Optical.threader(treatments,on_error) do |t|
      added_already_done = false
      pseudo_replicate_names = t.pseudo_replicate_names(REQUIRED_REPS,File.expand_path(output_base))
      if pseudo_replicate_names && REQUIRED_REPS == pseudo_replicate_names.size
        already_called = []
        pseudo_replicate_names.each do |pr|
          p = peak_caller().new("idr",[pr],[control],@opts)
          already_called << p if p.already_called?(output_base,conf)
        end
        if REQUIRED_REPS == already_called.size then
          peakers_mutex.synchronize { peakers += already_called }
          mutex.synchronize { idr_set << Idr.new(already_called,nil,nil,SecureRandom.hex(2)) }
          added_already_done = true
        end
      end
      if added_already_done
        true
      else
        pseudo_replicates = t.create_pseudo_replicates(REQUIRED_REPS,File.expand_path(output_base),conf)
        if pseudo_replicates && REQUIRED_REPS == pseudo_replicates.size
          to_idr = []
          pseudo_replicates.each do |pr|
            p = peak_caller().new("idr",[pr],[control],@opts)
            to_idr << p
            peakers_mutex.synchronize { peakers << p }
          end
          mutex.synchronize { idr_set << Idr.new(to_idr,nil,nil,SecureRandom.hex(2)) }
        else
          on_error.call("Failed to make pseudo replicates for #{t} #{pseudo_replicates.inspect}")
          if !t.analysis_ready_bam || !File.exists?(t.analysis_ready_bam.path)
            on_error.call("#{t} missing analysis ready bam")
          end
          if ! Dir.exists?(File.expand_path(output_base))
            on_error.call("#{t} missing output base dir")
          end
          false
        end # enough PRs
      end #if already called
    end #thread each treatment
    return nil if problem
    return idr_set
  end

end
