# Copyright (c) 2014, Stuart Glenn, OMRF
# Distributed under a BSD 3-Clause
# Full license available in LICENSE.txt distributed with this software

class Optical::ChipAnalysis
  DIRS = {
    logs:"logs",
    align:"01_alignment",
    qc:"00_fastqc",
    vis:"02_visualization",
    peak:"03_peaks"
  }

  attr_reader :errs

  def initialize(stdout,stderr,conf)
    $stdout=stdout
    $stderr=stderr
    @conf = conf
    @conf.random_visualization_color() #we get one now to read the file out of threads
    @errs = []
    @errs_mutex = Mutex.new()
  end

  def run()
    return setup_directories() &&
      prep_samples_for_peak_calling() &&
      call_peaks() &&
      create_igv_session() &&
      create_final_report() && @errs.empty?
  end

  private

  def create_igv_session()
    i = Optical::IgvSession.new(@conf)
    i.write("igv_session")
  end

  def create_final_report()
    r = Optical::FinalReport.new(@conf)
    r.save_report("readme")
  end

  def setup_directories
    Dir.chdir(@conf.output_base)
    DIRS.each do |key,d|
      Dir.mkdir(d) unless File.exists?(d)
    end
  end

  def call_peaks()
    threader(@conf.peak_callers) do |p|
      do_find_peaks(p)
    end
  end

  def threader(enum,&block)
    on_error = Proc.new { |msg| add_error(msg) }
    Optical.threader(enum,on_error,&block)
  end

  def prep_samples_for_peak_calling()
    threader(@conf.samples) do |name,sample|
      fastqc_for_sample(sample) &&
      prepare_bam_for_sample(sample) &&
      prepare_visualization_for_sample(sample)
    end
  end

  def do_find_peaks(p)
    p.checkpointed(get_sample_dir_in_stage(p.safe_name,:peak,true)) do |outbase,o|
      unless o.find_peaks(outbase,@conf)
        add_error("Peak finding error: #{o.error()}")
        false
      else
        true
      end
    end
  end

  def fastqc_lib(outbase,lib,sample)
    lib.fastq_paths.each do |fastq|
      cmd = @conf.cluster_cmd_prefix(free:2, max:4, sync:true, name:"fastqc_#{sample.safe_name}") +
        %W(fastqc --extract -q -o #{outbase} #{fastq})
      puts cmd.join(" ") if @conf.verbose
      unless system(*cmd)
        add_error("Failure in fastqc of #{fastq} for #{sample.name} #{$?.exitstatus}")
        return false
      else
        fastqc_base = "#{File.join(@conf.output_base,outbase,
                         File.basename(File.basename(fastq,".gz"),".fastq"))}_fastqc"
        lib.add_fastqc_path("#{fastqc_base}.html")
        begin
          File.delete("#{fastqc_base}.zip")
        rescue
        end
      end
    end
    return true
  end

  def fastqc_for_sample(sample)
    qc_dir = File.join(DIRS[:qc],sample.safe_name)
    Dir.mkdir(qc_dir) unless File.exists?(qc_dir)
    sample.checkpointed(qc_dir) do |dir,s|
      !s.libraries.map { |lib| fastqc_lib(dir,lib,s) }.include?(false)
    end
  end

  def get_sample_dir_in_stage(safe_name,stage,skip_check)
    outbase = File.join(DIRS[stage],safe_name)
    if !skip_check && File.exists?(outbase)
      add_error("#{safe_name} dir already exists in #{DIRS[stage]} unable to process")
      return nil
    end
    Dir.mkdir(outbase) unless Dir.exists?(outbase)
    return outbase
  end

  def prepare_visualization_for_sample(sample)
    sample.checkpointed(get_sample_dir_in_stage(sample.safe_name,:vis,true)) do |out,s|
      puts "Preparing visualization files for #{s.name}'s bam (#{s.analysis_ready_bam})" #if @conf.verbose
      s.bam_visual = Optical::ChipBamVisual.new(out,s.analysis_ready_bam,@conf)
      unless s.bam_visual.create_files()
        add_error("Error in creating visual files: #{s.bam_visual.error()}")
        false
      else
        true
      end
    end
  end

  def prepare_bam_for_sample(sample)
    sample.checkpointed(get_sample_dir_in_stage(sample.safe_name,:align,true)) do |outbase,s|
      puts "Preparing bam #{s.name}" if @conf.verbose
      if (align_libs(s.libraries,outbase,s.safe_name) &&
          filter_libs(s.libraries,outbase,s.safe_name) &&
          finalize_libraries_for_sample(s,outbase) &&
          clean_intermediate_bams_for_sample(s) ) then
        if @conf.verbose
          puts "#{s} aligned to #{s.analysis_ready_bam} & has #{s.libraries.map {|l| l.qc_path}.join(", ")} alignment qc reports"
        end
        true
      else
        add_error("Error in preparing bam for #{sample}")
        false
      end
    end
  end

  def clean_intermediate_bams_for_sample(sample)
    sample.libraries.each do |l|
      [l.filtered_path, l.aligned_path].each do |b|
        if b && "" != b && File.exists?(b)
          File.delete(b)
        end
      end
    end
  end

  def filter_libs(libs,outbase,sample_safe_name)
    libs.each do |lib|
      filt_bam = lib.aligned_path.sub(/_(\d+\.bam)/,'_filtered_\1')
      filter = @conf.alignment_filter.new(lib,sample_safe_name,@conf)
      unless filter.filter_to(filt_bam)
        add_error("Unable to filter to #{filt_bam}")
        return false
      end
    end
    return true
  end

  # 1 or more libs became bams, should now merge to a single bam
  # remove duplicates & clean up 83 & 99 flags
  def finalize_libraries_for_sample(sample,outbase)
    final_bam = File.join(outbase,"#{sample.safe_name}_stillduped.bam")
    tmp_bam = File.join(outbase,"#{sample.safe_name}_tmp.bam")
    cmd = []

    # merge each library/lane instance & remove dupes maybe
    if @conf.remove_duplicates
      final_bam = File.join(outbase,"#{sample.safe_name}_deduped.bam")
      metrics_path = File.join(outbase,"#{sample.safe_name}_dedupe_metrics.txt")
      cmd = @conf.cluster_cmd_prefix(free:8, max:56, sync:true, name:"remove_dupe_#{sample.safe_name}") +
        %W(picard MarkDuplicates OUTPUT=#{tmp_bam} VALIDATION_STRINGENCY=LENIENT MAX_RECORDS_IN_RAM=6000000
           COMPRESSION_LEVEL=8 REMOVE_DUPLICATES=TRUE ASSUME_SORTED=true METRICS_FILE=#{metrics_path}) +
           sample.libraries.map {|l| "INPUT=#{l.filtered_path}" }
    else
      cmd = @conf.cluster_cmd_prefix(free:8, max:56, sync:true, name:"merge_#{sample.safe_name}") +
        %W(picard MergeSamFiles OUTPUT=#{tmp_bam} VALIDATION_STRINGENCY=LENIENT MAX_RECORDS_IN_RAM=6000000
           COMPRESSION_LEVEL=8 USE_THREADING=True ASSUME_SORTED=true SORT_ORDER=coordinate) +
           sample.libraries.map {|l| "INPUT=#{l.filtered_path}" }
    end
    puts cmd.join(" ") if @conf.verbose
    unless system(*cmd)
      add_error("Failure in mark dupes/merge of sample #{sample.safe_name} #{$?.exitstatus}")
      return false
    end

    # only get the first in pairs (83,99)
    if sample.has_paired?
      cmd = @conf.cluster_cmd_prefix(free:1, max:12, sync:true, name:"trim_pairs_#{sample.safe_name}") +
        %W(/bin/bash -o pipefail -o errexit -c)
      filt = "samtools view -h #{tmp_bam} | awk -F '\\t' '{if ((\\$1 ~ /^@/) || (\\$2==83) || (\\$2==99)) print \\$0}'" +
        "| samtools view -Shu - | samtools sort -@ 2 -m 4G -o - /tmp/#{sample.safe_name}_#{$$} > #{final_bam}"
      cmd << "\"#{filt}\""
      puts cmd.join(" ") if @conf.verbose
      unless system(*cmd)
        add_error("Failure removing second pairs of sample #{sample.safe_name} #{$?.exitstatus}")
        return false
      end
      File.delete(tmp_bam) if File.exists?(tmp_bam)
    else
      File.rename(tmp_bam,final_bam)
    end

    if @conf.alignment_masking_bed_path
      # We can do it with bamutils filter -excludedbed nostrand from the ngsutils package
      input_path = final_bam.dup
      final_bam.sub!(/\.bam/,"_masked.bam")
      cmd = @conf.cluster_cmd_prefix(free:2, max:8, sync:true, name:"mask_#{sample.safe_name}") +
        %W(bamutils filter #{input_path} #{final_bam} -excludebed #{@conf.alignment_masking_bed_path} nostrand)
      puts cmd.join(" ") if @conf.verbose
      unless system(*cmd)
        add_error("Failure masking #{sample.safe_name} #{$?.exitstatus}")
        return false
      end
      File.delete(input_path) if File.exists?(input_path)
    end

    cmd = @conf.cluster_cmd_prefix(free:1, max:4, sync:true, name:"index_#{sample.safe_name}") +
      %W(samtools index #{final_bam})
    puts cmd.join(" ") if @conf.verbose
    unless system(*cmd)
      add_error("Failure index of sample #{sample.safe_name} #{$?.exitstatus}")
      return false
    end

    sample.analysis_ready_bam = Optical::Bam.new(File.join(@conf.output_base,final_bam),sample.has_paired?)
    sample.analysis_ready_bam.fragment_size = @conf.default_fragment_size
    sample.analysis_ready_bam.dupes_removed = @conf.remove_duplicates
    if ! File.exists?(sample.analysis_ready_bam.path)
      add_error("Final bam for #{sample.safe_name} does not exist at #{sample.analysis_ready_bam}")
      return false
    end
    return true
  end

  def bwa_aln(lib_part,is_paired,lib_bam,sample_safe_name)
    cmd = @conf.cluster_cmd_prefix(free:1, max:48, sync:true, name:"bwa_#{sample_safe_name}", threads:@conf.bwa_threads) +
      %W(/bin/bash -o pipefail -o errexit -c)
    aln_threads = if @conf.bwa_threads > 1
                    @conf.bwa_threads/2
                  else
                    1
                  end
    name_sort = ""
    bwa_mode = "samse"
    if is_paired
      bwa_mode = "sampe"
      name_sort = "-n"
    end

    bwa_cmd = "bwa #{bwa_mode} " +
      "-r \\\"@RG\\tID:#{sample_safe_name}_#{lib_part.run}_#{lib_part.lane}\\tSM:#{sample_safe_name}\\tPL:Illumina\\tPU:#{lib_part.lane}\\\" " +
      @conf.reference_path
    lib_part.fastq_paths.each do |fp|
      aln = "bwa aln -t #{aln_threads} #{@conf.reference_path} #{fp}"
      bwa_cmd += " <(#{aln})"
    end
    bwa_cmd += " #{lib_part.fastq_paths.join(" ")}"
    bwa_cmd += "| samtools view -Shu - | samtools sort #{name_sort} -@ 2 -m 4G -o - /tmp/#{sample_safe_name}_#{$$} > #{lib_bam}"
    cmd << "\"#{bwa_cmd}\""

    puts cmd.join(" ") if @conf.verbose
    unless system(*cmd)
      add_error("Failure in bwa of library part for #{sample_safe_name} #{$?.exitstatus}")
      return false
    end
    lib_part.bam_path = File.join(@conf.output_base,lib_bam)
    return true
  end

  def bwa_mem(lib,lib_bam,sample_safe_name)
    cmd = @conf.cluster_cmd_prefix(free:1, max:48, sync:true, name:"bwa_#{sample.safe_name}_#{i}", threads:@conf.bwa_threads) +
      %W(/bin/bash -o pipefail -o errexit -c)
    bwa_cmd = "bwa mem -v 1 -M -t #{@conf.bwa_threads} " +
      "-R \\\"@RG\\tID:#{sample.name}_#{lib.run}_#{lib.lane}\\tSM:#{sample.name}\\tPL:Illumina\\tPU:#{lib.lane}\\\" " +
      @conf.reference_path
      #TODO update for libray parts
    bwa_cmd += " #{lib.parts.fastq_paths.join(" ")} "
    bwa_cmd += "| samtools view -Shu - | samtools sort -@ 2 -m 4G -o - /tmp/#{sample.safe_name}_#{i} > #{lib_bam}"
    cmd << "\"#{bwa_cmd}\""
    return false
  end

  def generate_lib_qc_report(lib,sample_safe_name)
    qc_bam = lib.aligned_path
    endness = "se"
    if lib.is_paired? then
      endness = "pe"
    end
    qc_file = lib.aligned_path.sub(/\.bam$/,"_alignment_qc.txt")
    File.unlink(qc_file) if File.exists?(qc_file)
    qc_cmd = @conf.cluster_cmd_prefix(free:1, max:12, sync:true, name:"align_qc_#{sample_safe_name}") +
      %W(/bin/bash -o pipefail -o errexit -c)
    qc_cmd += ["'library_complexity.sh #{endness} #{qc_bam}' > #{qc_file}"]
    puts qc_cmd.join(" ") if @conf.verbose
    unless system(*qc_cmd)
      add_error("Failure in qc bwa of library #{qc_bam} for #{sample_safe_name} #{$?.exitstatus}")
      return false
    end
    lib.qc_path = qc_file
    return true
  end

  def align_libs(libs,outbase,sample_safe_name)
    return threader(libs.each_with_index.to_a) do |lib,i|
      process_lib_parts(lib,i,outbase,sample_safe_name)
    end #each lib
  end

  def process_lib_parts(lib,i,outbase,sample_safe_name)
    threader(lib.parts.each_with_index.to_a) do |part,p|
      lib_bam = File.join(outbase,"#{sample_safe_name}_lib#{i}_part#{p}.bam")
      bwa_aln(part,lib.is_paired?,lib_bam,sample_safe_name)
    end #each lib part
    lib_bam = File.join(outbase,"#{sample_safe_name}_#{i}.bam")
    return false unless merge_library_parts(lib,lib_bam,sample_safe_name)
    return false unless generate_lib_qc_report(lib,sample_safe_name)
    return true
  end

  def merge_library_parts(lib,final_bam,sample_safe_name)
    cmd = @conf.cluster_cmd_prefix(free:8, max:56, sync:true, name:"merge_#{sample_safe_name}") +
      %W(picard MergeSamFiles OUTPUT=#{final_bam} VALIDATION_STRINGENCY=LENIENT MAX_RECORDS_IN_RAM=6000000
         COMPRESSION_LEVEL=8 USE_THREADING=True ASSUME_SORTED=true SORT_ORDER=coordinate) +
         lib.parts.map {|p| "INPUT=#{p.bam_path}" }
    puts cmd.join(" ") if @conf.verbose
    unless system(*cmd)
      add_error("Failure in merge of library parts #{final_bam} of sample #{sample_safe_name} #{$?.exitstatus}")
      return false
    end
    lib.parts.each do |p|
      begin
        File.delete(p.bam_path)
      rescue
      end
    end
    lib.aligned_path = final_bam
    return true
  end

  def add_error(msg)
    @errs_mutex.synchronize { @errs << msg }
  end
end
