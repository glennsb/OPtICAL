BEGIN {
  OFS="\t";
  lastid="";
  id_counts=0;
}
function at_least_one_unique(r1,r2) {
  if ( (r1["tags"] ~ /XT:A:U/) && (r2["tags"] ~ /XT:A:U/) ) {
    print r1["read"];
    print r2["read"];
  } else if ( (r1["tags"] ~ /XT:A:U/) && (r2["tags"] ~ /XT:A:R/) ) {
    print r1["read"];
    print r2["read"];
  } else if ( (r1["tags"] ~ /XT:A:R/) && (r2["tags"] ~ /XT:A:U/) ) {
    print r1["read"];
    print r2["read"];
  }
}

function only_unique(r1,r2) {
  if ((r1["tags"] ~ /XT:A:U/) && (r2["tags"] ~ /XT:A:U/) ) {
    print r1["read"];
    print r2["read"];
  }
}

function primary_alignment(r1,r2) {
  if ( (r1["tags"] ~ /XT:A:U/) && (r2["tags"] ~ /XT:A:U/) ) {
    print r1["read"];
    print r2["read"];
  } else if ( (r1["tags"] ~ /XT:A:U/) && (r2["tags"] ~ /XT:A:R/) ) {
    print r1["read"];
    print r2["read"];
  } else if ( (r1["tags"] ~ /XT:A:R/) && (r2["tags"] ~ /XT:A:U/) ) {
    print r1["read"];
    print r2["read"];
  } else if ( (r1["tags"] ~ /XT:A:R/) && (r2["tags"] ~ /XT:A:R/) ) {
    print r1["read"];
    print r2["read"];
  }
}

{
  if ( $1 ~ /^@/ )
  {
    # headers go straight through
    print $0;
    next;
  }
  if (lastid == "") {
    lastid=$1;
    id_counts=1;
    r1["read"] = $0;
    r1["flag"] = $2;
    r1["chr"] = $3;
    r1["tags"] = "";
    for(i=12;i<NF;i++) { r1["tags"]=r1["tags"] $i " ";}
    r1["tags"]=r1["tags"] $i;
    next;
  }

  if ( lastid == $1 ) {
    id_counts++;
    if ( id_counts == 2 ) {
      r2["read"] = $0;
      r2["flag"] = $2;
      r2["chr"] = $3;
      r2["tags"] = "";
      for(i=12;i<NF;i++) { r2["tags"]=r2["tags"] $i " ";}
      r2["tags"]=r2["tags"] $i;
    }
  } else if ( lastid != $1 ) {
    if ( 2 == id_counts ) {
      # two matching ends of a pair, should we include them?
      if ( (r1["flag"] == 83 || r1["flag"] == 99) && (r1["chr"] ~ /chr([[:digit:]]+|[XY]|MT)/) &&
           (r2["chr"] ~ /chr([[:digit:]]+|[XY]|MT)/) ) {
        if (filt == "at_least_one_unique") {
          at_least_one_unique(r1,r2);
        } else if ( filt == "only_unique") {
          only_unique(r1,r2);
        } else if ( filt == "primary") {
          primary_alignment(r1,r2);
        }
      }
    }
    id_counts=1;
    lastid=$1;
    r1["read"] = $0;
    r1["flag"] = $2;
    r1["chr"] = $3;
    r1["tags"]="";
    for(i=12;i<NF;i++) { r1["tags"]=r1["tags"] $i " ";}
    r1["tags"]=r1["tags"] $i;
  }

}
END {
  if ( 2 == id_counts ) {
    # two matching ends of a pair, should we include them?
    if ( (r1["flag"] == 83 || r1["flag"] == 99) && (r1["chr"] ~ /chr([[:digit:]]+|[XY]|MT)/) &&
         (r2["chr"] ~ /chr([[:digit:]]+|[XY]|MT)/) ) {
      if (filt == "at_least_one_unique") {
        at_least_one_unique(r1,r2);
      } else if ( filt == "only_unique") {
        only_unique(r1,r2);
      } else if ( filt == "primary") {
        primary_alignment(r1,r2);
      }
    }
  }
}
