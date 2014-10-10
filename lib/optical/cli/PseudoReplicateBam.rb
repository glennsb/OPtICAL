# Copyright (c) 2014, Stuart Glenn, OMRF
# Distributed under a BSD 3-Clause
# Full license available in LICENSE.txt distributed with this software

class Optical::CLI::PseudoReplicateBam

  DEFAULT_REPLICATES=2
  AWK_SCRIPT = File.expand_path(File.join( File.dirname(__FILE__), "..", "make_replicate_sams.awk"))
  PERL_SCRIPT = File.expand_path(File.join( File.dirname(__FILE__), "..", "shuffle.perl"))

  def self.command_name
    "pseudoReplicateBam"
  end

  def self.desc
    "Randomly divide bam into pseudo replicates"
  end

  def self.opts(options)
    OptionParser.new do |opts|
      opts.banner = "Usage: optical [global options] #{command_name()} [-r NUM_REPS] [-o OUTPUT_PREFIX] -b INPUT.BAM "

      opts.on("-b","--bam FILE","The input bam to replicate") do |o|
        options.bam_path = File.expand_path(o)
      end

      opts.on("-o","--out FILE","Save output replicates with FILE as the prefix, defaults to INPUT+_replicate") do |o|
        options.output_prefix = File.expand_path(o)
      end

      opts.on("-r","--replicates NUM",Integer,"Number of replicate bam files to create, defaults to #{DEFAULT_REPLICATES}") do |conf|
        options.num_replicates = conf.to_i
      end

      opts.on("-h","--help","Show this help message") do
        puts opts
        exit(0)
      end
    end
  end

  def initialize(options,args)
    @options = options
    @options.num_replicates = DEFAULT_REPLICATES
    @args = args
    @errs = []
  end

  def run!()
    if !cli_opts_parsed?() || !cli_opts_valid?()
      @errs.each do |e|
        $stderr.puts "Error: #{e}"
      end
      $stderr.puts self.class.opts({}).help()
      exit(1)
    end

    begin
      ret = make_replicates()
    rescue => err
      $stderr.puts "Failure: #{err} (#{err.backtrace.first})"
      exit(1)
    end
    exit(0) if ret
    exit(1)
  end

  # TODO make this a classy object
  def make_replicates()
    sam_pipe_reader,sam_pipe_writer = IO.pipe

    sam_body_pid = fork {
      sam_pipe_reader.close
      $stdout.reopen(sam_pipe_writer)
      sam_pipe_writer.close
      cmd = %W(samtools view #{@options.bam_path})
      $stderr.puts cmd.join(" ")
      exec(*cmd)
    }

    perl_pipe_reader,perl_pipe_writer = IO.pipe

    sam_header_pid = fork {
      sam_pipe_reader.close
      sam_pipe_writer.close
      $stdout.reopen(perl_pipe_writer)
      perl_pipe_writer.close
      cmd = %W(samtools view -H #{@options.bam_path})
      $stderr.puts cmd.join(" ")
      exec(*cmd)
    }

    perl_pid = fork {
      perl_pipe_reader.close
      $stdin.reopen(sam_pipe_reader)
      sam_pipe_reader.close
      $stdout.reopen(perl_pipe_writer)
      perl_pipe_writer.close
      cmd=%W(perl #{PERL_SCRIPT})
      $stderr.puts cmd.join(" ")
      exec(*cmd)
    }
    sam_pipe_reader.close
    sam_pipe_writer.close

    awk_pid = fork {
      perl_pipe_writer.close
      $stdin.reopen(perl_pipe_reader)
      perl_pipe_reader.close
      cmd = %W(awk -vbase=#{@options.output_prefix}_tmp -vreps=#{@options.num_replicates} -f #{AWK_SCRIPT})
      $stderr.puts cmd.join(" ")
      exec(*cmd)
    }
    perl_pipe_reader.close
    perl_pipe_writer.close

    do_bail = false
    [sam_header_pid, sam_body_pid, perl_pid, awk_pid].each do |pid|
      if do_bail
        Process.kill(9,pid)
        Process.wait(pid)
      else
        Process.wait(pid)
        unless $?.success?
          @errs << "A child failed to exit cleanly, bailing out"
          do_bail = true
        end
      end
    end

    return false if do_bail

    @options.num_replicates.times do |r|
      r+=1;
      sam="#{@options.output_prefix}_tmp_#{r}.sam"
      bam="#{@options.output_prefix}_#{r.to_s.rjust(2,"0")}"
      reader,writer = IO.pipe
      view_pid = fork {
        reader.close()
        $stdout.reopen(writer)
        writer.close()
        cmd = %W(samtools view -Suh #{sam})
        exec(*cmd)
      }
      sorter_pid = fork {
        writer.close()
        $stdin.reopen(reader)
        reader.close()
        cmd = %W(samtools sort -@ 2 -m 4G - #{bam})
        exec(*cmd)
      }
      [view_pid,sorter_pid].each do |p|
        if do_bail
          Process.kill(9,p)
          Process.wait(p)
        else
          Process.wait(p)
          unless $?.success?
            @errs << "A child failed to exit cleanly, bailing out"
            do_bail = true
          end
        end
      end
      File.delete(sam) if File.exists?(sam)
    end

    return !do_bail
  end

  def cli_opts_parsed?()
    opts = self.class.opts(@options)
    begin
      opts.parse!(@args)
    rescue => err
      @errs << err.to_s
      return false
    end

    return true
  end

  def cli_opts_valid?()
    bam_readable?() &&
    num_replicates_valid?() &&
    output_valid?()
  end

  def bam_readable?()
    unless @options.bam_path
      @errs << "Missing bam argument"
      return false
    end
    unless File.file?(@options.bam_path) && File.readable?(@options.bam_path)
      @errs << "Bam, #{@options.bam_path} is not a readable file"
      return false
    end
    return true
  end

  def num_replicates_valid?()
    if ! @options.num_replicates || @options.num_replicates <= 1
      @errs << "Invalid number of replicates to create, please pick something > 1"
      return false
    end
    return true
  end

  def output_valid?()
    if nil == @options.output_prefix || "" == @options.output_prefix
      @options.output_prefix = File.basename(@options.bam_path,".bam")+"_replicate"
    end
    base = File.dirname(@options.output_prefix)
    unless base && Dir.exists?(base) && File.writable?(base)
      @errs << "Unable to write to named output location, #{base}"
      return false
    end
    @options.num_replicates.times do |r|
      if File.exists?( @options.output_prefix + r.to_s.rjust(2,"0") + ".bam")
        @errs << "A file already exists as what our new file will be, refusing to overwrite"
        return false
      end
    end
    return true
  end
end
