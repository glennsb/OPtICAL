BEGIN{
  FS="\t";
}
{
  if ($1 ~ /^@.*/) {
    print $0;
  } else if ($3 ~ /chr([[:digit:]]+|[XY]|MT)/) {
    print $0;
  }
}
