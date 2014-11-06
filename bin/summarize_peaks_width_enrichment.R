#!/usr/bin/env Rscript

args <- commandArgs(trailingOnly = TRUE)

df <- read.table(args[1],header=FALSE)
sizes <- as.numeric(df[,3]) - as.numeric(df[,2])
cat( paste("median width","mean width","sd width","mean enrichment","sd enrichment",sep="\t"),"\n")
cat( paste(median(sizes),  mean(sizes),  sd(sizes), 
    mean( as.numeric(df[,7],na.rm=TRUE ) ), 
    sd( as.numeric(df[,7],na.rm=TRUE) ), sep="\t"), "\n")
