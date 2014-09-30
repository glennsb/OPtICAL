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
      @errs << "A bam prep failed"
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
    # DEBUGING, skip expensive ops as they work
    if File.exists?(outbase)
      add_error("#{sample.safe_name} dir already exists in #{DIRS[:align]} unable to process")
      return false
    end
    Dir.mkdir(outbase)

    return false unless filter_libs(sample.libraries,outbase,sample.safe_name)

    # 1 or more libs became bams, should now merge to a single bam
    return false unless join_libs(sample.libraries,outbase,sample.safe_name)

    # remove duplicates & clean up 83 & 99 flags

    return false
  end

  def filter_libs(libs,outbase,sample_safe_name)
    libs.each do |lib|
      filt_bam = lib.aligned_path.sub(/_(\d+\.bam)/,'_filtered_\1')
      filter = @conf.alignment_filter.new(lib,sample_safe_name,@conf)
      return false unless filter.filter_to(filt_bam)
    end
    return true
  end

  def join_libs(libs,outbase,sample_safe_name)
  end

  def bwa_aln(lib,lib_bam,sample_safe_name)
    cmd = @conf.cluster_cmd_prefix(free:1, max:48, sync:true, name:"bwa_#{sample_safe_name}", threads:@conf.bwa_threads) +
      %W(/bin/bash -o pipefail -o errexit -c)
    aln_threads = if @conf.bwa_threads > 1
                    @conf.bwa_threads/2
                  else
                    1
                  end
    bwa_mode = if lib.is_paired?
                 "sampe"
               else
                 "samse"
               end

    bwa_cmd = "bwa #{bwa_mode} " +
      "-r \\\"@RG\\tID:#{sample_safe_name}_#{lib.run}_#{lib.lane}\\tSM:#{sample_safe_name}\\tPL:Illumina\\tPU:#{lib.lane}\\\" " +
      @conf.reference_path
    lib.fastq_paths.each do |fp|
      aln = "bwa aln -t #{aln_threads} #{@conf.reference_path} #{fp}"
      bwa_cmd += " <(#{aln})"
    end
    bwa_cmd += " #{lib.fastq_paths.join(" ")}"
    bwa_cmd += "| samtools view -Shu - | samtools sort -@ 2 -m 4G -o - /tmp/#{sample_safe_name}_#{$$} > #{lib_bam}"
    cmd << "\"#{bwa_cmd}\""

    puts cmd.join(" ") if @conf.verbose
    unless system(*cmd)
      add_error("Failure in bwa of library #{i} for #{sample_safe_name} #{$?.exitstatus}")
      return false
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
      qc_bam = File.join(outbase,"#{sample_safe_name}_#{i}_namesorted")
      sort_cmd = @conf.cluster_cmd_prefix(free:1, max:12, sync:true, name:"namesort_#{sample_safe_name}_#{i}") +
        %W(samtools sort -n #{lib_bam} #{qc_bam})
      puts sort_cmd.join(" ") if @conf.verbose
      unless system(*sort_cmd)
        add_error("Failure in sorting by name the bam #{i} for #{sample_safe_name} #{$?.exitstatus}")
        return false
      end
      qc_bam += ".bam"
    end
    qc_file = File.join(outbase,"#{sample_safe_name}_#{i}_alignment_qc.txt")
    qc_cmd = @conf.cluster_cmd_prefix(free:1, max:12, sync:true, name:"align_qc_#{sample_safe_name}_#{i}") +
      %W(/bin/bash -o pipefail -o errexit -c)
    qc_cmd += ["'library_complexity.sh #{endness} #{qc_bam}' > #{qc_file}"]
    puts qc_cmd.join(" ") if @conf.verbose
    unless system(*qc_cmd)
      add_error("Failure in qc bwa of library #{i} for #{sample_safe_name} #{$?.exitstatus}")
      return false
    end
    lib.qc_path = qc_file
    if lib.is_paired? then
      File.delete(qc_bam)
    end
    return true
  end

  def align_libs(libs,outbase,sample_safe_name)
    libs.each_with_index do |lib,i|
      lib_bam = File.join(outbase,"#{sample_safe_name}_#{i}.bam")
      # align the fasq to the reference & sort that bam
      return false unless bwa_aln(lib,lib_bam,sample_safe_name)
      # generate QC .tab file
      return false unless generate_lib_qc_report(lib,sample_safe_name)
    end #each lib
    return true
  end

  def add_error(msg)
    @errs_mutex.synchronize { @errs << msg }
  end
end
