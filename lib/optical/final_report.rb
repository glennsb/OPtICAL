# Copyright (c) 2014, Stuart Glenn, OMRF
# Distributed under a BSD 3-Clause
# Full license available in LICENSE.txt distributed with this software

require 'erb'
require 'pathname'

class Optical::FinalReport
  def initialize(conf)
    @conf = conf
    @base_wd = Pathname.new(@conf.output_base)
  end


  def save_report(file)
    puts render()
    return true
  end

  private

  def make_table(lines)
    maxes = Array.new(lines[0].size,0)
    lines.each do |l|
      l.each_with_index do |s,i|
        maxes[i] = s.length if s.length > maxes[i]
      end
    end
    lines.insert(1,%w(-)*lines[0].size)
    lines[1].each_with_index do |l,i|
      lines[1][i] = l*maxes[i]
    end
    lines.map do |l|
      line = "|"
      l.each_with_index do |s,i|
        line += " #{s.ljust(maxes[i]," ")} |"
      end
      line
    end.join("\n")
  end

  def md_path_link(p,name=File.basename(p))
    link = "[#{name}]"
    if p =~ /^#{File::SEPARATOR}/
      link += "(#{Pathname.new(p).relative_path_from(@base_wd)})"
    else
      link += "(#{p})"
    end
    link
  end

  def report_peaks()
    lines = [%W(Name Caller Type Peak\ File NSC RSC Num\ Peaks Width\ Median
                Width\ Mean Width\ SD Enrichment\ Mean Enrichment\ SD)]
    @conf.peak_callers do |p|
      paths = p.peak_path
      nums = p.num_peaks
      paths.size.times do |i|
        line = [p.to_s, p.class.to_s]
        if paths.size > 1 && i == 0
          line << "conservative"
        elsif paths.size > 1 && i == 1
          line << "optimal"
        else
          line << "*not idr*"
        end
        (nsc,rsc) = p.load_cross_correlation()
        line += [md_path_link(paths[i]),nsc,rsc,nums[i].to_s]
        pipe = IO.popen(%W(summarize_peaks_width_enrichment.R #{paths[i].shellescape}))
        data = pipe.readlines.last.chomp.split(/\t/)
        line += data
        pipe.close
        lines << line
      end
    end
    make_table(lines)
  end

  def report_bams()
    lines = [%W(Bam Fragment Alignments)]
    samples = @conf.peak_callers.map {|pc| pc.treatments + pc.controls}.flatten.compact.uniq
    samples.map {|s| [s.analysis_ready_bam,s]}.each do |bam,s|
      name = File.join( File.basename(File.dirname(bam.path)), File.basename(bam.path) )
      lines << [md_path_link(bam.path,name), bam.fragment_size.to_s, bam.num_alignments.to_s]
    end
    make_table(lines)
  end

  def report_libraries()
    lines = [%W(Sample Fastq FastQC)]
    counts_headers = get_library_complexity_count_headers()
    lines[0] += counts_headers.map{|s| s.to_s.tr("_"," ")}
    @conf.samples do |s|
      s.libraries.each_with_index do |lib,i|
        name = lib.fastq_paths.map{|f| File.basename(f) }.join(",")
        fastqc = lib.fastqc_paths.map {|f| md_path_link(f,"fastqc")}.join(", ")
        line = [s.to_s, name, fastqc]
        lib.load_stats()
        counts = lib.mapping_counts
        counts_headers.each do |h|
          line << counts[h].to_s
        end
        lines << line
      end
    end
    make_table(lines)
  end

  def get_library_complexity_count_headers()
    #TODO this will screw up with a mix of single & paired end
    s=@conf.samples().first.last #samples is a hash, so first gives us the name, object
    s.libraries.first.load_stats()
    s.libraries.first.mapping_counts.keys
  end

  def render
    ERB.new(get_template().chomp,0,'-').result(binding)
  end

  def get_template()
    <<EOF
OPtICAL Run Report
==================

Results from OPtICAL version <%= Optical::VERSION %> on <%= Time.now().iso8601() %>

Peaks
-----

<%= report_peaks() %>

BAMs
----

<%= report_bams() %>

Libraries
---------

<%= report_libraries() %>

Configuration
-------------

Alignment Filter

: <%= @conf.alignment_filter %>
EOF
  end
end
