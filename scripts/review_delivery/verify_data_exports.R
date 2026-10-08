# Read-only check of every exported field against the actual RDS inputs.
args<-commandArgs(trailingOnly=TRUE);stopifnot(length(args)==1)
root<-args[1];checks<-0L
for(scope in c('prepandemic','latest','pooled')) {
 d<-readRDS(file.path(root,scope,'derived','analysis_frame.rds'))
 for(type in c('broad_frame','complete_cases')) {
  expected<-if(type=='broad_frame')d else d[d$eligible,,drop=FALSE]
  got<-read.csv(file.path(root,'github_review_release','exports',scope,paste0(type,'.csv')),check.names=FALSE)
  stopifnot(identical(names(got),names(expected)),nrow(got)==nrow(expected))
  for(v in names(expected)) {
   x<-expected[[v]];y<-got[[v]]
   if(is.factor(x)||is.character(x)) {x<-as.character(x);y<-as.character(y);y[y=='']<-NA_character_}
   if(is.logical(x)) y<-as.logical(y)
   if(is.numeric(x)) y<-as.numeric(y)
   test<-all.equal(x,y,tolerance=1e-12,check.attributes=FALSE)
   if(!isTRUE(test)) stop(paste(scope,type,v,paste(test,collapse="; ")))
   checks<-checks+1L
  }
 }
}
cat('PASS:',checks,'exported fields match actual RDS data (numeric tolerance 1e-12); no models run.\n')
