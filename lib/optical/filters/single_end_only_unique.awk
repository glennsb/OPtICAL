BEGIN{
  FS="\t";
}
{
  if ($1 ~ /^@.*/) {
    print $0;
  } else if ($3 ~ /chr([[:digit:]]+|[XY]|MT)/) {
    tags="";
    for(i=12;i<NF;i++) { tags=tags $i " ";}
    tags=tags $i;
    if ( tags ~ /XT:A:U/ ) {
      print $0;
    }
  }
}
