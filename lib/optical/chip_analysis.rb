# Copyright (c) 2014, Stuart Glenn, OMRF
# Distributed under a BSD 3-Clause
# Full license available in LICENSE.txt distributed with this software

class Optical::ChipAnalysis
  DIRS = {
    logs:"logs",
    align:"01_alignment",
    qc:"00_fastqc"
  }

  attr_reader :errs

  def initialize(stdout,stderr,conf)
    $stdout=stdout
    $stderr=stderr
    @conf = conf
    @errs = []
    @errs_mutex = Mutex.new()
  end

  def run()
    setup_directories()

    workers = []
    @conf.samples do |sample|
      workers << Thread.new do
        fastqc_for_sample(sample) &&
        prepare_bam_for_sample(sample)
      end
    end
    exits = []
    workers.each do |w|
      begin
        exits << w.value()
      rescue => err
        exits << false
        add_error("Error in worker thread: #{err} (#{err.backtrace.first}")
      end
    end

    if exits.any?{|e| !e}
      add_error("A bam prep thread failed")
      return false
    end

    return true if @errs.empty?
    return false
  end

  private

  def setup_directories
    Dir.chdir(@conf.output_base)
    Dir.mkdir(DIRS[:logs]) unless File.exists?(DIRS[:logs])
    Dir.mkdir(DIRS[:qc]) unless File.exists?(DIRS[:qc])
    Dir.mkdir(DIRS[:align]) unless File.exists?(DIRS[:align])
  end

  def fastqc_for_sample(sample)
    return true if @conf.skip_fastqc
    puts "Fastqc for #{sample.name}"
    outbase = File.join(DIRS[:qc],sample.safe_name)
    Dir.mkdir(outbase) unless File.exists?(outbase)
    sample.libraries.each do |lib|
      lib.fastq_paths.each do |fastq|
        cmd = @conf.cluster_cmd_prefix(free:2, max:4, sync:true, name:"fastqc_#{sample.safe_name}") +
          %W(fastqc --extract -q -o #{outbase} #{fastq})
        puts cmd.join(" ") if @conf.verbose
        case system(*cmd)
          when true
            fastqc_base = "#{File.join(@conf.output_base,outbase, File.basename(File.basename(fastq,".gz"),".fastq"))}_fastqc"
            lib.add_fastqc_path("#{fastqc_base}.html")
            begin
              File.delete("#{fastqc_base}.zip")
            rescue
            end
          when false
            add_error("Failure in fastqc of #{fastq} for #{sample.name} #{$?.exitstatus}")
            return false
          when nil
            add_error("Unable to execute fastqc #{$?.exitstatus}")
            return false
        end
      end #libs.fastqs
    end #sample.libs
    return true
  end

  def prepare_bam_for_sample(sample)
    puts "Preparing bam #{sample.name}" if @conf.verbose
    outbase = File.join(DIRS[:align],sample.safe_name)
    if File.exists?(outbase) && !@conf.skip_alignment
      add_error("#{sample.safe_name} dir already exists in #{DIRS[:align]} unable to process")
      return false
    end
    Dir.mkdir(outbase) unless Dir.exists?(outbase)

    return false unless align_libs(sample.libraries,outbase,sample.safe_name)

    return false unless filter_libs(sample.libraries,outbase,sample.safe_name)

    # 1 or more libs became bams, should now merge to a single bam
    # remove duplicates & clean up 83 & 99 flags
    return false unless finalize_libraries_for_sample(sample,outbase)

    clean_intermediate_bams_for_sample(sample) unless @conf.skip_alignment

    if @conf.verbose
      puts "#{sample} aligned to #{sample.analysis_ready_bam} & has #{sample.libraries.map {|l| l.qc_path}.join(", ")} alignment qc reports"
    end
    return true
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
    return true if @conf.skip_alignment
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
        %W(picard MergeSameFiles OUTPUT=#{tmp_bam} VALIDATION_STRINGENCY=LENIENT MAX_RECORDS_IN_RAM=6000000
           COMPRESSION_LEVEL=8 USE_THREADED=True ASSUME_SORTED=true SORT_ORDER=coordinate) +
           sample.libraries.map {|l| "INPUT=#{l.filtered_path}" }
    end
    unless @conf.skip_alignment
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

      unless @skip_alignment
        cmd = @conf.cluster_cmd_prefix(free:1, max:4, sync:true, name:"index_#{sample.safe_name}") +
          %W(samtools index #{final_bam})
        puts cmd.join(" ") if @conf.verbose
        unless system(*cmd)
          add_error("Failure index of sample #{sample.safe_name} #{$?.exitstatus}")
          return false
        end
      end
    end
    sample.analysis_ready_bam = File.join(@conf.output_base,final_bam)
    if ! File.exists?(sample.analysis_ready_bam)
      add_error("Final bam for #{sample.safe_name} does not exist at #{sample.analysis_ready_bam}")
      return false
    end
    return true
  end

  def bwa_aln(lib,lib_bam,sample_safe_name)
    cmd = @conf.cluster_cmd_prefix(free:1, max:48, sync:true, name:"bwa_#{sample_safe_name}", threads:@conf.bwa_threads) +
      %W(/bin/bash -o pipefail -o errexit -c)
    aln_threads = if @conf.bwa_threads > 1
                    @conf.bwa_threads/2
                  else
                    1
                  end
    name_sort = ""
    bwa_mode = "samse"
    if lib.is_paired?
      bwa_mode = "sampe"
      name_sort = "-n"
    end

    bwa_cmd = "bwa #{bwa_mode} " +
      "-r \\\"@RG\\tID:#{sample_safe_name}_#{lib.run}_#{lib.lane}\\tSM:#{sample_safe_name}\\tPL:Illumina\\tPU:#{lib.lane}\\\" " +
      @conf.reference_path
    lib.fastq_paths.each do |fp|
      aln = "bwa aln -t #{aln_threads} #{@conf.reference_path} #{fp}"
      bwa_cmd += " <(#{aln})"
    end
    bwa_cmd += " #{lib.fastq_paths.join(" ")}"
    bwa_cmd += "| samtools view -Shu - | samtools sort #{name_sort} -@ 2 -m 4G -o - /tmp/#{sample_safe_name}_#{$$} > #{lib_bam}"
    cmd << "\"#{bwa_cmd}\""

    unless @conf.skip_alignment
      puts cmd.join(" ") if @conf.verbose
      unless system(*cmd)
        add_error("Failure in bwa of library for #{sample_safe_name} #{$?.exitstatus}")
        return false
      end
    end
    lib.aligned_path = File.join(@conf.output_base,lib_bam)
    return true
  end

  def bwa_mem(lib,lib_bam,sample_safe_name)
    cmd = @conf.cluster_cmd_prefix(free:1, max:48, sync:true, name:"bwa_#{sample.safe_name}_#{i}", threads:@conf.bwa_threads) +
      %W(/bin/bash -o pipefail -o errexit -c)
    bwa_cmd = "bwa mem -v 1 -M -t #{@conf.bwa_threads} " +
      "-R \\\"@RG\\tID:#{sample.name}_#{lib.run}_#{lib.lane}\\tSM:#{sample.name}\\tPL:Illumina\\tPU:#{lib.lane}\\\" " +
      @conf.reference_path
    bwa_cmd += " #{lib.fastq_paths.join(" ")} "
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
    qc_cmd = @conf.cluster_cmd_prefix(free:1, max:12, sync:true, name:"align_qc_#{sample_safe_name}") +
      %W(/bin/bash -o pipefail -o errexit -c)
    qc_cmd += ["'library_complexity.sh #{endness} #{qc_bam}' > #{qc_file}"]
    unless @conf.skip_alignment
      puts qc_cmd.join(" ") if @conf.verbose
      unless system(*qc_cmd)
        add_error("Failure in qc bwa of library #{qc_bam} for #{sample_safe_name} #{$?.exitstatus}")
        return false
      end
    end
    lib.qc_path = qc_file
    return true
  end

  def align_libs(libs,outbase,sample_safe_name)
    libs.each_with_index do |lib,i|
      lib_bam = File.join(outbase,"#{sample_safe_name}_#{i}.bam")
      return false unless bwa_aln(lib,lib_bam,sample_safe_name)
      return false unless generate_lib_qc_report(lib,sample_safe_name)
    end #each lib
    return true
  end

  def add_error(msg)
    @errs_mutex.synchronize { @errs << msg }
  end
end
