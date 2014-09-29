#!/bin/bash
# Copyright (c) 2014, Stuart Glenn, OMRF
# Distributed under a BSD 3-Clause
# Full license available in LICENSE.txt distributed with this software

# This is an refactoring of the "mapqc.sh" rules from the hichip package

if [[ $# != 2 ]]; then
  echo -e "Usage: `basename ${0}` (pe|se) bam_file"
  exit 1
fi

set -e
set -o pipefail

endness=$1
shift

base=`basename "$@" .bam`

if [[ "z${endness}" == "zse" ]]; then
  samtools view "$@" | awk -F '\t' -v lib="${base}" '
    BEGIN {
      OFS="\t";
      unique_mapped_reads = 0;
      multiple_hit_reads = 0;
      unmapped_reads = 0;
    }
    {
      tags="";
      if ( ($2 == 0 || $2 == 16) ) {
        for(i=12;i<NF;i++) { tags=tags $i " ";}
        tags=tags $i;
        if ( tags ~ /XT:A:U/ ) {
          unique_mapped_reads++;
          if ( $3 ~ /chr([[:digit:]]+|[XY]|MT)/ ) {
            genomic_positions[$2":"$3":"$4]++;
          }
        } else if ( tags ~ /XT:A:R/ ) {
          multiple_hit_reads++;
        }
      } else if ( tags !~ /XT:A/ ) {
        unmapped_reads++;
      }
    }
    END {
      single_mapped_positions = 0;
      multi_mapped_positions = 0;
      for(i in genomic_positions) {
        if ( genomic_positions[i] == 1 ) {
          single_mapped_positions++;
        } else if ( genomic_positions[i] > 1 ) {
          multi_mapped_positions++;
        }
      }
      print "library", "# Uniq mapped reads", "# Multi hit reads", "# Unmapped reads",
            "# Total reads", "# Total mapped reads", "# Genomic positions single unique read mapped",
            "# Genomic positions >1 unique reads mapped", "# Total Genomic positions unique read mapped";
      print lib, unique_mapped_reads, multiple_hit_reads, unmapped_reads, unique_mapped_reads+multiple_hit_reads+unmapped_reads,
            unique_mapped_reads+multiple_hit_reads, single_mapped_positions,
            multi_mapped_positions, single_mapped_positions+multi_mapped_positions;
    }'
elif [[ "z${endness}" == "zpe" ]]; then
  samtools view "$@" | awk -F '\t' -v lib="${base}" '
    BEGIN {
      OFS="\t";
      all_pairs = 0;
      lastid="";
      id_counts=0;
      unique_mapped_pairs=0;
      single_ends_mapped_of_pair=0;
      both_multiple_hit_pairs=0;
      unmapped_pairs=0;
      single_multiple_hit_pairs=0;
      all_pairs=0;
      half_mapped_pairs=0;
      other=0;
    }
    {
      if (lastid == "") {
        lastid=$1;
        id_counts++;
        r1["flag"]=$2;
        r1["rname"]=$3;
        r1["pos"]=$4;
        r1["mapq"]=$5;
        r1["tags"]="";
        for(i=12;i<NF;i++) { r1["tags"]=r1["tags"] $i " ";}
        r1["tags"]=r1["tags"] $i;
        next;
      }

      if ( lastid == $1 ) {
        id_counts++;
        if ( id_counts == 2 ) {
          r2["flag"]=$2;
          r2["rname"]=$3;
          r2["pos"]=$4;
          r2["mapq"]=$5;
          r2["tags"]="";
          for(i=12;i<NF;i++) { r2["tags"]=r2["tags"] $i " ";}
          r2["tags"]=r2["tags"] $i;
        }
      } else if ( lastid != $1 ) {
        all_pairs++;
        if ( 2 == id_counts ) {
          if ( (r1["flag"] == 83 || r1["flag"] == 99) && (r2["flag"] == 163 || r2["flag"] == 147) ) {
            if ( r1["tags"] ~ /XT:A:U/ && r2["tags"] ~ /XT:A:U/ ) {
              unique_mapped_pairs++;
              if ( r1["rname"] ~ /chr([[:digit:]]+|[XY]|MT)/ ) {
                genomic_positions[r1["flag"]":"r1["rname"]":"r1["pos"]":"r2["rname"]":"r2["pos"]]++;
              }
            } else if ( r1["tags"] ~/XT:A:R/ && r2["tags"] ~ /XT:A:R/ ) {
              both_multiple_hit_pairs++;
            } else {
              single_multiple_hit_pairs++;
            }
          } else if ( (r1["flag"] == 83 || r1["flag"] == 99) && (r2["flag"] != 163 && r2["flag"] != 147) ) {
            single_ends_mapped_of_pair++;
          } else if ( (r1["flag"] != 83 && r1["flag"] != 99) && (r2["flag"] == 163 || r2["flag"] == 147) ) {
            single_ends_mapped_of_pair++;
          } else if ( (r1["tags"] ~ /XT/ && r2["tags"] !~ /XT/) || ( r1["tags"] !~ /XT/ && r2["tags"] ~ /XT/) ) {
            half_mapped_pairs++;
          } else if ( r1["tags"] !~ /XT/ && r2["tags"] !~ /XT/) {
            unmapped_pairs++;
          } else {
            other++;
          }
        }
        id_counts=1;
        lastid=$1;
        r1["flag"]=$2;
        r1["rname"]=$3;
        r1["pos"]=$4;
        r1["mapq"]=$5;
        r1["tags"]="";
        for(i=12;i<NF;i++) { r1["tags"]=r1["tags"] $i " ";}
        r1["tags"]=r1["tags"] $i;
      }

    }
    END {
      if ( 2 == id_counts ) {
        all_pairs++;
        if ( 2 == id_counts ) {
          if ( (r1["flag"] == 83 || r1["flag"] == 99) && (r2["flag"] == 163 || r2["flag"] == 147) ) {
            if ( r1["tags"] ~ /XT:A:U/ && r2["tags"] ~ /XT:A:U/ ) {
              unique_mapped_pairs++;
              if ( r1["rname"] ~ /chr([[:digit:]]+|[XY])/ ) {
                genomic_positions[r1["flag"]":"r1["rname"]":"r1["pos"]":"r2["rname"]":"r2["pos"]]++;
              }
            } else if ( r1["tags"] ~/XT:A:R/ && r2["tags"] ~ /XT:A:R/ ) {
              both_multiple_hit_pairs++;
            } else {
              single_multiple_hit_pairs++;
            }
          } else if ( (r1["flag"] == 83 || r1["flag"] == 99) && (r2["flag"] != 163 && r2["flag"] != 147) ) {
            single_ends_mapped_of_pair++;
          } else if ( (r1["flag"] != 83 && r1["flag"] != 99) && (r2["flag"] == 163 || r2["flag"] == 147) ) {
            single_ends_mapped_of_pair++;
          } else if ( (r1["tags"] ~ /XT/ && r2["tags"] !~ /XT/) || ( r1["tags"] !~ /XT/ && r2["tags"] ~ /XT/) ) {
            half_mapped_pairs++;
          } else if ( r1["tags"] !~ /XT/ && r2["tags"] !~ /XT/) {
            unmapped_pairs++;
          } else {
            other++;
          }
        }
      }
      single_mapped_positions = 0;
      multi_mapped_positions = 0;
      for(i in genomic_positions) {
        if ( genomic_positions[i] == 1 ) {
          single_mapped_positions++;
        } else if ( genomic_positions[i] > 1 ) {
          multi_mapped_positions++;
        }
      }
      print "library", "# Uniq mapped pairs", "# Multi hit both of pairs", "# Multi hit 1 of pair", "# Unmapped pairs",
            "# Total pairs", "# Total mapped pairs", "# Half mapped pairs", "# Unproperly mapped pairs", "# Genomic positions single unique pair mapped",
            "# Genomic positions >1 unique pairs mapped", "# Total Genomic positions unique pairs mapped";
      print lib, unique_mapped_pairs, both_multiple_hit_pairs, single_multiple_hit_pairs, unmapped_pairs,
            all_pairs, unique_mapped_pairs+both_multiple_hit_pairs+single_multiple_hit_pairs, half_mapped_pairs+single_ends_mapped_of_pair,
            other, single_mapped_positions, multi_mapped_positions, single_mapped_positions+multi_mapped_positions;
    }'
elif [[ "z${endness}" == "zpemem" ]]; then

  #cat "$@" | awk -F '\t' -v lib="${base}" '
  samtools view -F 256 "$@" | awk -F '\t' -v lib="${base}" '
    BEGIN {
      OFS="\t";
      all_pairs = 0;
      lastid="";
      id_counts=0;
    }
    {
      if (lastid == "") {
        lastid=$1;
        id_counts++;
        r1["flag"]=$2;
        r1["rname"]=$3;
        r1["pos"]=$4;
        r1["mapq"]=$5;
        for(i=12;i<NF;i++) { r1["tags"]+=i",";}
        r1["tags"]+=NF;
        next;
      }

      if ( lastid == $1 ) {
        id_counts++;
        if ( id_counts == 2 ) {
          r2["flag"]=$2;
          r2["rname"]=$3;
          r2["pos"]=$4;
          r2["mapq"]=$5;
          for(i=12;i<NF;i++) { r2["tags"]+=i",";}
          r2["tags"]+=NF;
        }
      } else if ( lastid != $1 ) {
        all_pairs++;
        if ( 2 == id_counts ) {
          if ( (r1["flag"] == 83 || r1["flag"]) && (r2["flag"] == 163 || r2["flag"] == 147) ) {
            if ( r1_mapq != 0 && r2_mapq != 0) {
              unique_mapped_pairs++;
              if ( r1["rname"] ~ /chr([[:digit:]]+|[XY])/ ) {
                genomic_positions[r1["flag"]":"r1["rname"]":"r1["pos"]":"r2["rname"]":"r2["pos"]]++;
              }
            } else if ( r1["mapq"] == 0 && r2["mapq"] == 0 ) {
              both_multiple_hit_pairs++;
            } else {
              single_multiple_hit_pairs++;
            }
          } else {
            unmapped_pairs++;
          }
        }
        id_counts=1;
        lastid=$1;
        r1["flag"]=$2;
        r1["rname"]=$3;
        r1["pos"]=$4;
        r1["mapq"]=$5;
        for(i=12;i<NF;i++) { r1["tags"]+=i",";}
        r1["tags"]+=NF;
      }

      #if ( ($2 == 83 || $2 == 99 || $2 == 163 || $2 == 147) ) {
        #if ( $2 == 83 || $2 == 99 ) {
          #r1_qname=$1;
          #r1_flag=$2;
          #r1_rname=$3;
          #r1_pos=$4;
          #r1_mapq=$5;
          #for(i=12;i<NF;i++) { r1_flags+=i",";}
          #r1_flags+=NF;
          #getline;
          #r2_qname=$1;
          #r2_flag=$2;
          #r2_rname=$3;
          #r2_pos=$4;
          #r2_map2=$5;
          #for(i=12;i<NF;i++) { r2_flags+=i",";}
          #r2_flags+=NF;

          #if ( r1_qname != r2_qname ) {
            #print r1_qname"\t"r2_qname;
            #next;
          #}

          #if ( r1_mapq != 0 && r2_mapq != 0) {
            #unique_mapped_pairs++;
            #if ( r1_rname ~ /chr([[:digit:]]+|[XY])/ ) {
              #genomic_positions[r1_flag":"r1_rname":"r1_pos":"r2_rname":"r2_pos]++;
            #}
          #} else if ( r1_mapq == 0 && r2_mapq == 0 ) {
            #both_multiple_hit_pairs++;
          #} else {
            #single_multiple_hit_pais++;
          #}
        #}
      #} else {
        #unmapped_reads++;
      #}
    }
    END {
      if ( 2 == id_counts ) {
        all_pairs++;
        if ( (r1["flag"] == 83 || r1["flag"]) && (r2["flag"] == 163 || r2["flag"] == 147) ) {
          if ( r1_mapq != 0 && r2_mapq != 0) {
            unique_mapped_pairs++;
            if ( r1["rname"] ~ /chr([[:digit:]]+|[XY])/ ) {
              genomic_positions[r1["flag"]":"r1["rname"]":"r1["pos"]":"r2["rname"]":"r2["pos"]]++;
            }
          } else if ( r1["mapq"] == 0 && r2["mapq"] == 0 ) {
            both_multiple_hit_pairs++;
          } else {
            single_multiple_hit_pairs++;
          }
        } else {
          unmapped_pairs++;
        }
      }
      single_mapped_positions = 0;
      multi_mapped_positions = 0;
      for(i in genomic_positions) {
        if ( genomic_positions[i] == 1 ) {
          single_mapped_positions++;
        } else if ( genomic_positions[i] > 1 ) {
          multi_mapped_positions++;
        }
      }
      print "library", "# Uniq mapped pairs", "# Multi hit both of pairs", "# Multi hit 1 of pair", "# Unmapped pairs",
            "# Total pairs", "# Total mapped pairs", "# Genomic positions single unique read mapped",
            "# Genomic positions >1 unique reads mapped", "# Total Genomic positions unique read mapped";
      print lib, unique_mapped_pairs, both_multiple_hit_pairs, single_multiple_hit_pairs, unmapped_pairs,
            all_pairs,
            unique_mapped_pairs+both_multiple_hit_pairs+single_multiple_hit_pairs, single_mapped_positions,
            multi_mapped_positions, single_mapped_positions+multi_mapped_positions;
    }'
else
  echo -e "Unknown endness, try se or pe"
  exit 1
fi
