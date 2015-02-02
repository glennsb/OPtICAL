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
    report = render()
    File.open("#{file}.md","w") do |out|
      out.puts report
    end
    File.open("#{file}.html","w") do |out|
      out.puts html_wrap_report(report)
    end
    return true
  end

  private

  def make_table(lines)
    maxes = Array.new(lines[0].size,0)
    lines.each do |l|
      l.each_with_index do |s,i|
        if s
          maxes[i] = s.length if s.length > maxes[i]
        else
          maxes[i] = 0 if 0 > maxes[i]
        end
      end
    end
    lines.insert(1,%w(-)*lines[0].size)
    lines[1].each_with_index do |l,i|
      lines[1][i] = l*maxes[i]
    end
    lines.map do |l|
      line = "|"
      l.each_with_index do |s,i|
        if s
          line += " #{s.ljust(maxes[i]," ")} |"
        else
          line += " #{' '*maxes[i]} |"
        end
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
    lines = [['Name', 'Caller', 'Type', 'NSC', 'RSC', 'Num Peaks', 'Width Median',
                'Width Mean', 'Width SD', 'Enrichment Mean', 'Enrichment SD']]
    counts_headers = get_library_complexity_count_headers()
    lines[0] += counts_headers.map{|s| "treatment #{s}".tr("_"," ")}
    lines[0] += counts_headers.map{|s| "controls #{s}".tr("_"," ")}

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
        line += [nsc,rsc, md_path_link(paths[i],nums[i].to_s)]
        if File.exists?(paths[i])
          pipe = IO.popen(%W(summarize_peaks_width_enrichment.R #{paths[i].shellescape}))
          data = pipe.readlines.last
          if data
            data = data.chomp.split(/\t/)
          else
            data = [0]*5
            $stderr.puts "Warning no encodePeak data for #{p.to_s}"
          end
          line += data.map{|f| format("%.3f",f.to_f)}
          pipe.close
        else
          $stderr.puts "Warning, no peak file for #{p.to_s} can't find #{paths[i]}"
          line += [0]*5
        end
        line += peaker_samples_stats(p.treatments,counts_headers)
        line += peaker_samples_stats(p.controls,counts_headers)
        lines << line
      end
    end
    make_table(lines)
  end

  def peaker_samples_stats(samples,headers)
    if nil == samples || 0 == samples.size
      return headers.map {|h| ""}
    end
    sample = if 1 == samples.size
               samples[0]
             else
               @conf.sample(samples.map {|s| s.name}.join(" and ").tr(" ","_") + "_pooled")
             end
    counts = sample.mapping_counts()
    headers.map do |h|
      counts.fetch(h).to_s
    end
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
    lines = [%W(Sample FastQC)]
    counts_headers = get_library_complexity_count_headers()
    lines[0] += counts_headers.map{|s| s.to_s.tr("_"," ")}
    @conf.samples do |s|
      s.libraries.each_with_index do |lib,i|
        fastqc = lib.fastqc_paths.map {|f| md_path_link(f,"fastqc")}.join(", ")
        line = [s.to_s, fastqc]
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

  def html_wrap_report(report)
    <<EOF
<!DOCTYPE html>
<html><title>OptiCAL Report</title>
<xmp theme="simplex" style="display:none;">
#{report}
</xmp>
<script src="https://ngs.omrf.org/~glenns/strapdown/strapdown.js"></script>
</html>
EOF
  end

  def render
    ERB.new(get_template().chomp,0,'-').result(binding)
  end

  def get_template()
    <<EOF
OPtICAL Run Report
==================

Results from OPtICAL version <%= Optical::VERSION %> on <%= Time.now().to_s() %>

Peaks
-----

<%= report_peaks() %>

BAMs
----

<%= report_bams() %>

Libraries
---------

<%= report_libraries() %>

IGV Session
-----------

[XML Session File](igv_session.xml)

Configuration
-------------

Alignment Filter

: <%= @conf.alignment_filter %>

Remove Duplicates

: <%= @conf.remove_duplicates %>

Reference

: <%= @conf.reference_path %>

Min Mapping Quality Score

: <%= @conf.min_map_quality_score %>

Alignment Mask

: <%= @conf.alignment_masking_bed_path %>
EOF
  end
end
