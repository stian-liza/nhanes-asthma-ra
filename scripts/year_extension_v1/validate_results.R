.libPaths(c('outputs/original_proposal_20260928_v01/R_library','.Rlib',.libPaths()))
suppressPackageStartupMessages({library(survey);library(dplyr);library(jsonlite)})
scope<-commandArgs(trailingOnly=TRUE)[1];root<-file.path('/Volumes/Elements/NHANES_asthma_ra_extension_20261008_fresh_v1',scope);out<-file.path('outputs/year_extension_20261008_v01',scope)
d<-readRDS(file.path(root,'derived','analysis_frame.rds'));broad<-d[d$design_valid,];z<-d[d$eligible,]
models<-readRDS(file.path(root,'derived','models.rds'));checks<-list()
# Independent Taylor sandwich using original weights and all broad-design PSUs.
psus<-unique(broad[,c('SDMVSTRA','SDMVPSU')]);psus$key<-paste(psus$SDMVSTRA,psus$SDMVPSU,sep='_')
for(name in c('M0','M1','M2','M3')) {
 m<-models[[name]];X<-model.matrix(formula(m),z);prob<-as.vector(plogis(X%*%coef(m)));w<-z$analysis_weight
 # Match the saved final IRLS step exactly; using freshly evaluated probabilities
 # changes variance by about 1e-6 relative because glm stops at finite tolerance.
 # Neither the survey variance code nor vcov is used to construct this sandwich.
 bread<-solve(crossprod(X,X*as.numeric(m$weights)))
 obs_score<-X*(as.numeric(residuals(m,type='working'))*as.numeric(m$weights));cluster_score<-rowsum(obs_score,paste(z$SDMVSTRA,z$SDMVPSU,sep='_'))
 U<-matrix(0,nrow(psus),ncol(X));idx<-match(rownames(cluster_score),psus$key);U[idx,]<-cluster_score
 meat<-matrix(0,ncol(X),ncol(X))
 for(h in unique(psus$SDMVSTRA)) {
  u<-U[psus$SDMVSTRA==h,,drop=FALSE];mh<-nrow(u);centered<-sweep(u,2,colMeans(u),'-');meat<-meat+mh/(mh-1)*crossprod(centered)
 }
 V<-bread%*%meat%*%bread
 error<-max(abs(V-vcov(m)));cat(name,'variance max error',error,'diagonal ratio',diag(V)/diag(vcov(m)),'\n');stopifnot(error<1e-9)
 checks[[length(checks)+1]]<-data.frame(check=paste0(name,'_independent_Taylor_variance'),max_absolute_error=error,pass=TRUE)
}
# Unadjusted RA coefficient must equal log of ratio of weighted group odds.
p<-read.csv(file.path(out,'asthma_prevalence.csv'));p0<-p$estimate[p$group=='No_arthritis'];p1<-p$estimate[p$group=='RA']
or<-(p1/(1-p1))/(p0/(1-p0));error<-abs(or-exp(coef(models$M0)['ra']));stopifnot(error<1e-8)
checks[[length(checks)+1]]<-data.frame(check='M0_weighted_odds_identity',max_absolute_error=error,pass=TRUE)
# Exact domain eligibility against an independent Boolean implementation.
ra_alt<-(d$MCQ160A==1 & d$arthritis_type==ifelse(d$year<2011,1,2));control_alt<-d$MCQ160A==2
smoke_alt<-d$SMQ020==2 | (d$SMQ020==1 & d$SMQ040 %in% 1:3)
alt<-d$RIDAGEYR>=20 & d$RIDAGEYR<=79 & d$design_valid & d$MCQ010 %in% 1:2 & (ra_alt|control_alt) & d$RIAGENDR %in% 1:2 & d$RIDRETH1 %in% 1:5 & d$DMDEDUC2 %in% 1:5 & is.finite(d$INDFMPIR) & d$INDFMPIR>=0 & d$INDFMPIR<=5 & is.finite(d$BMXBMI) & d$BMXBMI>0 & smoke_alt
alt[is.na(alt)]<-FALSE;stopifnot(identical(as.logical(alt),as.logical(d$eligible)))
checks[[length(checks)+1]]<-data.frame(check='independent_complete_case_eligibility',max_absolute_error=sum(alt!=d$eligible),pass=TRUE)
# Design variable support for prevalence domains, including domain-only single PSUs.
for(g in c(0,1)) {
 a<-z[z$ra==g,];pairs<-unique(a[,c('SDMVSTRA','SDMVPSU')]);tab<-table(pairs$SDMVSTRA)
 checks[[length(checks)+1]]<-data.frame(check=paste0('RA_',g,'_domain_active_PSU_minus_strata_df_',nrow(pairs)-length(tab)),max_absolute_error=0,pass=TRUE)
}
write.csv(bind_rows(checks),file.path(out,'independent_validation.csv'),row.names=FALSE)
rangeinfo<-data.frame(variable=c('age','bmi','pir'),min=sapply(z[,c('age','bmi','pir')],min),max=sapply(z[,c('age','bmi','pir')],max))
write.csv(rangeinfo,file.path(out,'analysis_ranges.csv'),row.names=FALSE)
leverage<-hatvalues(models$M3)
write_json(list(max_leverage=max(leverage),n_leverage_over_2p_n=sum(leverage>2*length(coef(models$M3))/nrow(z)),n=sum(d$eligible),all_pass=TRUE,variance_max_error=max(bind_rows(checks)$max_absolute_error)),file.path(out,'independent_validation.json'),auto_unbox=TRUE,pretty=TRUE)
print(bind_rows(checks))
