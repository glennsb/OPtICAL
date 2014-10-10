BEGIN {
  if ("" == base) {
    print "Missing output base, specify via -v base=";
    exit 1;
  } else if ( "" == reps ) {
    print "Missing number of replicates via -v reps=";
    exit 1;
  }
}

/^@/ {
  for(i=0;i<reps;i++) {
    file=base"_"i+1".sam";
    print $0 > file;
  }
  next;
}

{
  file=base"_"(NR%reps)+1".sam";
  print $0 > file;
}
