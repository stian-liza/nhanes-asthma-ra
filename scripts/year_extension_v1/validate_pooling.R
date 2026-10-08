.libPaths(c('outputs/original_proposal_20260928_v01/R_library','.Rlib',.libPaths()))
suppressPackageStartupMessages({library(survey);library(jsonlite)})
ROOT<-'/Volumes/Elements/NHANES_asthma_ra_extension_20261008_fresh_v1';O<-'outputs/year_extension_20261008_v01/pooled'
d<-readRDS(file.path(ROOT,'pooled/derived/analysis_frame.rds'));z<-d[d$eligible,];broad<-d[d$design_valid,];mods<-readRDS(file.path(ROOT,'pooled/derived/pooling_models.rds'));checks<-list()
psus<-unique(broad[,c('SDMVSTRA','SDMVPSU')]);psus$key<-paste(psus$SDMVSTRA,psus$SDMVPSU,sep='_')
for(n in names(mods)) {
 m<-mods[[n]];stopifnot(identical(m$survey.design$variables$SEQN,z$SEQN));X<-model.matrix(m)
 A<-solve(crossprod(X,X*as.numeric(m$weights)));score<-X*(as.numeric(residuals(m,type='working'))*as.numeric(m$weights));u<-rowsum(score,paste(z$SDMVSTRA,z$SDMVPSU,sep='_'))
 U<-matrix(0,nrow(psus),ncol(X));U[match(rownames(u),psus$key),]<-u;B<-matrix(0,ncol(X),ncol(X))
 for(h in unique(psus$SDMVSTRA)){v<-U[psus$SDMVSTRA==h,,drop=FALSE];j<-nrow(v);v<-sweep(v,2,colMeans(v),'-');B<-B+j/(j-1)*crossprod(v)}
 V<-A%*%B%*%A;err<-max(abs(V-vcov(m)));stopifnot(err<1e-9);checks[[n]]<-data.frame(model=n,independent_covariance_max_error=err,pass=TRUE)
}
write.csv(do.call(rbind,checks),file.path(O,'pooling_independent_validation.csv'),row.names=FALSE)
write_json(list(verdict='pass',models=length(mods),all_pass=TRUE),file.path(O,'pooling_independent_validation.json'),pretty=TRUE,auto_unbox=TRUE)
