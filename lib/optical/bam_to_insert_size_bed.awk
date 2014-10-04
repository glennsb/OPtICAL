BEGIN{
  FS="\t";
  OFS="\t";
  alignments=0;
  if ("" == base) {
    print "Missing output base via -v base=";
    exit 1;
  }
  if ("" == endness) {
    print "Missing endness style (se|pe) via -v endness=";
    exit 1;
  } else if ( ("se" == endness) && (""==size) ) {
    print "Missing fragment size since single end via -v size=";
    exit 1;
  }
}

function pe_bedder(path) {
  start=($4-1)
  if ( (($2==83) || ($2==147)) && ($9>0) ) {
    print $3,start,(start+$9),".","1","-" > path;
  } else if ( ((2==83) || ($2==147)) && ($9<0) ) {
    print $3,start,(start-$9),".","1","-" > path;
  } else if ( (($2==99) || ($2==163)) && ($9>0) ) {
    print $3,start,(start+$9),".","1","+" > path;
  } else if ( (($2==99) || ($2==163)) && ($9<0) ) {
    print $3,start,(start-$9),".","1","+" > path;
  }
}

function se_bedder(path,size) {
}

{
  alignments++;
  if ("pe" == endness) {
    sub(/-/,"",$9);
    tlens[$9]++;
    pe_bedder(base"_tmp.bed");
  } else if ("se" == endness) {
  }
}

END {
  print alignments > base"_num_alignments.txt";
  if ("pe" == endness) {
    output = " sort -k 2 -n -r|head -n 1|cut -f 1 >" base"_estimated_size.txt";
    for(tlen in tlens) {
      print tlen,tlens[tlen] | output;
    }
  }
}
