# Export existing inputs for review only; does not fit or modify a model.
args <- commandArgs(trailingOnly=TRUE)
stopifnot(length(args)==2)
root <- normalizePath(args[1],mustWork=TRUE)
target <- args[2]
stopifnot(startsWith(target,paste0(root,'/')))
dir.create(target,recursive=TRUE,showWarnings=FALSE)
expected <- c(prepandemic=37127L,latest=3563L,pooled=40690L)
index <- list(); fields <- list()
for(scope in names(expected)) {
  path <- file.path(root,scope,'derived','analysis_frame.rds')
  d <- readRDS(path)
  stopifnot(!anyDuplicated(d$SEQN), !anyNA(d$eligible), sum(d$eligible)==expected[[scope]])
  dest <- file.path(target,scope);dir.create(dest,showWarnings=FALSE)
  write.csv(d,file.path(dest,'broad_frame.csv'),row.names=FALSE,na='',fileEncoding='UTF-8')
  write.csv(d[d$eligible,,drop=FALSE],file.path(dest,'complete_cases.csv'),row.names=FALSE,na='',fileEncoding='UTF-8')
  # Verify CSV readback; RDS retains exact floating-point values and factor levels.
  cc <- read.csv(file.path(dest,'complete_cases.csv'))
  stopifnot(nrow(cc)==expected[[scope]],identical(cc$SEQN,as.integer(d$SEQN[d$eligible])) || all(cc$SEQN==d$SEQN[d$eligible]))
  index[[scope]] <- data.frame(scope,broad_rows=nrow(d),design_valid=sum(d$design_valid),complete_case_rows=sum(d$eligible),ra=sum(d$ra[d$eligible]==1),asthma=sum(d$asthma[d$eligible]==1),columns=ncol(d))
  fields[[scope]] <- do.call(rbind,lapply(names(d),function(v)data.frame(scope,field=v,r_class=paste(class(d[[v]]),collapse=';'),levels=if(is.factor(d[[v]]))paste(levels(d[[v]]),collapse=';')else'',missing_broad=sum(is.na(d[[v]])),missing_complete=sum(is.na(d[[v]][d$eligible])))))
}
write.csv(do.call(rbind,index),file.path(target,'frame_inventory.csv'),row.names=FALSE)
write.csv(do.call(rbind,fields),file.path(target,'frame_schema.csv'),row.names=FALSE)
cat('Review export verified; no models run.\n')
